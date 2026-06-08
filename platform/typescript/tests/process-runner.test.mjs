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
  assert.match(script, /Start-Process -FilePath 'C:\\Tools\\run''it.exe' `/);
  assert.match(script, /-ArgumentList '--name O''Brien "C:\\Path With Spaces\\input.txt"' `/);
  assert.match(script, /-RedirectStandardOutput 'C:\\Temp\\stdout.txt' `/);
  assert.match(script, /-RedirectStandardError 'C:\\Temp\\stderr.txt' `/);
  assert.match(script, /\$process\.WaitForExit\(\)/);
  assert.doesNotMatch(script, /-Wait `/);
  assert.match(script, /\$exitCode = if \(\$process\.ExitCode -is \[int\]\) { \$process\.ExitCode } else { 0 }/);
  assert.match(script, /\$_ \| Out-File -FilePath 'C:\\Temp\\stderr.txt' -Append -Encoding utf8/);
  assert.match(script, /Set-Content -LiteralPath 'C:\\Temp\\exit-code.txt' -Value \$exitCode -Encoding ascii/);
});

test("Windows admin wrapper script quotes launcher path and streams output files", () => {
  const script = windowsAdminWrapperScript(
    "C:\\Temp\\launch 'quoted'.ps1",
    "C:\\Temp\\stdout.txt",
    "C:\\Temp\\stderr.txt",
    "C:\\Temp\\exit-code.txt",
    "C:\\Working Dir",
  );

  assert.match(script, /-ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\\Temp\\launch ''quoted''.ps1"'/);
  assert.match(script, /-WorkingDirectory 'C:\\Working Dir'/);
  assert.match(script, /function Write-NewFileContent/);
  assert.match(script, /\$fileEncoding = \[System\.Text\.UTF8Encoding\]::new\(\$false\)/);
  assert.match(script, /\$offset = if \(\$Position\.Value -eq 0 -and \$read -ge 3 -and \$buffer\[0\] -eq 0xef -and \$buffer\[1\] -eq 0xbb -and \$buffer\[2\] -eq 0xbf\) { 3 } else { 0 }/);
  assert.match(script, /Write-NewFileContent -Path 'C:\\Temp\\stdout.txt' -Position \(\[ref\]\$stdoutPosition\) -IsError \$false/);
  assert.match(script, /Write-NewFileContent -Path 'C:\\Temp\\stderr.txt' -Position \(\[ref\]\$stderrPosition\) -IsError \$true/);
  assert.match(script, /\$_ \| Out-File -FilePath 'C:\\Temp\\stderr.txt' -Append -Encoding utf8/);
  assert.match(script, /\$exitCode = if \(Test-Path -LiteralPath 'C:\\Temp\\exit-code.txt'\)/);
  assert.match(script, /elseif \(\$null -ne \$process -and \$process\.ExitCode -is \[int\]\) { \$process\.ExitCode } else { \[Console\]::Error\.WriteLine\('Admin command did not write an exit code\.'\); 1 }/);
});

test("Windows admin wrapper script supports scheduled task automation mode", () => {
  const script = windowsAdminWrapperScript(
    "C:\\Temp With Spaces\\launch.ps1",
    "C:\\Temp\\stdout.txt",
    "C:\\Temp\\stderr.txt",
    "C:\\Temp\\exit-code.txt",
    "C:\\Working Dir",
    {
      mode: "scheduled-task",
      taskName: "GUI For CLI Admin Broker",
      queueDirectory: "C:\\Temp Queue",
    },
  );

  assert.match(script, /\$requestDirectory = 'C:\\Temp Queue'/);
  assert.match(script, /launcherPath = 'C:\\Temp With Spaces\\launch\.ps1'/);
  assert.match(script, /workingDirectory = 'C:\\Working Dir'/);
  assert.match(script, /& schtasks\.exe \/Run \/TN 'GUI For CLI Admin Broker'/);
  assert.match(script, /\$adminCommandCompleted = Test-Path -LiteralPath 'C:\\Temp\\exit-code\.txt'/);
  assert.doesNotMatch(script, /-Verb RunAs/);
});

test("Windows admin wrapper script adds a deadline when a timeout is provided", () => {
  const script = windowsAdminWrapperScript(
    "C:\\Temp\\launch.ps1",
    "C:\\Temp\\stdout.txt",
    "C:\\Temp\\stderr.txt",
    "C:\\Temp\\exit-code.txt",
    undefined,
    {
      mode: "scheduled-task",
      taskName: "GUI For CLI Admin Broker",
      queueDirectory: "C:\\Temp Queue",
    },
    5_000,
  );

  assert.match(script, /\$deadline = \(Get-Date\)\.AddSeconds\(5\)/);
  assert.match(script, /Admin command did not complete before the process timeout\./);
});
