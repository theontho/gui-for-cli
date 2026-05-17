import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

const { platformCommand } = await import("../dist/web/src/server/platform-command.js");

test("uses Windows executables for Unix setup helpers", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows command resolution is platform-specific.");
    return;
  }

  assert.deepEqual(await platformCommand("/usr/bin/env", ["which", "pixi"]), {
    executable: "where.exe",
    args: ["pixi"],
  });
  assert.deepEqual(await platformCommand("/usr/bin/env", ["pixi", "install"]), {
    executable: "pixi",
    args: ["install"],
  });
});

test("checks Windows pathTool absolute paths without where.exe", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows command resolution is platform-specific.");
    return;
  }
  const target = path.resolve("..", "..", "examples", "WGSExtract", "runtime", "wgsextract-cli", "bin", "wgsextract");
  const result = await platformCommand("/usr/bin/env", ["which", target]);

  assert.equal(result.executable, "powershell.exe");
  assert.deepEqual(result.args.slice(0, 4), ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]);
  assert.match(result.args[4], /param\(\$candidate\)/);
  assert.match(result.args[4], /Test-Path -LiteralPath/);
  assert.match(result.args[4], /\.cmd/);
  assert.equal(result.args[5], target);
});

test("routes Windows script files through platform interpreters", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows command resolution is platform-specific.");
    return;
  }
  const script = path.resolve("..", "..", "examples", "WGSExtract", "scripts", "run-wgsextract.sh");
  const result = await platformCommand("/bin/sh", [script, "deps", "check"]);

  assert.equal(result.executable, "powershell.exe");
  assert.deepEqual(result.args.slice(0, 4), ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]);
  assert.equal(result.args[4], script.slice(0, -3) + ".ps1");
  assert.deepEqual(result.args.slice(5), ["deps", "check"]);
  assert.deepEqual(await platformCommand(path.resolve("..", "..", "examples", "WGSExtract", "scripts", "list-reference-genomes.py"), ["options"]), {
    executable: "python",
    args: [path.resolve("..", "..", "examples", "WGSExtract", "scripts", "list-reference-genomes.py"), "options"],
  });
});
