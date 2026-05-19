import assert from "node:assert/strict";
import { chmod, cp, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { runInitialSetupIfNeeded, runSetup, runSetupStep, runUninstall } from "../dist/web/src/server/setup-runner.js";
import { createProcessManager } from "../dist/web/src/server/process-runner.js";

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
  assert.equal(calls[1].args[4], path.join(bundleRoot, "scripts", "windows", "setup-wgsextract-pixi.ps1"));
});

test("WGSExtract platform script folders have complete script sets", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const bundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const manifest = (await import("../dist/web/src/server/bundle-loader.js")).loadManifestFromRoot;
  await manifest(bundleRoot);
});

test("WGSExtract keeps platform scripts out of the shared script root", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const scriptsRoot = path.join(repoRoot, "examples", "WGSExtract", "scripts");
  const scriptExtensions = new Set([".sh", ".ps1", ".py"]);
  const rootScripts = (await readdir(scriptsRoot, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && scriptExtensions.has(path.extname(entry.name)))
    .map((entry) => path.basename(entry.name, path.extname(entry.name)));
  const platformScripts = new Set();

  for (const directoryName of ["posix", "windows"]) {
    const directory = path.join(scriptsRoot, directoryName);
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.isFile() && scriptExtensions.has(path.extname(entry.name))) {
        platformScripts.add(path.basename(entry.name, path.extname(entry.name)));
      }
    }
  }

  assert.deepEqual(rootScripts.filter((script) => platformScripts.has(script)).sort(), []);
});

test("runs WGSExtract POSIX setup scripts from nested script folders", async (t) => {
  if (process.platform === "win32") {
    t.skip("This regression covers POSIX packaged setup script paths.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceBundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-posix-setup-"));
  const bundleRoot = path.join(tempRoot, "WGSExtract");
  const appDir = path.join(bundleRoot, "runtime", "wgsextract-cli", "app");
  const fakePixi = path.join(tempRoot, "pixi");
  const previousPixi = process.env.PIXI;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceBundleRoot, bundleRoot, { recursive: true });
    await mkdir(appDir, { recursive: true });
    await writeFile(fakePixi, `#!/bin/sh
if [ "$1" = "run" ] && [ "$2" = "bcftools" ] && [ "$3" = "call" ]; then
  printf 'X 1 60000 M 1\\n*  * *     M 2\\n*  * *     F 2\\n' >&2
  exit 255
fi
echo fake pixi "$@"
exit 0
`);
    await chmod(fakePixi, 0o755);
    process.env.PIXI = fakePixi;

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    const manifest = await loadManifestFromRoot(bundleRoot);
    const result = await runSetupStep(
      manifest,
      bundleRoot,
      processManager.runProcess,
      "bootstrap-reference-library",
    );

    assert.equal(result.status, "ok");
    assert.match(result.command, /scripts\/posix\/bootstrap-reference-library\.sh/);
    assert.match(result.stdout, /fake pixi run wgsextract ref bootstrap --ref/);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("runs WGSExtract platform setup scripts from nested script folders", async (t) => {
  if (process.platform !== "win32") {
    t.skip("This regression covers the packaged Windows setup script path.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const bundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-setup-"));
  const appDir = path.join(tempRoot, "runtime", "wgsextract-cli", "app");
  const referenceLibrary = path.join(tempRoot, "reference");
  const fakePixi = path.join(tempRoot, "pixi.cmd");
  const previousPixi = process.env.PIXI;
  const previousAppDir = process.env.WGSEXTRACT_APP_DIR;
  const previousReferenceLibrary = process.env.WGSEXTRACT_REFERENCE_LIBRARY;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await mkdir(appDir, { recursive: true });
    await writeFile(fakePixi, [
      "@echo off",
      "if \"%1\"==\"run\" if \"%2\"==\"bcftools\" if \"%3\"==\"call\" (",
      "  echo X 1 60000 M 1 1>&2",
      "  echo *  * *     M 2 1>&2",
      "  echo *  * *     F 2 1>&2",
      "  exit /b 255",
      ")",
      "echo fake pixi %*",
      "exit /b 0",
      "",
    ].join("\r\n"));
    await chmod(fakePixi, 0o755);
    process.env.PIXI = fakePixi;
    process.env.WGSEXTRACT_APP_DIR = appDir;
    process.env.WGSEXTRACT_REFERENCE_LIBRARY = referenceLibrary;

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    const manifest = await loadManifestFromRoot(bundleRoot);
    const result = await runSetupStep(
      manifest,
      bundleRoot,
      processManager.runProcess,
      "bootstrap-reference-library",
    );

    assert.equal(result.status, "ok");
    assert.match(result.command, /scripts\\windows\\bootstrap-reference-library\.ps1/);
    assert.match(result.stdout, /fake pixi run wgsextract ref bootstrap --ref/);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_APP_DIR", previousAppDir);
    setOrDeleteEnv("WGSEXTRACT_REFERENCE_LIBRARY", previousReferenceLibrary);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("runs WGSExtract uninstall steps and removes bundle runtime", async (t) => {
  if (process.platform !== "win32") {
    t.skip("This regression covers the packaged Windows uninstall script path.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceBundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-uninstall-"));
  const bundleRoot = path.join(tempRoot, "WGSExtract");
  const runtimeRoot = path.join(bundleRoot, "runtime", "wgsextract-cli");
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceBundleRoot, bundleRoot, { recursive: true });
    await mkdir(path.join(runtimeRoot, "app"), { recursive: true });

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    const manifest = await loadManifestFromRoot(bundleRoot);
    const result = await runUninstall(manifest, bundleRoot, processManager.runProcess);

    assert.equal(result.status, "ok");
    assert.equal(result.results[0].id, "cleanup-wgsextract-runtime");
    await assert.rejects(() => mkdir(path.join(runtimeRoot, "sentinel")), /ENOENT/);
  } finally {
    processManager.terminateAllProcesses();
    await rm(tempRoot, { force: true, recursive: true });
  }
});

function setOrDeleteEnv(key, value) {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}

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
