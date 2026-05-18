export function createShutdownController({ getServer, terminateAllProcesses }) {
    let isShuttingDown = false;
    const shutdown = (reason) => {
        if (isShuttingDown) {
            return;
        }
        isShuttingDown = true;
        terminateAllProcesses();
        const exitCode = reason === "SIGINT" ? 130 : reason === "uncaughtException" ? 1 : 0;
        const server = getServer();
        if (!server) {
            process.exit(exitCode);
        }
        server.close(() => process.exit(exitCode));
        setTimeout(() => process.exit(exitCode), 500).unref();
    };
    return {
        shutdown,
        installShutdownHandlers() {
            for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
                process.once(signal, () => shutdown(signal));
            }
            process.once("beforeExit", () => terminateAllProcesses());
            process.once("uncaughtException", (error) => {
                console.error(error);
                shutdown("uncaughtException");
            });
        },
        installParentMonitor() {
            const parentPid = Number(process.env.GFC_PARENT_PID ?? "");
            if (!Number.isInteger(parentPid) || parentPid <= 1) {
                return;
            }
            const timer = setInterval(() => {
                try {
                    process.kill(parentPid, 0);
                }
                catch (error) {
                    if (error?.code === "ESRCH") {
                        shutdown("parentExit");
                    }
                }
            }, 1000);
            timer.unref();
        },
    };
}
