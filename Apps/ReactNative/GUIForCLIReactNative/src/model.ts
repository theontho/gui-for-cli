export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function pageGroups(
  manifest: any,
): Array<{ title?: string; pages: any[] }> {
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

export function configSettingBindings(
  manifest: any,
  fieldID: string,
): Array<{
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
            .map((setting: any) => ({ control, setting })),
        ),
    ),
  );
}

export function configDataSourceContext(snapshot: any, control: any): any {
  const settingValues = { ...(snapshot.configValues ?? {}) };
  for (const setting of control.settings ?? []) {
    const value =
      snapshot.configValues?.[`${control.id}.${setting.id}`] ??
      setting.value ??
      '';
    settingValues[setting.id] = value;
    settingValues[setting.key] = value;
  }
  return {
    fieldValues: { ...(snapshot.fieldValues ?? {}), ...settingValues },
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
    actionID: action.id,
    precheck: action.precheck,
    fieldValues: context.fieldValues ?? {},
    checkedOptions: context.checkedOptions ?? {},
    configValues: context.configValues ?? {},
    rowValues: context.rowValues ?? {},
    bundleRootPath: context.bundleRootPath ?? '',
  });
}

export function formatLabel(
  template: string | undefined,
  values: Record<string, string | number>,
): string {
  return String(template ?? '').replace(/%\{([^}]+)\}/g, (_, key) =>
    String(values[key] ?? ''),
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

export function normalizeIconSet(value: unknown): 'platform' | 'emoji' {
  return value === 'emoji' ? 'emoji' : 'platform';
}

export function normalizeColorTheme(
  value: unknown,
): 'system' | 'light' | 'dark' {
  return value === 'light' || value === 'dark' ? value : 'system';
}

export function normalizeWebUIFont(value: unknown): 'system' | 'sfPro' {
  return value === 'sfPro' ? 'sfPro' : 'system';
}

export function resolveText(value: string | undefined, context: any): string {
  return String(value ?? '').replace(/\{\{([^}]+)\}\}/g, (_, raw) => {
    const placeholder = String(raw).trim();
    if (placeholder.startsWith('row.')) {
      return context.rowValues?.[placeholder.slice(4)] ?? '';
    }
    if (placeholder.startsWith('config.')) {
      return context.configValues?.[placeholder.slice(7)] ?? '';
    }
    return (
      context.rowValues?.[placeholder] ??
      context.fieldValues?.[placeholder] ??
      context.configValues?.[placeholder] ??
      ''
    );
  });
}

export function pathPickerKind(spec: any): 'file' | 'directory' {
  const explicitKind = String(
    spec?.pathType ?? spec?.pathKind ?? spec?.pathMode ?? '',
  ).toLowerCase();
  if (explicitKind === 'directory' || explicitKind === 'folder') {
    return 'directory';
  }
  if (explicitKind === 'file') {
    return 'file';
  }
  const searchable = [spec?.id, spec?.key, spec?.label, spec?.tooltip]
    .map(value => String(value ?? '').toLowerCase())
    .join(' ');
  if (
    searchable.includes('reference_library') ||
    /(^|[_\s-])(out|output)[_\s-]*(dir|directory)($|[_\s-])/.test(searchable) ||
    /(^|[_\s-])(dir|directory|folder|library|cache)($|[_\s-])/.test(searchable)
  ) {
    return 'directory';
  }
  return 'file';
}

export function pathPickerTitle(labels: any, spec: any): string {
  const choose = labels.chooseButtonTitle ?? 'Choose';
  return spec?.label ? `${choose} ${spec.label}` : choose;
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
      formatLabel(labels?.terminalExitCodeTitleFormat, { code: exitCode }),
    blurb: reference?.summary ?? labels?.terminalNonzeroExitSummary,
    detail: formatLabel(labels?.terminalExitDetailFormat, {
      command,
      code: exitCode,
    }),
  };
}

export function terminalProcessErrorStatus(
  labels: any,
  command: string,
  message: string,
): any {
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

export function setupStatusSummary(
  labels: any,
  setupRun: any,
  hasSteps: boolean,
): string {
  if (!hasSteps) {
    return (
      labels.setupNoStepsTitle ?? 'No setup steps are defined for this bundle.'
    );
  }
  switch (setupRun?.status) {
    case 'running':
      return labels.setupRunningTitle ?? 'Running setup...';
    case 'ok':
      return labels.setupStatusOkTitle ?? 'Setup completed successfully.';
    case 'failed':
      return (
        labels.setupStatusFailedTitle ??
        'Setup failed. Review command output for details.'
      );
    default:
      return (
        labels.setupStatusReadyTitle ??
        "Review and run this bundle's setup steps."
      );
  }
}

export function setupStepStatusLabel(labels: any, status: string): string {
  switch (status) {
    case 'running':
      return labels.setupStepRunningTitle ?? 'Running';
    case 'ok':
      return labels.setupStepOkTitle ?? 'OK';
    case 'warning':
      return labels.setupStepWarningTitle ?? 'Warning';
    case 'failed':
      return labels.setupStepFailedTitle ?? 'Failed';
    default:
      return labels.setupStepPendingTitle ?? 'Pending';
  }
}
