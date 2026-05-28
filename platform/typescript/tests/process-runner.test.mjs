import assert from "node:assert/strict";
import test from "node:test";

const { createProcessManager, windowsAdminLauncherScript, windowsAdminWrapperScript } = await import("../dist/web/src/server/process-runner.js");

test("process manager captures successful output", async () => {
  const manager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  const result = await manager.runProcess(process.execPath, [
    "-e",
    "process.stdout.write('out'); process.stderr.write('err');",
  ], { env: process.env });

  assert.equal(result.exitCode, 0);
  assert.equal(result.stdout, "out");
  assert.equal(result.stderr, "err");
});

test("process manager truncates buffered stdout and stderr independently", async () => {
  const manager = createProcessManager({ maxOutputBytes: 3, maxErrorBytes: 2 });
  const stdoutChunks = [];
  const stderrChunks = [];

  const result = await manager.runProcess(process.execPath, [
    "-e",
    "process.stdout.write('abcdef'); process.stderr.write('wxyz');",
  ], {
    env: process.env,
    onStdout: (text) => stdoutChunks.push(text),
    onStderr: (text) => stderrChunks.push(text),
  });

  assert.equal(result.stdout, "abc");
  assert.equal(result.stderr, "wx");
  assert.equal(result.stdoutTruncated, true);
  assert.equal(result.stderrTruncated, true);
  assert.equal(stdoutChunks.join(""), "abcdef");
  assert.equal(stderrChunks.join(""), "wxyz");
});

test("process manager rejects and terminates on timeout", async () => {
  const manager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  await assert.rejects(
    manager.runProcess(process.execPath, ["-e", "setInterval(() => {}, 1000);"], {
      env: process.env,
      timeoutMs: 100,
    }),
    /Process timed out after 1 seconds\./,
  );
});

test("process manager rejects aborted runs", async () => {
  const manager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });
  const abortController = new AbortController();
  const promise = manager.runProcess(process.execPath, ["-e", "setInterval(() => {}, 1000);"], {
    env: process.env,
    signal: abortController.signal,
  });

  abortController.abort();

  await assert.rejects(promise, /Process cancelled\./);
});

test("Windows admin launcher script quotes arguments and keeps stderr encoding consistent", () => {
  const script = windowsAdminLauncherScript(
    { executable: "C:\\Tools\\run'it.exe", args: ["--name", "O'Brien", "C:\\Path With Spaces\\input.txt"] },
    { TOOL_HOME: "C:\\Tool's Home", REMOVE_ME: undefined },
    "C:\\Temp\\stdout.txt",
    "C:\\Temp\\stderr.txt",
    "C:\\Temp\\exit-code.txt",
  );

  assert.match(script, /Set-Item -LiteralPath 'Env:\\TOOL_HOME' -Value 'C:\\Tool''s Home'/);
  assert.match(script, /Remove-Item -LiteralPath 'Env:\\REMOVE_ME' -ErrorAction SilentlyContinue/);
  assert.match(script, /& 'C:\\Tools\\run''it.exe' @\('--name', 'O''Brien', 'C:\\Path With Spaces\\input.txt'\) > 'C:\\Temp\\stdout.txt' 2> 'C:\\Temp\\stderr.txt'/);
  assert.match(script, /\$_ \| Out-File -FilePath 'C:\\Temp\\stderr.txt' -Append -Encoding unicode/);
  assert.match(script, /Set-Content -LiteralPath 'C:\\Temp\\exit-code.txt' -Value \$exitCode -Encoding ascii/);
});

test("Windows admin wrapper script forwards launch failures before exiting", () => {
  const script = windowsAdminWrapperScript(
    "C:\\Temp\\launch 'quoted'.ps1",
    "C:\\Temp\\stdout.txt",
    "C:\\Temp\\stderr.txt",
    "C:\\Temp\\exit-code.txt",
    "C:\\Working Dir",
  );

  assert.match(script, /-ArgumentList @\('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\\Temp\\launch ''quoted''.ps1'\)/);
  assert.match(script, /-WorkingDirectory 'C:\\Working Dir'/);
  assert.match(script, /\$_ \| Out-File -FilePath 'C:\\Temp\\stderr.txt' -Append -Encoding unicode/);
  assert.match(script, /if \(Test-Path -LiteralPath 'C:\\Temp\\stderr.txt'\) { \[Console\]::Error\.Write\(\[IO\.File\]::ReadAllText\('C:\\Temp\\stderr.txt'\)\) }/);
  assert.match(script, /\$exitCode = if \(Test-Path -LiteralPath 'C:\\Temp\\exit-code.txt'\)/);
});
