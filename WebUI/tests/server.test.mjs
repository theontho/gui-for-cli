import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { applicationSupportDirectory, expandPathTokens } from "../dist/server/paths.js";
import { createProcessManager } from "../dist/server/process-runner.js";

test("expands config and application support tokens for the current platform", () => {
  const original = {
    APPDATA: process.env.APPDATA,
    LOCALAPPDATA: process.env.LOCALAPPDATA,
    XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
    XDG_DATA_HOME: process.env.XDG_DATA_HOME,
  };

  try {
    if (process.platform === "win32") {
      process.env.APPDATA = "C:\\Users\\tester\\AppData\\Roaming";
      process.env.LOCALAPPDATA = "C:\\Users\\tester\\AppData\\Local";
      assert.equal(applicationSupportDirectory(), "C:\\Users\\tester\\AppData\\Local");
      assert.equal(
        expandPathTokens("{{configHome}}|{{applicationSupport}}", "C:\\bundle"),
        "C:\\Users\\tester\\AppData\\Roaming|C:\\Users\\tester\\AppData\\Local",
      );
      assert.equal(expandPathTokens(String.raw`~\bundle`, "C:\\bundle"), path.join(os.homedir(), "bundle"));
      return;
    }

    process.env.XDG_CONFIG_HOME = "/tmp/config-home";
    process.env.XDG_DATA_HOME = "/tmp/data-home";
    assert.equal(
      expandPathTokens("{{configHome}}|{{applicationSupport}}", "/bundle"),
      process.platform === "darwin"
        ? `/tmp/config-home|${path.join(os.homedir(), "Library", "Application Support")}`
        : "/tmp/config-home|/tmp/data-home",
    );
    assert.equal(expandPathTokens("~/bundle", "/bundle"), path.join(os.homedir(), "bundle"));
  }
  finally {
    for (const [key, value] of Object.entries(original)) {
      if (value == null) {
        delete process.env[key];
      }
      else {
        process.env[key] = value;
      }
    }
  }
});

test("runs .cmd scripts on Windows without a shell-specific caller", { skip: process.platform !== "win32" }, async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), "gui-for-cli-webui-"));
  try {
    const scriptPath = path.join(tempRoot, "echo-args.cmd");
    await writeFile(scriptPath, "@echo off\r\necho first=%~1\r\necho second=%~2\r\n", "utf8");
    const { runProcess } = createProcessManager({ maxOutputBytes: 65536, maxErrorBytes: 65536 });
    const result = await runProcess(scriptPath, ["hello world", "second"], { cwd: tempRoot, env: process.env });
    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /first=hello world/);
    assert.match(result.stdout, /second=second/);
  }
  finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("serves WebUI without external icon CDNs", async () => {
  const indexHTML = await readFile(new URL("../index.html", import.meta.url), "utf8");
  assert.doesNotMatch(indexHTML, /cdn\.jsdelivr|bootstrap-icons/i);
});
