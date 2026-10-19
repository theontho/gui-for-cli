import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A child process launched by `ProcessSupervisor`.
///
/// Foundation makes the child the leader of its own process group, so
/// `terminate()` signals the whole tree: SIGTERM to the group, then SIGKILL after
/// the request's grace period. Completion follows the direct child's exit plus a
/// short drain of its pipes; descendants that keep the pipes open never delay it.
public final class SupervisedProcess: @unchecked Sendable {
  /// Chunks buffered by `output` before the oldest are dropped.
  public static let outputBufferLimit = 512

  public let id = UUID()
  /// Decoded output lines as they arrive, buffered in a bounded ring of the newest
  /// `outputBufferLimit` chunks. Finishes once the process completes.
  public let output: AsyncStream<ProcessOutputChunk>

  private let request: ProcessRequest
  private let queue = DispatchQueue(label: "dev.guiforcli.supervised-process")
  private let outputContinuation: AsyncStream<ProcessOutputChunk>.Continuation
  private let onSettled: @Sendable (SupervisedProcess) -> Void
  private let pidLock = NSLock()
  private var pid: Int32 = 0

  // Everything below is only touched on `queue`.
  #if os(macOS) || os(Linux)
    private var process: Process?
  #endif
  private var readers: [ProcessOutputStream: PipeReader] = [:]
  private var decoders: [ProcessOutputStream: UTF8LineDecoder] = [:]
  private var captures: [ProcessOutputStream: OutputCapture] = [:]
  private var termination: ProcessTermination?
  private var exit: ProcessExit?
  private var isFinishing = false
  private var drainWork: DispatchWorkItem?
  private var droppedLineCount = 0
  private var terminationRequested = false
  private var escalationPending = false
  private var settled = false
  private var waiters: [UUID: @Sendable (ProcessCompletion) -> Void] = [:]
  private var abandonedWaiters: Set<UUID> = []

  private init(request: ProcessRequest, onSettled: @escaping @Sendable (SupervisedProcess) -> Void)
  {
    self.request = request
    self.onSettled = onSettled
    (output, outputContinuation) = AsyncStream.makeStream(
      of: ProcessOutputChunk.self,
      bufferingPolicy: .bufferingNewest(Self.outputBufferLimit))
  }

  public var processIdentifier: Int32 {
    pidLock.withLock { pid }
  }

  /// Terminates the process tree: SIGTERM to the group now, SIGKILL after the
  /// grace period if any member survives. Returns immediately.
  public func terminate() {
    queue.async { self.requestTermination() }
  }

