import type { LooseRecord, RunProcess } from "../../../shared/types.js";

export type BundleTestOptions = {
    workspaceURL?: string;
    bootstrapConfig?: boolean;
    dryRun?: boolean;
    runSetup?: boolean;
    progressHandler?: (event: LooseRecord) => void;
    processManager?: { runProcess: RunProcess };
    maxOutputBytes?: number;
    maxErrorBytes?: number;
};
