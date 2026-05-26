import { readFile } from "node:fs/promises";
import { errorMessage } from "./errors.js";

export async function loadBundleTestPlan(planPath) {
    if (!planPath) {
        return { steps: [] };
    }
    let source;
    try {
        source = await readFile(planPath, "utf8");
    }
    catch (error) {
        throw new Error(`Could not read bundle test plan ${planPath}: ${errorMessage(error)}`);
    }
    try {
        return JSON.parse(source);
    }
    catch (error) {
        throw new Error(`Could not parse bundle test plan ${planPath}: ${errorMessage(error)}`);
    }
}