  /// Waits for the direct child to exit and its output to drain.
  ///
  /// Cancelling the waiting task, or reaching `timeout`, terminates the process
  /// tree and returns `.cancelled` / `.timedOut` right away; the supervisor keeps
  /// tracking the tree until it is gone.
  public func wait(timeout: Duration? = nil) async -> ProcessCompletion {
    let waiterID = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        addWaiter(waiterID, timeout: timeout) { continuation.resume(returning: $0) }
      }
    } onCancel: {
      queue.async { self.abandonWaiter(waiterID, with: .cancelled) }
    }
  }

  /// Blocks the calling thread until the process completes or `timeout` elapses.
  /// For synchronous callers only; async code uses `wait(timeout:)`.
  public func waitBlocking(timeout: Duration? = nil) -> ProcessCompletion {
    let semaphore = DispatchSemaphore(value: 0)
    let result = BlockingResult()
    addWaiter(UUID(), timeout: timeout) { completion in
      result.completion = completion
      semaphore.signal()
    }
    semaphore.wait()
    return result.completion ?? .cancelled
  }

  private func addWaiter(
    _ waiterID: UUID,
    timeout: Duration?,
    resume: @escaping @Sendable (ProcessCompletion) -> Void
  ) {
    queue.async {
      if let exit = self.exit {
        resume(.exited(exit))
      } else if self.abandonedWaiters.remove(waiterID) != nil {
        resume(.cancelled)
      } else {
        self.waiters[waiterID] = resume
        if let timeout {
          self.queue.asyncAfter(deadline: .now() + timeout.dispatchInterval) {
            self.abandonWaiter(waiterID, with: .timedOut)
          }
        }
      }
    }
  }

  /// Whether any member of the process group is still alive.
  public var isGroupAlive: Bool {
    let pid = processIdentifier
    guard pid > 1 else { return false }
    return kill(-pid, 0) == 0 || errno == EPERM
  }

  func signalGroup(_ signal: Int32) {
    let pid = processIdentifier
    // Never signal group 0/1: that would hit our own group or every process.
    guard pid > 1 else { return }
    kill(-pid, signal)
  }

  // MARK: - Launch

  #if os(macOS) || os(Linux)
    static func launch(
      _ request: ProcessRequest,
      register: (SupervisedProcess) -> Void,
      onSettled: @escaping @Sendable (SupervisedProcess) -> Void
    ) throws -> SupervisedProcess {
      let supervised = SupervisedProcess(request: request, onSettled: onSettled)
      let streams: [ProcessOutputStream] =
        request.mergesStandardError ? [.standardOutput] : [.standardOutput, .standardError]
      var pipes: [ProcessOutputStream: (read: Int32, write: Int32)] = [:]
      defer {
        for pipe in pipes.values { close(pipe.write) }
      }
      for stream in streams {
        pipes[stream] = try makePipe()
      }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: request.executable)
      process.arguments = request.arguments
      process.currentDirectoryURL = request.workingDirectory
      process.environment = request.environment
      process.standardInput = FileHandle.nullDevice
      let stdoutHandle = pipes[.standardOutput].map {
        FileHandle(fileDescriptor: $0.write, closeOnDealloc: false)
      }
      process.standardOutput = stdoutHandle
      process.standardError =
        pipes[.standardError].map { FileHandle(fileDescriptor: $0.write, closeOnDealloc: false) }
        ?? stdoutHandle
      process.terminationHandler = { finished in
        let termination: ProcessTermination =
          finished.terminationReason == .uncaughtSignal
          ? .signaled(finished.terminationStatus) : .exited(finished.terminationStatus)
        supervised.queue.async { supervised.childExited(termination) }
      }

      register(supervised)
      try supervised.queue.sync {
        do {
          try process.run()
        } catch {
          for pipe in pipes.values { close(pipe.read) }
          supervised.launchFailed()
          throw ProcessSupervisorError.launchFailed(
            executable: request.executable, message: error.localizedDescription)
        }
        supervised.process = process
        supervised.pidLock.withLock { supervised.pid = process.processIdentifier }
        #if os(Linux)
          supervised.watchChildExit(pid: process.processIdentifier)
        #endif
        for (stream, pipe) in pipes {
          supervised.startReading(stream, fileDescriptor: pipe.read)
        }
      }
      return supervised
    }

    #if os(Linux)
      /// Foundation on Linux learns that the child exited only once a socket the
      /// child inherits is closed, so a background descendant holding it would
      /// delay completion for its whole lifetime. Watch the child itself instead.
      /// `WNOWAIT` leaves the zombie for Foundation to reap; if Foundation reaped it
      /// first, its termination handler reports the exit.
      private func watchChildExit(pid: pid_t) {
        let thread = Thread { [self] in
          var info = siginfo_t()
          var result: Int32
          repeat {
            result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)
          } while result == -1 && errno == EINTR
          guard result == 0 else { return }
          let status = info._sifields._sigchld.si_status
          let termination: ProcessTermination =
            info.si_code == CLD_EXITED ? .exited(status) : .signaled(status)
          queue.async { self.childExited(termination) }
        }
        thread.name = "dev.guiforcli.supervised-process.wait"
        thread.start()
      }
    #endif

    private static func makePipe() throws -> (read: Int32, write: Int32) {
      var fds: [Int32] = [-1, -1]
      guard pipe(&fds) == 0 else {
        throw ProcessSupervisorError.launchFailed(
          executable: "pipe", message: String(cString: strerror(errno)))
      }
      // Keep both ends out of unrelated children spawned concurrently.
      for fd in fds {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
      }
      return (fds[0], fds[1])
    }
  #endif

  // MARK: - Queue-confined state machine

  private func startReading(_ stream: ProcessOutputStream, fileDescriptor: Int32) {
    decoders[stream] = UTF8LineDecoder()
    captures[stream] = OutputCapture(limit: request.captureLimit)
    readers[stream] = PipeReader(
      fileDescriptor: fileDescriptor,
      queue: queue,
      onData: { data in self.received(data, on: stream) },
      onEnd: { self.streamEnded(stream) })
  }

  private func received(_ data: Data, on stream: ProcessOutputStream) {
    captures[stream]?.append(data)
    guard let lines = decoders[stream]?.append(data) else { return }
    emit(lines, on: stream)
  }

  private func streamEnded(_ stream: ProcessOutputStream) {
    guard let reader = readers.removeValue(forKey: stream) else { return }
    reader.cancel()
    if termination != nil, readers.isEmpty {
      finish()
    }
  }

  private func childExited(_ termination: ProcessTermination) {
    // On Linux both the exit watcher and Foundation's handler may report.
    guard self.termination == nil else { return }
    self.termination = termination
    guard !readers.isEmpty else {
      finish()
      return
    }
    let work = DispatchWorkItem { [weak self] in self?.finish() }
    drainWork = work
    queue.asyncAfter(deadline: .now() + request.drainPeriod.dispatchInterval, execute: work)
  }

  private func emit(_ lines: [String], on stream: ProcessOutputStream) {
    guard !lines.isEmpty else { return }
    if case .dropped(let dropped) = outputContinuation.yield(
      ProcessOutputChunk(stream: stream, lines: lines))
    {
      droppedLineCount += dropped.lines.count
    }
  }

  private func finish() {
    guard !isFinishing, let termination else { return }
    isFinishing = true
    drainWork?.cancel()
    let openReaders = readers
    readers.removeAll()
    for reader in openReaders.values {
      // Read whatever is already buffered before closing our end.
      reader.drainAvailable()
      reader.cancel()
    }
    for stream in [ProcessOutputStream.standardOutput, .standardError] {
      emit(decoders[stream]?.finish() ?? [], on: stream)
    }
    #if os(macOS) || os(Linux)
      process = nil
    #endif
    outputContinuation.finish()
    let stdout = captures[.standardOutput] ?? OutputCapture(limit: 0)
    let stderr = captures[.standardError] ?? OutputCapture(limit: 0)
    let exit = ProcessExit(
      termination: termination,
      standardOutput: stdout.data,
      standardError: stderr.data,
      isStandardOutputTruncated: stdout.isTruncated,
      isStandardErrorTruncated: stderr.isTruncated,
      droppedOutputLineCount: droppedLineCount)
    self.exit = exit
    let waiting = waiters.values
    waiters.removeAll()
    for waiter in waiting {
      waiter(.exited(exit))
    }
    settleIfDone()
  }

  private func launchFailed() {
    outputContinuation.finish()
    settled = true
    onSettled(self)
  }

  private func requestTermination() {
    guard !terminationRequested, exit == nil || isGroupAlive else { return }
    terminationRequested = true
    signalGroup(SIGTERM)
    escalationPending = true
    queue.asyncAfter(deadline: .now() + request.terminationGracePeriod.dispatchInterval) {
      if self.isGroupAlive {
        self.signalGroup(SIGKILL)
      }
      self.escalationPending = false
      self.settleIfDone()
    }
  }

  private func abandonWaiter(_ waiterID: UUID, with completion: ProcessCompletion) {
    guard exit == nil else { return }
    guard let waiter = waiters.removeValue(forKey: waiterID) else {
      if completion == .cancelled {
        abandonedWaiters.insert(waiterID)
      }
      return
    }
    requestTermination()
    waiter(completion)
  }

  private func settleIfDone() {
    guard !settled, exit != nil, !escalationPending else { return }
    settled = true
    onSettled(self)
  }
}

