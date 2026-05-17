import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { runInitialSetupIfNeeded, runSetup, runSetupStep } from "../dist/web/src/server/setup-runner.js";

test("runs only the requested setup step", async () => {
  const calls = [];
  const manifest = {
    setup: {
      steps: [
        { id: "pixi", kind: "pathTool", label: "Find Pixi", value: "pixi" },
          {
            id: "deps",
            kind: "pixiRun",
            label: "Check deps",
            value: "wgsextract",
            arguments: ["deps", "check"],
            workingDirectory: "runtime/wgsextract-cli/app",
          },
      ],
    },
  };
  const runProcess = async (executable, args, options) => {
    calls.push({ executable, args, options });
    return { exitCode: 0, stdout: "ok\n", stderr: "" };
  };
  const bundleRoot = path.resolve("bundle");

  const result = await runSetupStep(manifest, bundleRoot, runProcess, "deps");

  assert.equal(calls.length, 1);
  assert.equal(calls[0].executable, process.platform === "win32" ? "pixi" : "/usr/bin/env");
  assert.deepEqual(calls[0].args, process.platform === "win32"
    ? ["run", "wgsextract", "deps", "check"]
    : ["pixi", "run", "wgsextract", "deps", "check"]);
  assert.equal(calls[0].options.cwd, path.join(bundleRoot, "runtime", "wgsextract-cli", "app"));
  assert.equal(result.id, "deps");
  assert.equal(result.status, "ok");
  assert.equal(result.stdout, "ok\n");
});

test("uses Windows equivalents for setup commands", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows command resolution is platform-specific.");
    return;
  }
  const calls = [];
  const manifest = {
    setup: {
      steps: [
        { id: "pixi", kind: "pathTool", label: "Pixi", value: "pixi" },
        { id: "script", kind: "setupScript", label: "Script", value: "scripts/setup-wgsextract-pixi.sh" },
      ],
    },
  };
  const bundleRoot = path.resolve("..", "..", "examples", "WGSExtract");
  const runProcess = async (executable, args, options) => {
    calls.push({ executable, args, options });
    return { exitCode: 0, stdout: "", stderr: "" };
  };

  await runSetupStep(manifest, bundleRoot, runProcess, "pixi");
  await runSetupStep(manifest, bundleRoot, runProcess, "script");

  assert.equal(calls[0].executable, "where.exe");
  assert.deepEqual(calls[0].args, ["pixi"]);
  assert.equal(calls[1].executable, "powershell.exe");
  assert.deepEqual(calls[1].args.slice(0, 4), ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]);
  assert.equal(calls[1].args[4], path.join(bundleRoot, "scripts", "setup-wgsextract-pixi.ps1"));
});

test("rejects unknown setup step ids", async () => {
  await assert.rejects(
    runSetupStep({ setup: { steps: [] } }, path.resolve("bundle"), async () => ({ exitCode: 0 }), "missing"),
    /Unknown setup step: missing/
  );
});

test("runs and persists initial setup when no prior setup run exists", async () => {
  const savedStates = [];
  const emittedEvents = [];
  const bundle = {
    manifest: {
      setup: {
        steps: [{ id: "pixi", kind: "pathTool", label: "Find Pixi", value: "pixi" }],
      },
    },
    bundleState: { setupRun: null },
  };
  const runProcess = async (_executable, _args, options) => {
    options.onStdout?.("pixi\n");
    return { exitCode: 0, stdout: "pixi\n", stderr: "" };
  };

  const setupRun = await runInitialSetupIfNeeded(
    bundle,
    path.resolve("bundle"),
    runProcess,
    async (state) => savedStates.push(state),
    (event) => emittedEvents.push(event),
    true,
    () => "2026-05-09T19:20:00.000Z",
  );

  assert.equal(setupRun.status, "ok");
  assert.equal(setupRun.completedAt, "2026-05-09T19:20:00.000Z");
  assert.equal(setupRun.results[0].id, "pixi");
  assert.equal(bundle.bundleState.setupRun, setupRun);
  assert.deepEqual(savedStates, [{ setupRun }]);
  assert.deepEqual(emittedEvents.map((event) => event.type), ["step-start", "output", "step-complete", "complete"]);
});

