export function reportShellError(app: any, title: string, error: unknown) {
  app.reportError(error, title);
}