/// Hands a completion from the supervisor queue to a blocked thread; the
/// semaphore orders the write before the read.
private final class BlockingResult: @unchecked Sendable {
  var completion: ProcessCompletion?
}

/// Retains up to `limit` bytes of a stream.
private struct OutputCapture {
  let limit: Int
  var data = Data()
  var isTruncated = false

  mutating func append(_ chunk: Data) {
    let remaining = limit - data.count
    if remaining > 0 {
      data.append(chunk.prefix(remaining))
    }
    if chunk.count > max(remaining, 0) {
      isTruncated = true
    }
  }
}

/// Non-blocking reader for one pipe; owns and closes its file descriptor.
private final class PipeReader {
  private static let readSize = 64 * 1024
  private let fileDescriptor: Int32
  private let source: DispatchSourceRead
  private let onData: (Data) -> Void
  private let onEnd: () -> Void

  init(
    fileDescriptor: Int32,
    queue: DispatchQueue,
    onData: @escaping (Data) -> Void,
    onEnd: @escaping () -> Void
  ) {
    self.fileDescriptor = fileDescriptor
    self.onData = onData
    self.onEnd = onEnd
    _ = fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL) | O_NONBLOCK)
    source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
    source.setEventHandler { [unowned self] in
      _ = readOnce()
    }
    source.setCancelHandler {
      close(fileDescriptor)
    }
    source.resume()
  }

  /// Reads until the pipe is empty or closed.
  func drainAvailable() {
    while readOnce() {}
  }

  func cancel() {
    source.cancel()
  }

  /// Returns whether data was read.
  private func readOnce() -> Bool {
    var buffer = Data(count: Self.readSize)
    let count = buffer.withUnsafeMutableBytes {
      read(fileDescriptor, $0.baseAddress, Self.readSize)
    }
    if count > 0 {
      onData(buffer.prefix(count))
      return true
    }
    if count == 0 || (errno != EAGAIN && errno != EINTR) {
      onEnd()
    }
    return false
  }
}
