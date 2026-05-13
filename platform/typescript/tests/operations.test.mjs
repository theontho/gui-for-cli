import assert from "node:assert/strict";
import test from "node:test";

globalThis.localStorage = {
  getItem() {
    return null;
  },
  setItem() {},
};
globalThis.window = { innerHeight: 900 };
globalThis.document = {
  querySelector() {
    return null;
  },
};

const { createInitialState, state } = await import("../dist/web/src/client/state.js");
const { runSetup } = await import("../dist/web/src/client/operations.js");

function resetState() {
  Object.assign(state, createInitialState(), {
    manifest: {
      setup: {
        steps: [
          { id: "install", kind: "setupScript", label: "Install tool", value: "scripts/install.sh" },
          { id: "check", kind: "pixiRun", label: "Check deps", value: "wgsextract", arguments: ["deps", "check"] },
        ],
      },
    },
    labels: {
      setupTitle: "Setup",
      setupRunningTitle: "Running setup...",
      terminalMainTabTitle: "Main",
    },
    bundleRootPath: "/bundle",
  });
}

async function waitUntil(predicate) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("Timed out waiting for condition.");
}

function setupStreamResponse() {
  const encoder = new TextEncoder();
  let controller;
  const body = new ReadableStream({
    start(streamController) {
      controller = streamController;
    },
  });
  return {
    response: new Response(body, {
      status: 200,
      headers: { "content-type": "application/x-ndjson" },
    }),
    write(event) {
      controller.enqueue(encoder.encode(`${JSON.stringify(event)}\n`));
    },
    close() {
      controller.close();
    },
  };
}

test("streams setup output into a selectable setup terminal tab", async () => {
  resetState();
  const originalFetch = globalThis.fetch;
  const requests = [];
  const stream = setupStreamResponse();
  globalThis.fetch = (path, options) => {
    requests.push({ path, options });
    if (path === "/api/state/save") {
      return Promise.resolve(new Response("{}", { status: 200, headers: { "content-type": "application/json" } }));
    }
    return Promise.resolve(stream.response);
  };

  try {
    const setupPromise = runSetup();
    await waitUntil(() => requests.length === 1);

    assert.equal(requests[0].path, "/api/setup/stream");
    assert.equal(requests[0].options.method, "POST");
    assert.equal(requests[0].options.headers["content-type"], "application/json");
    assert.equal(JSON.parse(requests[0].options.body).locale, "");
    assert.equal(state.terminalEntries.length, 2);
    assert.equal(state.terminalEntries[0].kind, "main");
    assert.equal(state.terminalEntries[0].body, "");
    assert.equal(state.terminalEntries[1].title, "Setup");
    assert.equal(state.activeTerminalID, state.terminalEntries[1].id);
    assert.match(state.terminalEntries[1].body, /Running setup/);
    assert.doesNotMatch(state.terminalEntries[0].body, /Install tool/);

    stream.write({
      type: "step-start",
      step: {
        id: "install",
        label: "Install tool",
        kind: "setupScript",
        command: "/bin/sh /bundle/scripts/install.sh",
      },
    });
    await waitUntil(() => /==> Install tool/.test(state.terminalEntries[1].body));

    assert.match(state.terminalEntries[1].body, /==> Install tool/);
    assert.match(state.terminalEntries[1].body, /\$ \/bin\/sh \/bundle\/scripts\/install\.sh/);

    stream.write({ type: "output", id: "install", stream: "stdout", text: "installed\n" });
    await waitUntil(() => /installed/.test(state.terminalEntries[1].body));

    stream.write({
      type: "step-complete",
      result: {
        id: "install",
        label: "Install tool",
        kind: "setupScript",
        command: "/bin/sh /bundle/scripts/install.sh",
        exitCode: 0,
        stdout: "installed",
        stderr: "",
        status: "ok",
      },
    });
    await waitUntil(() => /\[ok\] Install tool/.test(state.terminalEntries[1].body));

    assert.match(state.terminalEntries[1].body, /installed/);
    assert.match(state.terminalEntries[1].body, /\[ok\] Install tool/);

    stream.write({
      type: "step-start",
      step: {
        id: "check",
        label: "Check deps",
        kind: "pixiRun",
        command: "/usr/bin/env pixi run wgsextract deps check",
      },
    });
    await waitUntil(() => /==> Check deps/.test(state.terminalEntries[1].body));

    assert.match(state.terminalEntries[1].body, /==> Check deps/);

    stream.write({ type: "output", id: "check", stream: "stdout", text: "deps ok\n" });
    stream.write({
      type: "step-complete",
      result: {
        id: "check",
        label: "Check deps",
        kind: "pixiRun",
        command: "/usr/bin/env pixi run wgsextract deps check",
        exitCode: 0,
        stdout: "deps ok",
        stderr: "",
        status: "ok",
      },
    });
    stream.write({
      type: "complete",
      result: {
        status: "ok",
        results: [
          { id: "install", label: "Install tool", status: "ok", exitCode: 0 },
          { id: "check", label: "Check deps", status: "ok", exitCode: 0 },
        ],
      },
    });
    stream.close();
    await setupPromise;

    assert.equal(state.setupRun.status, "ok");
    const saveRequest = requests.find((request) => request.path === "/api/state/save");
    assert.ok(saveRequest);
    assert.equal(JSON.parse(saveRequest.options.body).state.setupRun.status, "ok");
    assert.equal(state.terminalEntries[1].kind, "success");
    assert.match(state.terminalEntries[1].body, /deps ok/);
    assert.match(state.terminalEntries[1].body, /\[ok\] Check deps/);
    assert.doesNotMatch(state.terminalEntries[0].body, /deps ok/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
