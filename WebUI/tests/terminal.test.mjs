import assert from "node:assert/strict";
import test from "node:test";

globalThis.localStorage = {
  getItem() {
    return null;
  },
  setItem() {},
};
globalThis.window = { innerHeight: 900 };

const { createInitialState, state } = await import("../dist/client/state.js");
const { renderTerminalPane } = await import("../dist/client/terminal.js");

test("terminal copy feedback renders only after copying", () => {
  Object.assign(state, createInitialState(), {
    labels: {
      terminalCommandOutputLabel: "Command output",
      terminalCopyTextLabel: "Copy terminal text",
      terminalCopiedTextLabel: "Copied!",
      terminalMainTabTitle: "Main",
      terminalCloseTabLabelFormat: "Close %{title}",
    },
  });

  let html = renderTerminalPane();
  assert.doesNotMatch(html, /Copied!/);

  state.terminalCopyFeedback = true;
  html = renderTerminalPane();
  assert.match(html, /Copied!/);
  assert.match(html, /role="status"/);
});
