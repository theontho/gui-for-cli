import { useCallback } from 'react';
import { api, apiBase } from './api';
import {
  applySetupEventToSnapshot,
  randomID,
  readNDJSONEvents,
} from './appState';
import {
  errorMessage,
  terminalExitStatus,
  terminalProcessErrorStatus,
} from './model';
import { displayCommand } from './webuiCore';

export function useAppTerminalCallbacks({
  appendTerminalEntry,
  clearDerivedCaches,
  persistState,
  replaceTerminalEntry,
  runningActionControllersRef,
  setSnapshot,
  snapshotRef,
}: any) {
  const executeAction = useCallback(
    async (action: any, context: any) => {
      const id = randomID(action.id ?? 'action');
      const command = displayCommand(action.command, context);
      const runningEntry = {
        id,
        kind: 'command',
        title: action.title,
        body: `$ ${command}`,
        command,
      };
      const controller = new AbortController();
      runningActionControllersRef.current.set(id, controller);
      setSnapshot((state: any) => ({
        ...state,
        terminalEntries: [...state.terminalEntries, runningEntry].slice(-40),
        activeTerminalID: id,
      }));
      try {
        const result = await api('/api/run', {
          method: 'POST',
          body: { action, context },
          signal: controller.signal,
        });
        const status =
          result.exitCode === 0
            ? null
            : terminalExitStatus(
                snapshotRef.current.labels,
                snapshotRef.current.exitCodeReference,
                result.exitCode,
                result.command,
              );
        replaceTerminalEntry(id, {
          id,
          kind: result.exitCode === 0 ? 'success' : status.severity,
          title: action.title,
          command: result.command,
          body: [
            `$ ${result.command}`,
            result.stdout,
            result.stderr,
            `exit ${result.exitCode}`,
          ]
            .filter(Boolean)
            .join('\n'),
          status,
        });
        clearDerivedCaches();
      } catch (error) {
        const aborted =
          error instanceof Error &&
          (error.name === 'AbortError' || /abort/i.test(error.message));
        const status = aborted
          ? terminalExitStatus(
              snapshotRef.current.labels,
              snapshotRef.current.exitCodeReference,
              130,
              command,
            )
          : terminalProcessErrorStatus(
              snapshotRef.current.labels,
              command,
              errorMessage(error),
            );
        replaceTerminalEntry(id, {
          id,
          kind: aborted ? 'warning' : 'error',
          title: action.title,
          command,
          body: aborted
            ? [
                `$ ${command}`,
                snapshotRef.current.labels.terminalCancelledTitle ??
                  'Command cancelled',
              ].join('\n')
            : errorMessage(error),
          status,
        });
      } finally {
        runningActionControllersRef.current.delete(id);
      }
    },
    [
      clearDerivedCaches,
      replaceTerminalEntry,
      runningActionControllersRef,
      setSnapshot,
      snapshotRef,
    ],
  );

  const runAction = useCallback(
    async (action: any, context: any) => {
      if (action.confirm) {
        setSnapshot((current: any) => ({
          ...current,
          pendingConfirmation: { action, context, input: '' },
        }));
        return;
      }
      await executeAction(action, context);
    },
    [executeAction, setSnapshot],
  );

  const runSetup = useCallback(async () => {
    const setupID = appendTerminalEntry({
      kind: 'command',
      title: snapshotRef.current.labels.setupTitle ?? 'Setup',
      body: snapshotRef.current.labels.setupRunningTitle ?? 'Running setup...',
      command: 'bundle setup',
    });
    const controller = new AbortController();
    runningActionControllersRef.current.set(setupID, controller);
    setSnapshot((current: any) => ({
      ...current,
      setupRun: { status: 'running', results: [], currentStepID: null },
      activeTerminalID: setupID,
    }));
    try {
      const response = await fetch(`${apiBase()}/api/setup/stream`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ locale: snapshotRef.current.localizationCode }),
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(response.statusText || `HTTP ${response.status}`);
      }
      let finalSetupRun: any = null;
      await readNDJSONEvents(response, event => {
        setSnapshot((current: any) => {
          const next = applySetupEventToSnapshot(current, setupID, event);
          finalSetupRun = next.setupRun;
          return next;
        });
      });
      if (finalSetupRun?.status && finalSetupRun.status !== 'running') {
        await persistState({ setupRun: finalSetupRun });
      }
    } catch (error) {
      const aborted =
        error instanceof Error &&
        (error.name === 'AbortError' || /abort/i.test(error.message));
      const message = aborted
        ? snapshotRef.current.labels.terminalCancelledTitle ?? 'Setup cancelled'
        : errorMessage(error);
      const failedRun = {
        status: 'failed',
        results: snapshotRef.current.setupRun?.results ?? [],
        error: message,
        completedAt: new Date().toISOString(),
      };
      const status = aborted
        ? terminalExitStatus(
            snapshotRef.current.labels,
            snapshotRef.current.exitCodeReference,
            130,
            'bundle setup',
          )
        : terminalProcessErrorStatus(
            snapshotRef.current.labels,
            'bundle setup',
            message,
          );
      setSnapshot((current: any) => ({
        ...current,
        setupRun: failedRun,
        terminalEntries: current.terminalEntries.map((entry: any) =>
          entry.id === setupID
            ? {
                ...entry,
                kind: aborted ? 'warning' : 'error',
                body: [entry.body, message].filter(Boolean).join('\n'),
                status,
              }
            : entry,
        ),
      }));
      await persistState({ setupRun: failedRun });
    } finally {
      runningActionControllersRef.current.delete(setupID);
    }
  }, [
    appendTerminalEntry,
    persistState,
    runningActionControllersRef,
    setSnapshot,
    snapshotRef,
  ]);

  const openBundleWorkspace = useCallback(async () => {
    await executeAction(
      {
        id: 'open-bundle-workspace',
        title:
          snapshotRef.current.labels.openBundleWorkspaceTitle ??
          'Open Bundle Workspace',
        tooltip: snapshotRef.current.labels.openBundleWorkspaceTooltip,
        iconName: 'folder',
        command: {
          executable: '/usr/bin/open',
          arguments: ['{{bundleWorkspace}}'],
        },
      },
      {
        fieldValues: {},
        checkedOptions: {},
        configValues: {},
        rowValues: {},
        bundleRootPath: snapshotRef.current.bundleRootPath,
      },
    );
  }, [executeAction, snapshotRef]);

  const closeTerminal = useCallback(
    (id: string) => {
      if (id === 'main') {
        return;
      }
      runningActionControllersRef.current.get(id)?.abort();
      runningActionControllersRef.current.delete(id);
      setSnapshot((current: any) => {
        const remaining = current.terminalEntries.filter(
          (entry: any) => entry.id !== id,
        );
        return {
          ...current,
          terminalEntries: remaining,
          activeTerminalID: remaining[remaining.length - 1]?.id ?? 'main',
        };
      });
    },
    [runningActionControllersRef, setSnapshot],
  );

  const cancelAction = useCallback(
    (id: string) => {
      const controller = runningActionControllersRef.current.get(id);
      if (!controller) {
        return;
      }
      controller.abort();
    },
    [runningActionControllersRef],
  );

  const updateConfirmationInput = useCallback(
    (input: string) => {
      setSnapshot((current: any) => ({
        ...current,
        pendingConfirmation: current.pendingConfirmation
          ? { ...current.pendingConfirmation, input }
          : null,
      }));
    },
    [setSnapshot],
  );

  const cancelConfirmation = useCallback(() => {
    setSnapshot((current: any) => ({ ...current, pendingConfirmation: null }));
  }, [setSnapshot]);

  const confirmPendingAction = useCallback(async () => {
    const pending = snapshotRef.current.pendingConfirmation;
    if (!pending) {
      return;
    }
    setSnapshot((current: any) => ({ ...current, pendingConfirmation: null }));
    await executeAction(
      { ...pending.action, confirm: undefined },
      pending.context,
    );
  }, [executeAction, setSnapshot, snapshotRef]);

  return {
    cancelAction,
    cancelConfirmation,
    closeTerminal,
    confirmPendingAction,
    openBundleWorkspace,
    runAction,
    runSetup,
    updateConfirmationInput,
  };
}
