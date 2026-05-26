import { checkedOptionsForContext } from "../../../shared/rendering.js";
import { bootstrapConfigFiles, emptyBundleState, initialCheckedOptions, initialConfigFilePaths, initialConfigValues, initialFieldValues } from "./config-store.js";
import { expandPathTokens } from "./paths.js";

export async function makeRuntime(manifest, workspaceRoot, planInputs, bootstrapConfig) {
    const bundleState = emptyBundleState();
    const configFilePaths = initialConfigFilePaths(manifest, bundleState);
    if (bootstrapConfig) {
        await bootstrapConfigFiles(manifest, workspaceRoot, configFilePaths);
    }
    const initialConfig = await initialConfigValues(manifest, configFilePaths, workspaceRoot);
    const baseInputs = {
        fieldValues: initialFieldValues(manifest, initialConfig, bundleState),
        configValues: initialConfig,
        checkedOptions: initialCheckedOptions(manifest, initialConfig, bundleState),
    };
    const inputs = mergeInputs(baseInputs, expandInputs(planInputs, workspaceRoot));
    return {
        context: {
            fieldValues: inputs.fieldValues,
            checkedOptions: checkedOptionsForContext(inputs.checkedOptions),
            configValues: inputs.configValues,
            rowValues: {},
            bundleRootPath: workspaceRoot,
            placeholderLabels: placeholderLabels(manifest),
        },
    };
}

function mergeInputs(base, overrides) {
    return {
        fieldValues: { ...(base.fieldValues ?? {}), ...(overrides.fieldValues ?? {}) },
        configValues: { ...(base.configValues ?? {}), ...(overrides.configValues ?? {}) },
        checkedOptions: { ...(base.checkedOptions ?? {}), ...(overrides.checkedOptions ?? {}) },
    };
}

export function expandInputs(inputs, workspaceRoot) {
    return {
        fieldValues: expandValueRecord(inputs.fieldValues ?? {}, workspaceRoot),
        configValues: expandValueRecord(inputs.configValues ?? {}, workspaceRoot),
        checkedOptions: Object.fromEntries(Object.entries(inputs.checkedOptions ?? {}).map(([key, values]) => [
            key,
            checkedOptionValues(values, key, workspaceRoot),
        ])),
    };
}

function checkedOptionValues(values, key, workspaceRoot) {
    if (!Array.isArray(values)) {
        throw new Error(`checkedOptions.${key} must be an array.`);
    }
    return values.map((value) => expandPathTokens(String(value), workspaceRoot));
}

export function expandValueRecord(values, workspaceRoot) {
    return Object.fromEntries(Object.entries(values).map(([key, value]) => [
        key,
        expandPathTokens(String(value), workspaceRoot),
    ]));
}

function placeholderLabels(manifest) {
    const labels = {};
    for (const page of manifest.pages ?? []) {
        for (const section of page.sections ?? []) {
            for (const control of section.controls ?? []) {
                labels[control.id] = control.label;
                for (const setting of control.settings ?? []) {
                    labels[setting.id] = setting.label;
                    labels[setting.key] = setting.label;
                    labels[`${control.id}.${setting.id}`] = setting.label;
                    labels[`${control.id}.${setting.key}`] = setting.label;
                }
            }
        }
    }
    return labels;
}
