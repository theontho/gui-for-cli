import {displayCommand} from './webuiCore';

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function pageGroups(manifest: any): Array<{title?: string; pages: any[]}> {
  const groups = new Map<string, any[]>();
  for (const page of manifest?.pages ?? []) {
    const key = page.sidebarGroup ?? '';
    groups.set(key, [...(groups.get(key) ?? []), page]);
  }
  return [...groups.entries()].map(([title, pages]) => ({
    title: title || undefined,
    pages,
  }));
}

export function configSettingBindings(manifest: any, fieldID: string): Array<{
  control: any;
  setting: any;
}> {
  return (manifest?.pages ?? []).flatMap((page: any) =>
    (page.sections ?? []).flatMap((section: any) =>
      (section.controls ?? [])
        .filter((control: any) => control.kind === 'configEditor')
        .flatMap((control: any) =>
          (control.settings ?? [])
            .filter(
              (setting: any) =>
                setting.id === fieldID || setting.key === fieldID,
            )
            .map((setting: any) => ({control, setting})),
        ),
    ),
  );
}

export function configDataSourceContext(snapshot: any, control: any): any {
  const settingValues = {...(snapshot.configValues ?? {})};
  for (const setting of control.settings ?? []) {
    const value =
      snapshot.configValues?.[`${control.id}.${setting.id}`] ??
      setting.value ??
      '';
    settingValues[setting.id] = value;
    settingValues[setting.key] = value;
  }
  return {
    fieldValues: {...(snapshot.fieldValues ?? {}), ...settingValues},
    checkedOptions: snapshot.checkedOptions ?? {},
    configValues: settingValues,
    rowValues: {},
    bundleRootPath: snapshot.bundleRootPath,
  };
}

export function fieldStateCacheKey(context: any): string {
  return JSON.stringify({
    bundleRootPath: context.bundleRootPath ?? '',
    fieldValues: context.fieldValues ?? {},
    checkedOptions: context.checkedOptions ?? {},
    configValues: context.configValues ?? {},
    rowValues: context.rowValues ?? {},
  });
}

export function actionPrecheckCacheKey(action: any, context: any): string {
  return JSON.stringify({
    id: action.id,
    command: displayCommand(action.command, context),
  });
}

export function formatLabel(
  template: string | undefined,
  values: Record<string, string | number>,
): string {
  return String(template ?? '').replace(
    /%\{([^}]+)\}/g,
    (_, key) => String(values[key] ?? ''),
  );
}

export function iconGlyph(
  iconName?: string,
  iconEmoji?: string,
  fallback = '•',
): string {
  const map: Record<string, string> = {
    terminal: '▸',
    hammer: '🔨',
    folder: '📁',
    'folder.badge.gearshape': '📁',
    gearshape: '⚙',
    checklist: '☑',
    globe: '🌐',
    'play.fill': '▶',
    play: '▶',
    'trash.fill': '🗑',
    xmark: '×',
    'checkmark.circle.fill': '✓',
    'checkmark.seal': '✓',
    'rectangle.3.group': '▦',
    'exclamationmark.triangle.fill': '⚠',
    'point.3.connected.trianglepath.dotted': '🧬',
    'text.page': '📄',
    'waveform.path.ecg': '🧪',
    pawprint: '🐾',
    'externaldrive.connected.to.line.below': '💾',
  };
  return iconEmoji ?? (iconName ? map[iconName] : undefined) ?? fallback;
}

export function createMainTerminal(labels: any): any {
  return {
    id: 'main',
    kind: 'main',
    title: labels?.terminalMainTabTitle ?? 'Main',
    body: '',
    command: 'main',
  };
}

export function terminalExitStatus(
  labels: any,
  exitCodeReference: Map<number, any>,
  exitCode: number,
  command: string,
): any {
  const reference = exitCodeReference.get(Number(exitCode));
  const severity = reference?.severity === 'warning' ? 'warning' : 'error';
  return {
    severity,
    symbol: severity === 'warning' ? '▲' : '✕',
    title:
      reference?.title ??
      formatLabel(labels?.terminalExitCodeTitleFormat, {code: exitCode}),
    blurb: reference?.summary ?? labels?.terminalNonzeroExitSummary,
    detail: formatLabel(labels?.terminalExitDetailFormat, {command, code: exitCode}),
  };
}

export function terminalProcessErrorStatus(labels: any, command: string, message: string): any {
  return {
    severity: 'error',
    symbol: '✕',
    title: labels?.terminalProcessErrorTitle ?? 'Command failed',
    blurb:
      labels?.terminalProcessErrorSummary ?? 'The command could not complete.',
    detail: `${command}\n${message}`,
  };
}

export function terminalStatusLabel(entry: any): string | undefined {
  if (!entry.status) {
    return undefined;
  }
  return `${entry.status.title}\n${entry.status.blurb}\n\n${entry.status.detail}`;
}
