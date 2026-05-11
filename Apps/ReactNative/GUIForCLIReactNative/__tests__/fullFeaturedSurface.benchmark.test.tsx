import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import { performance } from 'node:perf_hooks';
import { Shell } from '../src/Shell';
import { palette } from '../src/styles';

const noopAsync = async () => undefined;

function fullFeaturedApp() {
  const manifest = {
    displayName: 'GUI for CLI',
    summary: 'Full-featured React Native shell benchmark.',
    iconEmoji: '🧰',
    setup: {
      steps: [
        { id: 'tool', label: 'Check tool', kind: 'pathTool' },
        { id: 'workspace', label: 'Prepare workspace', kind: 'bundledScript' },
      ],
    },
    pages: [
      {
        id: 'extract',
        title: 'Extract',
        summary: 'Exercise all command controls.',
        iconName: 'terminal',
        sidebarGroup: 'Workflows',
        sections: [
          {
            id: 'inputs',
            title: 'Inputs',
            subtitle: 'Representative full app controls.',
            controls: [
              {
                id: 'input_bam',
                kind: 'path',
                label: 'Input BAM',
                tooltip: 'Choose the aligned reads to process.',
                value: '',
              },
              {
                id: 'sample_name',
                kind: 'text',
                label: 'Sample',
                tooltip: 'Used in terminal titles and confirmations.',
                value: 'NA12878',
              },
              {
                id: 'format',
                kind: 'dropdown',
                label: 'Output format',
                options: [
                  { id: 'vcf', title: 'VCF', selected: true },
                  { id: 'fastq', title: 'FASTQ' },
                ],
              },
              {
                id: 'index',
                kind: 'toggle',
                label: 'Index output',
                value: 'true',
              },
              {
                id: 'targets',
                kind: 'checkboxGroup',
                label: 'Targets',
                options: [
                  {
                    id: 'autosomal',
                    title: 'Autosomal',
                    group: 'Genome regions',
                    selected: true,
                  },
                  {
                    id: 'mito',
                    title: 'Mitochondrial',
                    group: 'Genome regions',
                  },
                  { id: 'qc', title: 'QC reports', group: 'Outputs' },
                ],
              },
              {
                id: 'summary',
                kind: 'infoGrid',
                label: 'Summary',
                options: [
                  { id: 'platform', title: 'React Native' },
                  { id: 'mode', title: 'Full surface' },
                ],
              },
            ],
            actions: [
              {
                id: 'extract',
                title: 'Run Extract',
                iconName: 'play.fill',
                role: 'primary',
                command: { executable: 'echo', arguments: ['{{sample_name}}'] },
                tooltip: 'Runs the main command and streams output.',
                confirm: {
                  title: 'Run Extract',
                  message: 'Start extraction?',
                  requiredText: '{{sample_name}}',
                },
              },
              {
                id: 'inspect',
                title: 'Inspect Inputs',
                iconName: 'magnifyingglass',
                role: 'secondary',
                command: { executable: 'echo', arguments: ['{{input_bam}}'] },
              },
              {
                id: 'quick',
                title: 'Quick Run',
                iconEmoji: '⚡',
                iconOnly: true,
                command: { executable: 'echo', arguments: ['quick'] },
              },
            ],
          },
        ],
      },
      {
        id: 'library',
        title: 'Library',
        summary: 'Reference genome library.',
        iconName: 'rectangle.3.group',
        sidebarGroup: 'Workflows',
        sections: [
          {
            id: 'refs',
            title: 'References',
            controls: [
              {
                id: 'reference_library',
                kind: 'libraryList',
                label: 'Reference genomes',
                columns: [
                  { id: 'name', title: 'Name' },
                  { id: 'build', title: 'Build' },
                ],
                rows: [
                  {
                    id: 'hg38',
                    title: 'Human GRCh38',
                    status: 'installed',
                    tags: [{ id: 'primary', title: 'Primary' }],
                    values: { name: 'Human GRCh38', build: 'hg38' },
                  },
                ],
                rowActions: [
                  {
                    id: 'delete',
                    title: 'Delete',
                    iconName: 'trash',
                    role: 'destructive',
                    command: { executable: 'echo', arguments: ['{{row.id}}'] },
                  },
                ],
              },
            ],
          },
        ],
      },
      {
        id: 'settings',
        title: 'Settings',
        summary: 'Configuration and app preferences.',
        iconName: 'gearshape',
        sections: [
          {
            id: 'config',
            title: 'Configuration',
            controls: [
              {
                id: 'settings',
                kind: 'configEditor',
                label: 'WGS Extract Settings',
                configFile: { path: 'settings.toml' },
                settings: [
                  {
                    id: 'ref_path',
                    key: 'reference_library',
                    kind: 'path',
                    label: 'Reference Library',
                    tooltip: 'Directory containing installed references.',
                  },
                  {
                    id: 'theme',
                    key: 'theme',
                    kind: 'dropdown',
                    label: 'Theme',
                    options: [
                      { id: 'system', title: 'System' },
                      { id: 'dark', title: 'Dark' },
                    ],
                  },
                  {
                    id: 'threads',
                    key: 'threads',
                    kind: 'text',
                    label: 'Threads',
                    value: '8',
                  },
                  {
                    id: 'cache',
                    key: 'cache',
                    kind: 'toggle',
                    label: 'Cache',
                    value: 'true',
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  };
  return {
    manifest,
    labels: {
      actionsColumnTitle: 'Actions',
      chooseButtonTitle: 'Choose',
      colorThemeDarkLabel: 'Dark',
      colorThemeLightLabel: 'Light',
      colorThemePickerLabel: 'Color Theme',
      colorThemeSystemLabel: 'System',
      iconSetBootstrapIconsLabel: 'Platform',
      iconSetEmojiLabel: 'Emoji',
      iconSetPickerLabel: 'Icon Set',
      languagePickerLabel: 'Language',
      libraryStatusLabels: { installed: 'Installed' },
      loadingTitle: 'Loading...',
      openBundleWorkspaceTitle: 'Open Bundle Workspace',
      retryButtonTitle: 'Retry',
      saveButtonTitle: 'Save',
      settingsFileLabel: 'Settings file',
      setupRunButtonTitle: 'Run Setup',
      setupStatusReadyTitle: 'Review and run setup.',
      setupStepPendingTitle: 'Pending',
      setupTitle: 'Setup',
      standardOptionsSectionTitle: 'Standard Options',
      terminalMainTabTitle: 'Main',
      webUIFontPickerLabel: 'Web Font',
    },
    localizationCode: 'en',
    localizationOptions: [{ code: 'en', displayName: 'English' }],
    iconSet: 'platform',
    colorTheme: 'system',
    webUIFont: 'system',
    bundleRootPath: '/tmp/gui-for-cli-bundle',
    activePageID: 'extract',
    fieldValues: { sample_name: 'NA12878', index: 'true', format: 'vcf' },
    checkedOptions: { targets: ['autosomal'] },
    configValues: {
      'settings.ref_path': '/refs',
      'settings.theme': 'system',
      'settings.threads': '8',
      'settings.cache': 'true',
    },
    configFilePaths: { settings: 'settings.toml' },
    dataSourcePayloads: new Map(),
    dataSourceErrors: new Map(),
    loadingDataSources: new Set(),
    fileStateValues: new Map(),
    loadingFileStates: new Set(),
    actionPrechecks: new Map(),
    actionPrecheckErrors: new Map(),
    loadingActionPrechecks: new Set(),
    setupRun: null,
    terminalEntries: [
      { id: 'main', kind: 'main', title: 'Main', body: '', command: 'main' },
      {
        id: 'run-extract',
        kind: 'command',
        title: 'Run Extract',
        body: '$ echo NA12878\nprocessing...\n',
        command: 'echo NA12878',
      },
    ],
    activeTerminalID: 'run-extract',
    isSidebarVisible: true,
    isTerminalVisible: true,
    pendingConfirmation: null,
    updateActivePage: noopAsync,
    setFieldValue: noopAsync,
    setCheckedValues: noopAsync,
    setConfigValue: noopAsync,
    setConfigFilePath: noopAsync,
    loadConfig: noopAsync,
    saveConfig: noopAsync,
    choosePath: noopAsync,
    ensureDataSource: noopAsync,
    ensureFileState: noopAsync,
    ensureActionPrecheck: noopAsync,
    runAction: noopAsync,
    runSetup: noopAsync,
    openBundleWorkspace: noopAsync,
    retryDataSource: () => undefined,
    closeTerminal: () => undefined,
    selectTerminal: () => undefined,
    selectLocale: noopAsync,
    selectIconSet: noopAsync,
    selectColorTheme: noopAsync,
    selectWebUIFont: noopAsync,
    toggleSidebar: () => undefined,
    toggleTerminal: () => undefined,
    updateConfirmationInput: () => undefined,
    cancelConfirmation: () => undefined,
    confirmPendingAction: noopAsync,
    cancelAction: () => undefined,
    isRTL: false,
    terminalIsRTL: false,
  };
}

function countNodes(
  node:
    | TestRenderer.ReactTestRendererJSON
    | TestRenderer.ReactTestRendererJSON[]
    | null,
): number {
  if (!node) {
    return 0;
  }
  if (Array.isArray(node)) {
    return node.reduce((sum, child) => sum + countNodes(child), 0);
  }
  return (
    1 +
    (node.children ?? []).reduce((sum, child) => {
      return sum + (typeof child === 'string' ? 1 : countNodes(child));
    }, 0)
  );
}

test('benchmarks the full-featured React Native shell render surface', () => {
  const app = fullFeaturedApp();
  const theme = palette(false);
  let renderer: TestRenderer.ReactTestRenderer | undefined;
  const start = performance.now();
  act(() => {
    renderer = TestRenderer.create(<Shell app={app} theme={theme} />);
  });
  const initialRenderMS = performance.now() - start;
  const nodes = countNodes(renderer!.toJSON());
  expect(
    renderer!.root.findAllByProps({ accessibilityLabel: 'Input BAM' }).length,
  ).toBeGreaterThan(0);
  expect(
    renderer!.root.findAllByProps({ accessibilityLabel: 'Choose Input BAM' })
      .length,
  ).toBeGreaterThan(0);

  const updateStart = performance.now();
  act(() => {
    renderer!.update(
      <Shell app={{ ...app, activePageID: 'settings' }} theme={theme} />,
    );
  });
  const settingsRenderMS = performance.now() - updateStart;
  expect(
    renderer!.root.findAllByProps({ accessibilityLabel: 'Settings file' })
      .length,
  ).toBeGreaterThan(0);
  expect(
    renderer!.root.findAllByProps({ accessibilityLabel: 'Reference Library' })
      .length,
  ).toBeGreaterThan(0);

  const confirmationStart = performance.now();
  act(() => {
    renderer!.update(
      <Shell
        app={{
          ...app,
          pendingConfirmation: {
            action: (app.manifest.pages[0].sections[0] as any).actions[0],
            context: app,
            input: 'NA12878',
          },
        }}
        theme={theme}
      />,
    );
  });
  const confirmationRenderMS = performance.now() - confirmationStart;
  expect(
    renderer!.root.findAllByProps({
      accessibilityLabel: 'Type "NA12878" to confirm.',
    }).length,
  ).toBeGreaterThan(0);

  const metrics = {
    initialRenderMS: Number(initialRenderMS.toFixed(2)),
    settingsRenderMS: Number(settingsRenderMS.toFixed(2)),
    confirmationRenderMS: Number(confirmationRenderMS.toFixed(2)),
    renderedNodes: nodes,
    pages: app.manifest.pages.length,
  };
  console.log('[react-native-full-surface-benchmark]', JSON.stringify(metrics));

  expect(nodes).toBeGreaterThan(100);
  expect(Number.isFinite(initialRenderMS)).toBe(true);
  expect(Number.isFinite(settingsRenderMS)).toBe(true);
  expect(Number.isFinite(confirmationRenderMS)).toBe(true);
});
