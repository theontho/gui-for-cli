import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

const { createRequestHandler } = await import("../dist/web/src/server/routes.js");

async function withTestServer(t, overrides = {}) {
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-routes-"));
  t.after(async () => {
    await rm(tempRoot, { force: true, recursive: true });
  });

  const calls = {
    loadBundle: [],
    localizedLoads: [],
    runProcess: [],
    shutdown: [],
  };
  const context = {
    addDevReloadClient() {},
    appVersion: "1.2.3",
    bundleRoot: tempRoot,
    defaultLocale: "en",
    distRoot: tempRoot,
    enableDevReload: false,
    localizedBundleLoader: {
      async load(locale, preferredLocales) {
        calls.localizedLoads.push({ locale, preferredLocales });
        return {
          manifest: {
            id: "test-bundle",
            displayName: "Test Bundle",
            pages: [],
            setup: {
              steps: [
                { id: "node", kind: "pathTool", label: "Find Node", value: "node" },
              ],
            },
          },
          labels: {},
        };
      },
    },
    async loadBundle(requestedSource) {
      calls.loadBundle.push(requestedSource);
      return {
        bundleRootPath: path.join(tempRoot, "workspace"),
        sourceRootPath: requestedSource,
      };
    },
    maxBodyBytes: 1_048_576,
    repoRoot: path.resolve("..", ".."),
    async runProcess(executable, args, options = {}) {
      calls.runProcess.push({ executable, args, options });
      await options.onStdout?.("hello from process\n");
      return { exitCode: 0, stdout: "ok\n", stderr: "" };
    },
    shutdown(reason) {
      calls.shutdown.push(reason);
    },
    sourceBundleRoot: tempRoot,
    webRoot: tempRoot,
    ...overrides,
  };

  const server = createServer(createRequestHandler(context));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.equal(typeof address, "object");
  return { baseURL: `http://127.0.0.1:${address.port}`, calls, context };
}

async function postJSON(baseURL, path, body) {
  return fetch(`${baseURL}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function readNDJSON(response) {
  const text = await response.text();
  return text.trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

function actionRequest() {
  return {
    action: {
      id: "run",
      title: "Run",
      command: {
        executable: "tool",
        arguments: ["{{sample}}"],
      },
    },
    context: {
      fieldValues: { sample: "HG001" },
      checkedOptions: {},
      configValues: {},
      rowValues: {},
    },
  };
}

test("GET /api/manifest localizes with app version and preferred locales", async (t) => {
  const { baseURL, calls } = await withTestServer(t);

  const response = await fetch(`${baseURL}/api/manifest?locale=fr`, {
    headers: { "accept-language": "es;q=0.5,de;q=0.9,*;q=1" },
  });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.manifest.id, "test-bundle");
  assert.equal(body.appVersion, "1.2.3");
  assert.deepEqual(calls.localizedLoads, [{ locale: "fr", preferredLocales: ["de", "es"] }]);
});

test("POST /api/run returns rendered action result", async (t) => {
  const { baseURL, calls } = await withTestServer(t);

  const response = await postJSON(baseURL, "/api/run", actionRequest());
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.exitCode, 0);
  assert.equal(body.stdout, "ok\n");
  assert.match(body.command, /tool HG001$/);
  assert.deepEqual(calls.runProcess.map((call) => [call.executable, call.args]), [["tool", ["HG001"]]]);
});

test("POST /api/run/stream emits action lifecycle events", async (t) => {
  const { baseURL } = await withTestServer(t);

  const response = await postJSON(baseURL, "/api/run/stream", actionRequest());
  const events = await readNDJSON(response);

  assert.equal(response.status, 200);
  assert.deepEqual(events.map((event) => event.type), ["start", "output", "complete"]);
  assert.equal(events[1].stream, "stdout");
  assert.equal(events[2].result.exitCode, 0);
});

test("POST /api/setup/stream emits setup completion", async (t) => {
  const { baseURL, calls } = await withTestServer(t);

  const response = await postJSON(baseURL, "/api/setup/stream", { locale: "en" });
  const events = await readNDJSON(response);

  assert.equal(response.status, 200);
  assert.equal(events.at(-1).type, "complete");
  assert.equal(events.at(-1).result.status, "ok");
  assert.equal(calls.runProcess.length, 1);
});

test("POST /api/bundle/load delegates to the runtime loader", async (t) => {
  const { baseURL, calls } = await withTestServer(t);

  const response = await postJSON(baseURL, "/api/bundle/load", { path: "/tmp/source-bundle" });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(calls.loadBundle, ["/tmp/source-bundle"]);
  assert.equal(body.sourceRootPath, "/tmp/source-bundle");
});

test("route errors are reported as JSON failures", async (t) => {
  const { baseURL } = await withTestServer(t);

  const response = await postJSON(baseURL, "/api/datasource", {
    dataSource: {},
    context: {},
  });
  const body = await response.json();

  assert.equal(response.status, 500);
  assert.match(body.error, /Missing data source path/);
});
