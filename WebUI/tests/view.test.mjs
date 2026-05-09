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

const { state } = await import("../dist/client/state.js");
const { renderSetupSteps } = await import("../dist/client/view.js");

function prepareSetupState() {
  state.manifest = {
    setup: {
      steps: [
        {
          id: "install",
          kind: "setupScript",
          label: "Install tool",
          value: "scripts/install.sh",
        },
      ],
    },
  };
  state.labels = {
    setupTitle: "Setup",
    setupSummary: "Prepare the tool.",
    setupRunButtonTitle: "Run Setup",
    setupRequiredLabel: "Required",
  };
  state.bundleRootPath = "/bundle";
  state.setupRun = { status: "idle", results: [] };
}

test("renders a visible setup run button above setup steps", () => {
  prepareSetupState();

  const html = renderSetupSteps();

  assert.match(html, /class="action-row setup-actions"/);
  assert.match(html, /class="action-button primary setup-run-button"/);
  assert.match(html, /data-run-setup/);
  assert.match(html, />Run Setup</);
  assert.ok(html.indexOf("data-run-setup") < html.indexOf("setup-list"));
});

test("renders setup failure state details", () => {
  prepareSetupState();
  state.setupRun = {
    status: "failed",
    results: [
      {
        id: "install",
        label: "Install tool",
        kind: "setupScript",
        status: "error",
        error: "install failed",
      },
    ],
  };

  const html = renderSetupSteps();

  assert.match(html, /class="setup-step error"/);
  assert.match(html, /install failed/);
  assert.ok(html.indexOf("setup-list") < html.indexOf("install failed"));
});
