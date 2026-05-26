import assert from "node:assert/strict";
import test from "node:test";

const { createProcessManager } = await import("../dist/web/src/server/process-runner.js");

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
