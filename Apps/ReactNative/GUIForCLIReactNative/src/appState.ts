import { setupResultLine } from './webuiCore';

export function createInitialSnapshot() {
  return {
    status: 'loading',
    error: '',
    manifest: null as any,
    labels: {} as Record<string, any>,
    localizationCode: '',
    localizationOptions: [],
    iconSet: 'platform',
    colorTheme: 'system',
    webUIFont: 'system',
    bundleRootPath: '',
    sourceRootPath: '',
    activePageID: '',
    fieldValues: {},
    checkedOptions: {},
    configValues: {},
    configFilePaths: {},
    dataSourcePayloads: new Map<string, any>(),
    dataSourceErrors: new Map<string, string>(),
    loadingDataSources: new Set<string>(),
    fileStateValues: new Map<string, Record<string, string>>(),
    loadingFileStates: new Set<string>(),
    actionPrechecks: new Map<string, any>(),
    actionPrecheckErrors: new Map<string, string>(),
    loadingActionPrechecks: new Set<string>(),
    exitCodeReference: new Map<number, any>(),
    setupRun: null,
    setupAutorunStarted: false,
    terminalEntries: [] as any[],
    activeTerminalID: 'main',
    isSidebarVisible: true,
    isTerminalVisible: true,
    pendingConfirmation: null as any,
  };
}

export function randomID(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

export function formatConfigMessage(
  template: string | undefined,
  path: string,
  count?: number,
): string {
  return String(template ?? path)
    .replace(/%\{path\}/g, path)
    .replace(/%\{count\}/g, String(count ?? ''));
}

export async function readNDJSONEvents(
  response: Response,
  onEvent: (event: any) => void,
) {
  const body = response.body as any;
  if (body?.getReader && typeof TextDecoder !== 'undefined') {
    const reader = body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        if (line.trim()) {
          onEvent(JSON.parse(line));
        }
      }
    }
    buffer += decoder.decode();
    if (buffer.trim()) {
      onEvent(JSON.parse(buffer));
    }
    return;
  }

  const text = await response.text();
  for (const line of text.split(/\r?\n/)) {
    if (line.trim()) {
      onEvent(JSON.parse(line));
    }
  }
}

export function applySetupEventToSnapshot(
  snapshot: any,
  setupID: string,
  event: any,
) {
  const terminalEntries = snapshot.terminalEntries.map((entry: any) => ({
    ...entry,
  }));
  const tab = terminalEntries.find((entry: any) => entry.id === setupID);
  let setupRun = snapshot.setupRun;
  if (!tab) {
    return snapshot;
  }
  switch (event.type) {
    case 'step-start':
      setupRun = {
        ...(setupRun ?? {}),
        status: 'running',
        currentStepID: event.step.id,
      };
      tab.body = [
        tab.body,
        `==> ${event.step.label}`,
        `$ ${event.step.command}\n`,
      ]
        .filter(Boolean)
        .join('\n');
      break;
    case 'output':
      tab.body += event.text ?? '';
      break;
    case 'step-complete':
      setupRun = {
        ...(setupRun ?? {}),
        status: 'running',
        currentStepID: null,
        results: [
          ...(setupRun?.results ?? []).filter(
            (result: any) => result.id !== event.result.id,
          ),
          event.result,
        ],
      };
      tab.body = [tab.body, setupResultLine(event.result)]
        .filter(Boolean)
        .join('\n');
      break;
    case 'complete':
      setupRun = {
        ...event.result,
        completedAt: new Date().toISOString(),
        currentStepID: null,
      };
      tab.kind = event.result?.status === 'ok' ? 'success' : 'error';
      break;
  }
  return { ...snapshot, setupRun, terminalEntries };
}