test("streams setup process output before step completion", async () => {
  const emittedEvents = [];
  const manifest = {
    setup: {
      steps: [{ id: "install", kind: "setupScript", label: "Install", value: "scripts/install.sh" }],
    },
  };
  const runProcess = async (_executable, _args, options) => {
    options.onStdout?.("downloading\n");
    options.onStderr?.("installing\n");
    return { exitCode: 0, stdout: "downloading\n", stderr: "installing\n" };
  };

  const setupRun = await runSetup(manifest, path.resolve("bundle"), runProcess, (event) => {
    emittedEvents.push(event);
  });

  assert.equal(setupRun.status, "ok");
  assert.deepEqual(emittedEvents.map((event) => event.type), [
    "step-start",
    "output",
    "output",
    "step-complete",
    "complete",
  ]);
  assert.equal(emittedEvents[1].text, "downloading\n");
  assert.equal(emittedEvents[2].text, "installing\n");
});

test("streams setup process output before failed step completion", async () => {
  const emittedEvents = [];
  const manifest = {
    setup: {
      steps: [{ id: "install", kind: "setupScript", label: "Install", value: "scripts/install.sh" }],
    },
  };
  const runProcess = async (_executable, _args, options) => {
    options.onStdout?.("downloaded\n");
    options.onStderr?.("failed install\n");
    return { exitCode: 7, stdout: "downloaded\n", stderr: "failed install\n" };
  };

  const setupRun = await runSetup(manifest, path.resolve("bundle"), runProcess, (event) => {
    emittedEvents.push(event);
  });

  assert.equal(setupRun.status, "failed");
  assert.deepEqual(emittedEvents.map((event) => event.type), [
    "step-start",
    "output",
    "output",
    "step-complete",
    "complete",
  ]);
  assert.equal(emittedEvents[1].text, "downloaded\n");
  assert.equal(emittedEvents[2].text, "failed install\n");
  assert.equal(emittedEvents[3].result.status, "failed");
});

test("skips initial setup when disabled, already run, or no steps exist", async () => {
  let runCount = 0;
  const runProcess = async () => {
    runCount += 1;
    return { exitCode: 0 };
  };
  const saveState = async () => {
    throw new Error("setup should not be persisted");
  };

  assert.equal(
    await runInitialSetupIfNeeded({ manifest: { setup: { steps: [{ id: "a" }] } }, bundleState: {} }, path.resolve("bundle"), runProcess, saveState, undefined, false),
    null,
  );
  assert.equal(
    await runInitialSetupIfNeeded({ manifest: { setup: { steps: [{ id: "a" }] } }, bundleState: { setupRun: { status: "ok" } } }, path.resolve("bundle"), runProcess, saveState),
    null,
  );
  assert.equal(
    await runInitialSetupIfNeeded({ manifest: { setup: { steps: [] } }, bundleState: {} }, path.resolve("bundle"), runProcess, saveState),
    null,
  );
  assert.equal(runCount, 0);
});

test("persists a failed initial setup when launching a setup command throws", async () => {
  const savedStates = [];
  const bundle = {
    manifest: {
      setup: {
        steps: [{ id: "missing", kind: "pathTool", label: "Missing Tool", value: "missing-tool" }],
      },
    },
    bundleState: {},
  };

  const setupRun = await runInitialSetupIfNeeded(
    bundle,
    path.resolve("bundle"),
    async () => {
      throw new Error("spawn failed");
    },
    async (state) => savedStates.push(state),
    undefined,
    true,
    () => "2026-05-09T19:21:00.000Z",
  );

  assert.equal(setupRun.status, "failed");
  assert.equal(setupRun.error, "spawn failed");
  assert.equal(setupRun.completedAt, "2026-05-09T19:21:00.000Z");
  assert.deepEqual(setupRun.results, []);
  assert.deepEqual(savedStates, [{ setupRun }]);
});
