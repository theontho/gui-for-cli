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
const { renderTerminalPane, terminalTextDirection } = await import("../dist/client/terminal.js");

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

test("terminal log direction follows manifest instead of UI locale", () => {
  Object.assign(state, createInitialState(), {
    manifest: { terminalTextDirection: "ltr" },
    labels: {
      layoutDirection: "rtl",
      terminalCommandOutputLabel: "Command output",
      terminalCopyTextLabel: "Copy terminal text",
      terminalCopiedTextLabel: "Copied!",
      terminalMainTabTitle: "Main",
      terminalCloseTabLabelFormat: "Close %{title}",
    },
  });

  assert.equal(terminalTextDirection(), "ltr");
  assert.match(renderTerminalPane(), /class="terminal-log" dir="ltr"/);

  state.manifest = { terminalTextDirection: "rtl" };

  assert.equal(terminalTextDirection(), "rtl");
  assert.match(renderTerminalPane(), /class="terminal-log" dir="rtl"/);
});
