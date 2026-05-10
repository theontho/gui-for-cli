import assert from "node:assert/strict";
import test from "node:test";
import { runSetupStep } from "../dist/server/setup-runner.js";

test("runs only the requested setup step", async () => {
  const calls = [];
  const manifest = {
    setup: {
      steps: [
        { id: "pixi", kind: "pathTool", label: "Find Pixi", value: "pixi" },
        { id: "deps", kind: "pixiRun", label: "Check deps", value: "wgsextract", arguments: ["deps", "check"] },
      ],
    },
  };
  const runProcess = async (executable, args, options) => {
    calls.push({ executable, args, options });
    return { exitCode: 0, stdout: "ok\n", stderr: "" };
  };

  const result = await runSetupStep(manifest, "/bundle", runProcess, "deps");

  assert.equal(calls.length, 1);
  assert.equal(calls[0].executable, "/usr/bin/env");
  assert.deepEqual(calls[0].args, ["pixi", "run", "wgsextract", "deps", "check"]);
  assert.equal(calls[0].options.cwd, "/bundle");
  assert.equal(result.id, "deps");
  assert.equal(result.status, "ok");
  assert.equal(result.stdout, "ok\n");
});

test("rejects unknown setup step ids", async () => {
  await assert.rejects(
    runSetupStep({ setup: { steps: [] } }, "/bundle", async () => ({ exitCode: 0 }), "missing"),
    /Unknown setup step: missing/
  );
});
