import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

const { renderTUIScreen, selectedItem, tuiItemsForPage } = await import("../dist/tui/rendering.js");
const { optionCompletions, pathCompletions, resolveMultiOptionInput, resolveOptionInput } = await import("../dist/tui/completion.js");
const { cycleTheme } = await import("../dist/tui/app-input.js");
const { parseArgs } = await import("../dist/server/paths.js");

function sampleState() {
  return {
    manifest: {
      displayName: "Demo Bundle",
      summary: "Run useful commands from a terminal.",
      setup: { steps: [{ id: "install", label: "Install tool" }] },
      pages: [
        {
          id: "run",
          title: "Run",
          summary: "Choose inputs and launch commands.",
          sections: [
            {
              id: "inputs",
              title: "Inputs",
              controls: [
                { id: "input", kind: "path", label: "Input file", value: "" },
                {
                  id: "mode",
                  kind: "dropdown",
                  label: "Mode",
                  options: [
                    { id: "fast", title: "Fast", selected: true },
                    { id: "deep", title: "Deep" },
                  ],
                },
                {
                  id: "flags",
                  kind: "checkboxGroup",
                  label: "Flags",
                  options: [
                    { id: "qc", title: "QC", selected: true },
                    { id: "trim", title: "Trim" },
                  ],
                },
              ],
              actions: [
                {
                  id: "run",
                  title: "Run command",
                  command: { executable: "tool", arguments: ["{{input}}", "{{mode}}"] },
                },
              ],
            },
          ],
        },
        {
          id: "settings",
          title: "Settings",
          sections: [
            {
              id: "config",
              controls: [
                {
                  id: "app_settings",
                  kind: "configEditor",
                  label: "Settings file",
                  settings: [{ id: "out_dir", key: "output_dir", kind: "path", label: "Output dir", value: "" }],
                },
              ],
            },
          ],
        },
      ],
    },
    labels: { actionMissingInputsFormat: "Missing: %{inputs}" },
    bundleRootPath: "/tmp/demo",
    activePageID: "run",
    selectedItemIndex: 0,
    fieldValues: { mode: "fast" },
    checkedOptions: { flags: ["qc"] },
    configValues: {},
    dataSourcePayloads: new Map(),
    dataSourceErrors: new Map(),
    terminalEntries: [],
  };
}

test("renders bundle pages, controls, and disabled action state", () => {
  const state = sampleState();

  const screen = renderTUIScreen(state, { columns: 100, rows: 30 });

  assert.match(screen, /GUI for CLI TUI - Demo Bundle/);
  assert.match(screen, /PAGES/);
  assert.match(screen, /› ◦ Run/);
  assert.match(screen, /› Input file = \(empty\)/);
  assert.match(screen, /Mode = Fast/);
  assert.match(screen, /Flags = QC/);
  assert.match(screen, /\[Run command\] \[disabled: Missing: input\]/);
  assert.match(screen, /Terminal \(no commands run yet\)/);
});

