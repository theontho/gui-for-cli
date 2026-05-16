#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const packageRoot = path.join(repoRoot, "platform", "typescript");
const distRoot = path.join(packageRoot, "dist");
const { chromium } = createRequire(path.join(packageRoot, "package.json"))("playwright");

const args = parseArgs(process.argv.slice(2));
const bundleRoot = path.resolve(args.bundle ?? path.join(repoRoot, "examples", "WGSExtract"));
if (!existsSync(bundleRoot)) {
  fail(`bundle does not exist: ${bundleRoot}`);
}
const serverScript = path.join(distRoot, "web", "src", "server", "main.js");
if (!existsSync(serverScript)) {
  fail("compiled Web UI server is missing; run `npm --prefix platform/typescript run build` first");
}

const tempDir = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-browser-shot-"));
const portFile = path.join(tempDir, "port.txt");
let server;
try {
  server = startServer({ bundleRoot, portFile });
  const port = await waitForPortFile(portFile, args.timeout, server);
  await capturePage({
    url: `http://127.0.0.1:${port}/`,
    output: args.output,
    timeout: args.timeout,
  });
} finally {
  if (server) {
    await terminateProcessGroup(server.pid);
  }
  await rm(tempDir, { recursive: true, force: true });
}

function parseArgs(argv) {
  const parsed = {
    bundle: undefined,
    output: path.join(repoRoot, "docs", "ai", "screenshots", "browser-webui.png"),
    timeout: 20,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--bundle") parsed.bundle = readValue(argv, ++index, arg);
    else if (arg === "--output") parsed.output = path.resolve(readValue(argv, ++index, arg));
    else if (arg === "--timeout") parsed.timeout = parseNumber(readValue(argv, ++index, arg), arg);
    else if (arg === "--help" || arg === "-h") {
      console.log("Usage: capture-browser-screenshot.mjs [--bundle PATH] [--output PATH] [--timeout SECONDS]");
      process.exit(0);
    } else {
      fail(`unknown argument: ${arg}`);
    }
  }
  if (parsed.timeout <= 0) {
    fail("--timeout must be > 0");
  }
  return parsed;
}

function readValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    fail(`${flag} requires a value`);
  }
  return value;
}

function parseNumber(value, flag) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    fail(`${flag} must be a number`);
  }
  return parsed;
}

function startServer({ bundleRoot, portFile }) {
  return spawn(
    process.execPath,
    [serverScript, "--bundle", bundleRoot, "--port", "0", "--host", "127.0.0.1"],
    {
      cwd: packageRoot,
      detached: true,
      env: {
        ...process.env,
        GFC_PORT_FILE: portFile,
      },
      stdio: ["ignore", "ignore", "pipe"],
    },
  );
}

async function waitForPortFile(portFile, timeoutSeconds, child) {
  const deadline = performance.now() + timeoutSeconds * 1000;
  while (performance.now() < deadline) {
    if (child.exitCode !== null) {
      fail(`Web UI server exited before writing a port file with code ${child.exitCode}`);
    }
    if (existsSync(portFile)) {
      const port = Number(readFileSync(portFile, "utf8").trim());
      if (Number.isInteger(port) && port > 0) {
        return port;
      }
    }
    await sleep(25);
  }
  fail(`Timed out waiting for Web UI server port after ${timeoutSeconds}s`);
}

async function capturePage({ url, output, timeout }) {
  const browser = await chromium.launch({
    headless: false,
    args: ["--window-size=1344,864"],
  });
  try {
    const context = await browser.newContext({ viewport: { width: 1344, height: 864 } });
    const page = await context.newPage();
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: timeout * 1000 });
    await page.waitForFunction(() => document.querySelector("#app")?.dataset.state === "ready", null, {
      timeout: timeout * 1000,
    });
    await page.waitForTimeout(500);
    mkdirSync(path.dirname(output), { recursive: true });
    await page.screenshot({ path: output });
  } finally {
    await browser.close();
  }
}

async function terminateProcessGroup(pid) {
  try {
    process.kill(-pid, "SIGTERM");
  } catch (error) {
    if (error.code === "ESRCH") {
      return;
    }
    throw error;
  }
  await sleep(1000);
  try {
    process.kill(-pid, "SIGKILL");
  } catch (error) {
    if (error.code !== "ESRCH") {
      throw error;
    }
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function fail(message) {
  console.error(`capture-browser-screenshot: ${message}`);
  process.exit(1);
}
