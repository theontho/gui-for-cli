#!/usr/bin/env node
import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const packageRoot = path.join(repoRoot, "platform", "typescript");
const distRoot = path.join(packageRoot, "dist");
const { chromium } = createRequire(path.join(packageRoot, "package.json"))("playwright");

const args = parseArgs(process.argv.slice(2));
if (args.samples < 1) {
  fail("--samples must be an integer >= 1");
}
if (args.timeout <= 0) {
  fail("--timeout must be > 0");
}
if (args.settle < 0) {
  fail("--settle must be >= 0");
}

const bundleRoot = path.resolve(args.bundle ?? path.join(repoRoot, "examples", "WGSExtract"));
if (!existsSync(bundleRoot)) {
  fail(`bundle does not exist: ${bundleRoot}`);
}

const headless = args.headless || process.env.GFC_BROWSER_HEADLESS === "1";
const serverScript = path.join(distRoot, "web", "src", "server", "main.js");
if (!existsSync(serverScript)) {
  fail("compiled Web UI server is missing; run `npm --prefix platform/typescript run build` first");
}

const tempDir = await mkdtemp(path.join(tmpdir(), "gui-for-cli-webui-browser-bench-"));
const portFile = path.join(tempDir, "port.txt");
const serverOutput = [];
let server;
try {
  const serverStartedAt = performance.now();
  server = startServer({ bundleRoot, portFile, output: serverOutput });
  const port = await waitForPortFile(portFile, args.timeout, server);
  const serverStartMs = performance.now() - serverStartedAt;
  const runs = [];
  for (let index = 0; index < args.samples; index += 1) {
    runs.push(
      await runSample({
        url: `http://127.0.0.1:${port}/`,
        timeout: args.timeout,
        settle: args.settle,
        headless,
        serverPid: server.pid,
        preserveFocus: args.preserveFocus,
      }),
    );
  }
  const artifacts = artifactMetadata([
    path.join(packageRoot, "web", "index.html"),
    path.join(packageRoot, "web", "styles.css"),
    path.join(packageRoot, "web", "vendor"),
    path.join(distRoot, "web"),
    path.join(distRoot, "shared"),
  ]);
  const payload = {
    name: "Browser Web UI",
    url: `http://127.0.0.1:${port}/`,
    browser: { engine: "chromium", headless },
    bundleRoot,
    server: {
      pid: server.pid,
      startupMs: round(serverStartMs),
      output: serverOutput,
    },
    artifacts,
    artifactSizeMB: round(artifacts.reduce((total, artifact) => total + artifact.sizeBytes, 0) / 1_000_000),
    samples: args.samples,
    medians: medianMetrics(runs),
    runs,
  };
  const text = `${JSON.stringify(payload, null, 2)}\n`;
  console.log(text);
  if (args.output) {
    mkdirSync(path.dirname(args.output), { recursive: true });
    writeFileSync(args.output, text, "utf8");
  }
} catch (error) {
  console.error(`benchmark-browser: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  if (server) {
    await terminateProcessGroup(server.pid);
  }
  await rm(tempDir, { recursive: true, force: true });
}

function parseArgs(argv) {
  const parsed = {
    samples: 7,
    timeout: 20,
    settle: 0.5,
    bundle: undefined,
    output: undefined,
    headless: false,
    preserveFocus: process.env.GFC_BENCHMARK_PRESERVE_FOCUS === "1",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--samples") parsed.samples = parsePositiveInteger(readValue(argv, ++index, arg), arg);
    else if (arg === "--timeout") parsed.timeout = parseNumber(readValue(argv, ++index, arg), arg);
    else if (arg === "--settle") parsed.settle = parseNumber(readValue(argv, ++index, arg), arg);
    else if (arg === "--bundle") parsed.bundle = readValue(argv, ++index, arg);
    else if (arg === "--output") parsed.output = path.resolve(readValue(argv, ++index, arg));
    else if (arg === "--headless") parsed.headless = true;
    else if (arg === "--preserve-focus") parsed.preserveFocus = true;
    else if (arg === "--help" || arg === "-h") {
      console.log(
        "Usage: benchmark-browser.mjs [--bundle PATH] [--samples N] [--timeout SECONDS] [--settle SECONDS] [--output PATH] [--headless] [--preserve-focus]",
      );
      process.exit(0);
    } else {
      fail(`unknown argument: ${arg}`);
    }
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

function parsePositiveInteger(value, flag) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) {
    fail(`${flag} must be an integer`);
  }
  return parsed;
}

function parseNumber(value, flag) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    fail(`${flag} must be a number`);
  }
  return parsed;
}

function startServer({ bundleRoot, portFile, output }) {
  const child = spawn(
    process.execPath,
    [serverScript, "--bundle", bundleRoot, "--port", "0", "--host", "127.0.0.1"],
    {
      cwd: packageRoot,
      detached: true,
      env: {
        ...process.env,
        GFC_PORT_FILE: portFile,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => output.push(...chunk.trimEnd().split("\n").filter(Boolean)));
  child.stderr.on("data", (chunk) => output.push(...chunk.trimEnd().split("\n").filter(Boolean)));
  return child;
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

async function runSample({ url, timeout, settle, headless, serverPid, preserveFocus }) {
  const frontmostApp = preserveFocus && !headless ? frontmostApplicationName() : undefined;
  const browser = await chromium.launch({
    headless,
    args: ["--window-size=1344,864"],
  });
  restoreFrontmostApplication(frontmostApp);
  try {
    const context = await browser.newContext({ viewport: { width: 1344, height: 864 } });
    const page = await context.newPage();
    await page.addInitScript(() => {
      window.__gfcRenderedAt = undefined;
      window.addEventListener(
        "gui-for-cli-rendered",
        () => {
          window.__gfcRenderedAt = performance.now();
        },
        { once: true },
      );
    });
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: timeout * 1000 });
    await page.waitForFunction(() => document.querySelector("#app")?.dataset.state === "ready", null, {
      timeout: timeout * 1000,
    });
    await page.waitForTimeout(settle * 1000);
    restoreFrontmostApplication(frontmostApp);
    const renderedMs = await page.evaluate(() => window.__gfcRenderedAt ?? performance.now());
    const serverRssMB = processTreeRssMB(serverPid);
    const benchmarkTreeRssMB = processTreeRssMB(process.pid);
    return {
      metrics: {
        webAppRenderedMs: round(renderedMs),
      },
      rssMB: benchmarkTreeRssMB,
      benchmarkTreeRssMB,
      serverRssMB,
    };
  } finally {
    await browser.close();
  }
}

function processTreeRssMB(rootPid) {
  const result = spawnSync("/bin/ps", ["-axo", "pid=,ppid=,rss="], { encoding: "utf8" });
  if (result.status !== 0) {
    return null;
  }
  const children = new Map();
  const rssByPid = new Map();
  for (const line of result.stdout.split("\n")) {
    const [pidText, ppidText, rssText] = line.trim().split(/\s+/);
    const pid = Number(pidText);
    const ppid = Number(ppidText);
    const rss = Number(rssText);
    if (!Number.isInteger(pid) || !Number.isInteger(ppid) || !Number.isFinite(rss)) {
      continue;
    }
    rssByPid.set(pid, rss);
    const siblings = children.get(ppid) ?? [];
    siblings.push(pid);
    children.set(ppid, siblings);
  }
  const stack = [rootPid];
  const seen = new Set();
  let totalKb = 0;
  while (stack.length > 0) {
    const pid = stack.pop();
    if (seen.has(pid)) {
      continue;
    }
    seen.add(pid);
    totalKb += rssByPid.get(pid) ?? 0;
    stack.push(...(children.get(pid) ?? []));
  }
  return totalKb > 0 ? round(totalKb / 1024) : null;
}

function artifactMetadata(paths) {
  return paths.map((artifactPath) => {
    const sizeBytes = pathSizeBytes(artifactPath);
    return {
      path: artifactPath,
      kind: lstatSync(artifactPath).isDirectory() ? "directory" : "file",
      sizeBytes,
      sizeMB: round(sizeBytes / 1_000_000),
    };
  });
}

function pathSizeBytes(artifactPath) {
  const stat = lstatSync(artifactPath);
  if (stat.isSymbolicLink() || stat.isFile()) {
    return stat.size;
  }
  if (!stat.isDirectory()) {
    return 0;
  }
  const result = spawnSync("/usr/bin/find", [artifactPath, "(", "-type", "f", "-or", "-type", "l", ")"], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`could not list artifact files under ${artifactPath}: ${result.stderr}`);
  }
  return result.stdout
    .split("\n")
    .filter(Boolean)
    .reduce((total, filePath) => total + lstatSync(filePath).size, 0);
}

function medianMetrics(runs) {
  return {
    webAppRenderedMs: median(runs.map((run) => run.metrics.webAppRenderedMs)),
    rssMB: median(runs.map((run) => run.rssMB).filter((value) => value !== null)),
    benchmarkTreeRssMB: median(runs.map((run) => run.benchmarkTreeRssMB).filter((value) => value !== null)),
    serverRssMB: median(runs.map((run) => run.serverRssMB).filter((value) => value !== null)),
  };
}

function median(values) {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return round((sorted[middle - 1] + sorted[middle]) / 2);
  }
  return sorted[middle];
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

function round(value) {
  return Math.round(value * 1000) / 1000;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function frontmostApplicationName() {
  const result = spawnSync("/usr/bin/osascript", [
    "-e",
    'tell application "System Events" to get name of first application process whose frontmost is true',
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    console.error(`benchmark-browser: warning: could not determine frontmost app: ${(result.stderr ?? "").trim()}`);
    return undefined;
  }
  return result.stdout.trim() || undefined;
}

function restoreFrontmostApplication(appName) {
  if (!appName) return;
  const result = spawnSync("/usr/bin/osascript", [
    "-e",
    `tell application "System Events" to set frontmost of first application process whose name is ${JSON.stringify(appName)} to true`,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    console.error(`benchmark-browser: warning: could not restore focus to ${appName}: ${(result.stderr ?? "").trim()}`);
  }
}

function fail(message) {
  throw new Error(message);
}