test("can render ANSI colors for interactive terminals", () => {
  const state = sampleState();

  const screen = renderTUIScreen(state, { columns: 100, rows: 30, color: true });

  assert.match(screen, /\x1b\[[0-9;]*m/);
  assert.match(screen, /GUI for CLI TUI - Demo Bundle/);
});

test("uses different ANSI palettes for dark and light terminals", () => {
  const dark = renderTUIScreen(sampleState(), { columns: 160, rows: 30, color: true, theme: "dark" });
  const light = renderTUIScreen(sampleState(), { columns: 160, rows: 30, color: true, theme: "light" });

  assert.notEqual(light, dark);
  assert.match(dark, /\x1b\[1;38;5;255mDemo Bundle/);
  assert.match(light, /\x1b\[1;38;5;16mDemo Bundle/);
  assert.match(stripANSI(light), /\[t\] theme:auto/);
});

test("auto terminal theme follows environment hints", () => {
  const previous = process.env.GUI_FOR_CLI_TUI_THEME;
  try {
    process.env.GUI_FOR_CLI_TUI_THEME = "light";
    const screen = renderTUIScreen(sampleState(), { columns: 120, rows: 30, color: true, theme: "auto" });

    assert.match(screen, /\x1b\[1;38;5;16mDemo Bundle/);
  } finally {
    if (previous === undefined) {
      delete process.env.GUI_FOR_CLI_TUI_THEME;
    } else {
      process.env.GUI_FOR_CLI_TUI_THEME = previous;
    }
  }
});

test("cycles terminal theme preference for interactive sessions", () => {
  const app = { state: { terminalTheme: "auto" }, fullRedraw: false };

  cycleTheme(app);
  assert.equal(app.state.terminalTheme, "dark");
  assert.equal(app.fullRedraw, true);

  cycleTheme(app);
  assert.equal(app.state.terminalTheme, "light");

  cycleTheme(app);
  assert.equal(app.state.terminalTheme, "auto");
});

test("parses terminal theme CLI option", () => {
  assert.deepEqual(parseArgs(["--bundle", "Examples/WGSExtract", "--theme", "light"]), {
    bundle: "Examples/WGSExtract",
    theme: "light",
  });
});

test("tracks selectable setup, config setting, and action items", () => {
  const state = sampleState();
  state.activePageID = "settings";

  let items = tuiItemsForPage(state);
  assert.deepEqual(items.map((item) => item.kind), ["setup", "configSetting"]);
  assert.equal(selectedItem(state).kind, "setup");

  state.activePageID = "run";
  items = tuiItemsForPage(state);
  assert.deepEqual(items.map((item) => item.kind), ["control", "control", "control", "action"]);
});

test("bounds rendering to terminal rows and scrolls content to the focused item", () => {
  const state = sampleState();
  const controls = state.manifest.pages[0].sections[0].controls;
  controls.push(
    ...Array.from({ length: 20 }, (_, index) => ({
      id: `field_${index + 1}`,
      kind: "text",
      label: `Field ${index + 1}`,
      value: "",
    })),
  );
  state.selectedItemIndex = tuiItemsForPage(state).findIndex((item) => item.key === "control:field_19");

  const screen = renderTUIScreen(state, { columns: 90, rows: 18 });
  const lines = screen.split("\n");

  assert.equal(lines.length, 18);
  assert.match(screen, /Field 19/);
  assert.match(screen, /↑ more|↓ more/);
  assert.ok(lines.every((line) => stripANSI(line).length <= 90));
});

test("renders a compact message instead of upscaling tiny terminals", () => {
  const screen = renderTUIScreen(sampleState(), { columns: 40, rows: 8, color: true, theme: "light" });
  const lines = screen.split("\n");

  assert.equal(lines.length, 8);
  assert.match(stripANSI(screen), /Terminal too small/);
  assert.ok(lines.every((line) => stripANSI(line).length <= 40));
});

test("keeps sidebar page rows stable when the active page changes", () => {
  const state = sampleState();
  const first = renderTUIScreen(state, { columns: 90, rows: 20 }).split("\n");
  state.activePageID = "settings";
  state.selectedItemIndex = 0;
  const second = renderTUIScreen(state, { columns: 90, rows: 20 }).split("\n");

  const firstSettingsIndex = first.findIndex((line) => /[› ] ◦ Settings/.test(line));
  const secondSettingsIndex = second.findIndex((line) => /[› ] ◦ Settings/.test(line));

  assert.ok(firstSettingsIndex > 0);
  assert.equal(firstSettingsIndex, secondSettingsIndex);
});

test("renders terminal focus and scrolls output independently", () => {
  const state = sampleState();
  state.focusPane = "terminal";
  state.terminalScrollOffset = 5;
  state.terminalEntries = [
    {
      id: "run",
      kind: "success",
      title: "Run command",
      command: "tool run",
      body: Array.from({ length: 20 }, (_, index) => `line ${index + 1}`).join("\n"),
    },
  ];

  const screen = renderTUIScreen(state, { columns: 100, rows: 24 });

  assert.match(screen, /› Terminal \[success\] Run command/);
  assert.match(screen, /line 14/);
  assert.match(screen, /↓ newer output/);
  assert.match(screen, /\[Tab\] focus/);
});

test("uses requested terminal pane height", () => {
  const state = sampleState();
  state.terminalHeightRows = 8;
  state.terminalEntries = [
    {
      id: "run",
      kind: "success",
      title: "Run command",
      body: Array.from({ length: 8 }, (_, index) => `terminal line ${index + 1}`).join("\n"),
    },
  ];

  const screen = renderTUIScreen(state, { columns: 100, rows: 30 });

  assert.match(screen, /terminal line 7/);
  assert.match(screen, /\[\+\/-\] term size/);
});

test("preserves blank terminal output lines", () => {
  const state = sampleState();
  state.terminalEntries = [
    {
      id: "run",
      kind: "success",
      title: "Run command",
      command: "tool run",
      body: "first\n\nthird",
    },
  ];

  const screen = renderTUIScreen(state, { columns: 100, rows: 24 });
  const lines = screen.split("\n").map(stripANSI);
  const firstIndex = lines.findIndex((line) => line.includes("first"));
  const thirdIndex = lines.findIndex((line) => line.includes("third"));

  assert.equal(thirdIndex, firstIndex + 2);
});

test("sanitizes command output terminal control sequences", () => {
  const state = sampleState();
  state.terminalEntries = [
    {
      id: "escape",
      kind: "info",
      title: "Escapes",
      body: "safe\x1b[2Jclear\x1b]8;;https://example.com\x07link\x1b]8;;\x07\x07done",
    },
  ];

  const screen = renderTUIScreen(state, { columns: 100, rows: 24, color: true, theme: "dark" });

  assert.match(stripANSI(screen), /safeclearlinkdone/);
  assert.doesNotMatch(stripANSI(screen), /\x1b|\x07|\[2J|]8;;/);
});

test("keeps library row action selection stable for row IDs with colons", () => {
  const state = sampleState();
  state.manifest.pages[0].sections[0].controls = [
    {
      id: "library",
      kind: "libraryList",
      label: "References",
      rows: Array.from({ length: 12 }, (_, index) => ({
        id: index === 10 ? "ref:10" : `ref-${index}`,
        title: index === 10 ? "Reference 10" : `Reference ${index}`,
      })),
      rowActions: [{ id: "delete", title: "Delete", command: { executable: "rm", arguments: ["{{row.id}}"] } }],
    },
  ];
  state.selectedItemIndex = tuiItemsForPage(state).findIndex((item) => item.key === "action:library:ref:10:delete");

  const screen = renderTUIScreen(state, { columns: 100, rows: 30 });

  assert.match(screen, /Reference 10/);
  assert.match(screen, /Reference 10: \[Delete\]/);
});

test("completes filesystem paths for TUI path prompts", () => {
  const root = mkdtempSync(path.join(tmpdir(), "gui-for-cli-tui-"));
  try {
    mkdirSync(path.join(root, "references"));
    writeFileSync(path.join(root, "reads.fastq"), "");
    writeFileSync(path.join(root, "report.txt"), "");

    assert.deepEqual(pathCompletions("rea", root), ["reads.fastq"]);
    assert.deepEqual(pathCompletions("ref", root), ["references/"]);
    assert.deepEqual(pathCompletions("missing", root), []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("resolves typed option choices for dropdown and checkbox prompts", () => {
  const options = [
    { id: "fast", title: "Fast Mode" },
    { id: "deep", title: "Deep Analysis" },
    { id: "qc", title: "Quality Control" },
  ];

  assert.deepEqual(optionCompletions("de", options), ["deep"]);
  assert.equal(resolveOptionInput("2", options).id, "deep");
  assert.equal(resolveOptionInput("quality", options).id, "qc");
  assert.equal(resolveOptionInput("unknown", options).id, "fast");
  assert.equal(resolveOptionInput("unknown", options, "fast").id, "fast");
  assert.deepEqual(resolveMultiOptionInput("fast, quality", options, []), ["fast", "qc"]);
  assert.deepEqual(resolveMultiOptionInput("+deep,-fast", options, ["fast"]), ["deep"]);
  assert.deepEqual(resolveMultiOptionInput("unknown", options, []), []);
  assert.deepEqual(resolveMultiOptionInput("+unknown", options, ["fast"]), ["fast"]);
});

function stripANSI(value) {
  return value.replace(/\x1b\[[0-9;]*m/g, "");
}
