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
const { renderTerminalPane, terminalStatusTooltip } = await import("../dist/client/terminal.js");
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
  const setupListIndex = html.indexOf("setup-list");
  const errorTextIndex = html.indexOf("install failed");

  assert.match(html, /class="setup-step error"/);
  assert.match(html, /install failed/);
  assert.notEqual(setupListIndex, -1);
  assert.notEqual(errorTextIndex, -1);
  assert.ok(setupListIndex < errorTextIndex);
});

test("renders terminal copy button and compact status tooltip", () => {
  state.labels = {
    terminalCommandOutputLabel: "Command output",
    terminalCopyOutputLabel: "Copy Output",
    terminalCloseTabLabelFormat: "Close %{title}",
  };
  state.terminalEntries = [
    { id: "main", kind: "main", title: "Main", body: "", command: "main" },
    {
      id: "failed",
      kind: "error",
      title: "Setup",
      body: "long terminal output",
      command: "setup",
      status: {
        title: "Exit code 1",
        blurb: "The command exited with a non-zero status.",
        detail: "long terminal output should not be in the tooltip",
      },
    },
  ];
  state.activeTerminalIndex = 1;

  const html = renderTerminalPane();
  const tooltip = terminalStatusTooltip(state.terminalEntries[1].status);

  assert.match(html, /data-terminal-copy/);
  assert.match(html, /Copy Output/);
  assert.match(tooltip, /Exit code 1/);
  assert.doesNotMatch(tooltip, /long terminal output should not be in the tooltip/);
});
