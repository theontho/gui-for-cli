const { app, BrowserWindow } = require("electron");
const { spawn } = require("node:child_process");
const { existsSync, readFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");

const startedAt = performance.now();
let serverProcess;
let window;

function printMetric(name) {
  console.log(`metric ${name}_ms=${(performance.now() - startedAt).toFixed(1)}`);
}

function resourcePath(...parts) {
  return path.join(__dirname, ...parts);
}

async function waitForPortFile(filePath) {
  const deadline = performance.now() + 15_000;
  while (performance.now() < deadline) {
    if (existsSync(filePath)) {
      const port = Number(readFileSync(filePath, "utf8").trim());
      if (Number.isInteger(port) && port > 0) {
        rmSync(filePath, { force: true });
        return port;
      }
    }
    await delay(25);
  }
  throw new Error(`Timed out waiting for port file ${filePath}`);
}

async function waitForManifest(port) {
  const deadline = performance.now() + 15_000;
  while (performance.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/api/manifest`);
      if (response.ok) {
        return;
      }
    } catch {
      // Retry until the server is ready or the deadline expires.
    }
    await delay(25);
  }
  throw new Error("Timed out waiting for /api/manifest");
}

function launchServer() {
  const portFile = path.join(tmpdir(), `gui-for-cli-electron-${process.pid}.port`);
  serverProcess = spawn(
    process.execPath,
    [
      resourcePath("platform", "typescript", "dist", "web", "src", "server", "main.js"),
      "--port",
      "0",
      "--host",
      "127.0.0.1",
      "--bundle",
      resourcePath("examples", "WGSExtract"),
    ],
    {
      cwd: __dirname,
      env: {
        ...process.env,
        ELECTRON_RUN_AS_NODE: "1",
        GFC_PARENT_PID: String(process.pid),
        GFC_PORT_FILE: portFile,
      },
      stdio: "ignore",
    }
  );
  console.log(`node_pid=${serverProcess.pid}`);
  printMetric("nodeProcessStarted");
  return portFile;
}

async function waitForRenderedPage(deadline = performance.now() + 15_000) {
  while (performance.now() < deadline) {
    const ready = await window.webContents.executeJavaScript(
      "Boolean(document.querySelector('#app')?.dataset.state === 'ready' && document.title)"
    );
    if (ready) {
      printMetric("webAppRendered");
      return;
    }
    await delay(25);
  }
  throw new Error("Timed out waiting for rendered WebUI");
}

function terminateServer() {
  if (serverProcess && !serverProcess.killed) {
    serverProcess.kill("SIGTERM");
  }
}

app.on("before-quit", terminateServer);
app.on("window-all-closed", () => app.quit());

app.whenReady().then(async () => {
  try {
    printMetric("appReady");
    const portFile = launchServer();
    const port = await waitForPortFile(portFile);
    await waitForManifest(port);
    printMetric("serverManifestReady");

    window = new BrowserWindow({
      width: 1200,
      height: 800,
      show: false,
      webPreferences: { contextIsolation: true, nodeIntegration: false },
    });
    window.once("ready-to-show", () => {
      window.show();
      printMetric("windowShown");
    });
    window.webContents.once("did-finish-load", () => {
      printMetric("webNavigationDidFinish");
      waitForRenderedPage().catch((error) => {
        console.error(`error=${error.message}`);
        app.quit();
      });
    });
    await window.loadURL(`http://127.0.0.1:${port}/`);
  } catch (error) {
    console.error(`error=${error.message}`);
    app.quit();
  }
});
