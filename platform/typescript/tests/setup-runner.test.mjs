import assert from "node:assert/strict";
import { chmod, cp, mkdir, mkdtemp, readFile, realpath, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { runInitialSetupIfNeeded, runSetup, runSetupStep, runUninstall } from "../dist/web/src/server/setup-runner.js";
import { createProcessManager } from "../dist/web/src/server/process-runner.js";

test("runs only the requested setup step", async () => {
  const calls = [];
  const manifest = {
    setup: {
      steps: [
        { id: "pixi", kind: "pathTool", label: "Find Pixi", value: "pixi" },
          {
            id: "deps",
            kind: "pixiRun",
            label: "Check deps",
            value: "wgsextract",
            arguments: ["deps", "check"],
            workingDirectory: "runtime/wgsextract-cli/app",
          },
      ],
    },
  };
  const runProcess = async (executable, args, options) => {
    calls.push({ executable, args, options });
    return { exitCode: 0, stdout: "ok\n", stderr: "" };
  };
  const bundleRoot = path.resolve("bundle");

  const result = await runSetupStep(manifest, bundleRoot, runProcess, "deps");

  assert.equal(calls.length, 1);
  assert.equal(calls[0].executable, process.platform === "win32" ? "pixi" : "/usr/bin/env");
  assert.deepEqual(calls[0].args, process.platform === "win32"
    ? ["run", "wgsextract", "deps", "check"]
    : ["pixi", "run", "wgsextract", "deps", "check"]);
  assert.equal(calls[0].options.cwd, path.join(bundleRoot, "runtime", "wgsextract-cli", "app"));
  assert.equal(result.id, "deps");
  assert.equal(result.status, "ok");
  assert.equal(result.stdout, "ok\n");
});

test("uses Windows equivalents for setup commands", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows command resolution is platform-specific.");
    return;
  }
  const calls = [];
  const manifest = {
    setup: {
      steps: [
        { id: "pixi", kind: "pathTool", label: "Pixi", value: "pixi" },
        { id: "script", kind: "setupScript", label: "Script", value: "scripts/setup-wgsextract-pixi.sh" },
      ],
    },
  };
  const bundleRoot = path.resolve("..", "..", "examples", "WGSExtract");
  const runProcess = async (executable, args, options) => {
    calls.push({ executable, args, options });
    return { exitCode: 0, stdout: "", stderr: "" };
  };

  await runSetupStep(manifest, bundleRoot, runProcess, "pixi");
  await runSetupStep(manifest, bundleRoot, runProcess, "script");

  assert.equal(calls[0].executable, "where.exe");
  assert.deepEqual(calls[0].args, ["pixi"]);
  assert.equal(calls[1].executable, "powershell.exe");
  assert.deepEqual(calls[1].args.slice(0, 5), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]);
  assert.equal(calls[1].args[5], path.join(bundleRoot, "scripts", "windows", "setup-wgsextract-pixi.ps1"));
});

test("WGSExtract platform script folders have complete script sets", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const bundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const manifest = (await import("../dist/web/src/server/bundle-loader.js")).loadManifestFromRoot;
  await manifest(bundleRoot);
});

test("WGSExtract keeps platform scripts out of the shared script root", async () => {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const scriptsRoot = path.join(repoRoot, "examples", "WGSExtract", "scripts");
  const scriptExtensions = new Set([".sh", ".ps1", ".py"]);
  const rootScripts = (await readdir(scriptsRoot, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && scriptExtensions.has(path.extname(entry.name)))
    .map((entry) => path.basename(entry.name, path.extname(entry.name)));
  const platformScripts = new Set();

  for (const directoryName of ["posix", "windows"]) {
    const directory = path.join(scriptsRoot, directoryName);
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.isFile() && scriptExtensions.has(path.extname(entry.name))) {
        platformScripts.add(path.basename(entry.name, path.extname(entry.name)));
      }
    }
  }

  assert.deepEqual(rootScripts.filter((script) => platformScripts.has(script)).sort(), []);
});

test("WGSExtract Windows library state reports test genome visibility values", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows data source behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const script = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows", "library-state.ps1");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-library-state-"));
  const refPath = path.join(tempRoot, "reference");
  const genomeLibrary = path.join(tempRoot, "genomes");
  const testGenomePath = path.join(genomeLibrary, "wgsextract-benchmark-hg19-mini");
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    let result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      script,
      refPath,
      genomeLibrary,
    ], {});
    assert.equal(result.exitCode, 0, result.stderr);
    let state = JSON.parse(result.stdout);
    assert.equal(state.values["library.testGenomeInstalled"], "false");
    assert.equal(state.values["library.testGenomeStatus"], "missing");
    assert.equal(state.values["library.testGenomePath"], testGenomePath);
    assert.equal(state.values["library.annotationVcfInstalled"], "false");
    assert.equal(state.values["library.annotationVcfReady"], "false");
    assert.equal(state.values["library.spliceaiInstalled"], "false");
    assert.equal(state.values["library.alphamissenseInstalled"], "false");
    assert.equal(state.values["library.pharmgkbInstalled"], "false");

    await mkdir(testGenomePath, { recursive: true });
    await mkdir(path.join(refPath, "ref"), { recursive: true });
    await writeFile(path.join(refPath, "common_all.vcf.gz"), "");
    await writeFile(path.join(refPath, "ref", "spliceai_hg38.vcf.gz"), "");
    await writeFile(path.join(refPath, "ref", "alphamissense_hg38.tsv.gz"), "");
    await writeFile(path.join(refPath, "ref", "pharmgkb_hg38.vcf.gz"), "");
    await writeFile(path.join(testGenomePath, "genome-config.toml"), "name = \"test\"\n");
    result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      script,
      refPath,
      genomeLibrary,
    ], {});
    assert.equal(result.exitCode, 0, result.stderr);
    state = JSON.parse(result.stdout);
    assert.equal(state.values["library.testGenomeInstalled"], "true");
    assert.equal(state.values["library.testGenomeStatus"], "installed");
    assert.equal(state.values["library.annotationVcfInstalled"], "true");
    assert.equal(state.values["library.annotationVcfFile"], path.join(refPath, "common_all.vcf.gz"));
    assert.equal(state.values["library.annotationVcfReady"], "true");
    assert.equal(state.values["library.spliceaiInstalled"], "true");
    assert.equal(state.values["library.spliceaiFile"], path.join(refPath, "ref", "spliceai_hg38.vcf.gz"));
    assert.equal(state.values["library.alphamissenseInstalled"], "true");
    assert.equal(state.values["library.alphamissenseFile"], path.join(refPath, "ref", "alphamissense_hg38.tsv.gz"));
    assert.equal(state.values["library.pharmgkbInstalled"], "true");
    assert.equal(state.values["library.pharmgkbFile"], path.join(refPath, "ref", "pharmgkb_hg38.vcf.gz"));
  } finally {
    processManager.terminateAllProcesses();
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows config bootstrap includes genome library default", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows config bootstrap behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const script = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows", "bootstrap-wgsextract-config.ps1");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-config-"));
  const previousWorkspace = process.env.GUI_FOR_CLI_BUNDLE_WORKSPACE;
  const previousConfigPath = process.env.GUI_FOR_CLI_CONFIG_PATH;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    process.env.GUI_FOR_CLI_BUNDLE_WORKSPACE = tempRoot;
    delete process.env.GUI_FOR_CLI_CONFIG_PATH;
    const result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      script,
    ], { env: process.env });
    assert.equal(result.exitCode, 0, result.stderr);
    const bootstrap = JSON.parse(result.stdout);

    assert.equal(bootstrap.path, path.join(tempRoot, "settings", "config.toml"));
    assert.match(bootstrap.contents, new RegExp(`output_directory = "${escapeRegExp(tomlBasicStringValue(path.join(tempRoot, "output")))}"`));
    assert.match(bootstrap.contents, new RegExp(`reference_library = "${escapeRegExp(tomlBasicStringValue(path.join(tempRoot, "reference")))}"`));
    assert.match(bootstrap.contents, new RegExp(`genome_library = "${escapeRegExp(tomlBasicStringValue(path.join(tempRoot, "genomes")))}"`));
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("GUI_FOR_CLI_BUNDLE_WORKSPACE", previousWorkspace);
    setOrDeleteEnv("GUI_FOR_CLI_CONFIG_PATH", previousConfigPath);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows repair scripts forward stdin through runtime wrappers", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows PowerShell pipeline behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const scriptsRoot = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-repair-"));
  const appDir = path.join(tempRoot, "runtime", "app");
  const fakeBin = path.join(tempRoot, "bin");
  const outDir = path.join(tempRoot, "out");
  const fakePixi = path.join(tempRoot, "pixi.ps1");
  const vcfInput = path.join(tempRoot, "sample.vcf");
  const bamInput = path.join(tempRoot, "sample.bam");
  const reference = path.join(tempRoot, "reference.fa");
  const previousPixi = process.env.PIXI;
  const previousAppDir = process.env.WGSEXTRACT_APP_DIR;
  const previousPath = process.env.Path;
  const previousUpperPath = process.env.PATH;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await mkdir(appDir, { recursive: true });
    await mkdir(fakeBin, { recursive: true });
    await mkdir(outDir, { recursive: true });
    await writeFile(vcfInput, "original-vcf\n");
    await writeFile(bamInput, "original-bam\n");
    await writeFile(reference, ">ref\nACGT\n");
    await writeFile(fakePixi, [
      "param([Parameter(Position=0, ValueFromRemainingArguments=$true)][string[]]$Rest, [Parameter(ValueFromPipeline=$true)]$PipelineInput)",
      "begin { $stdinLines = @() }",
      "process { if ($null -ne $PipelineInput) { $stdinLines += [string]$PipelineInput } }",
      "end {",
      "  $log = Join-Path $PSScriptRoot 'calls.log'",
      "  Add-Content -LiteralPath $log -Value ('PIXI|' + ($Rest -join '|') + '|STDIN=' + ($stdinLines -join '\\n'))",
      "  if ($Rest.Count -ge 3 -and $Rest[0] -eq 'run' -and $Rest[1] -eq 'wgsextract' -and $Rest[2] -eq 'repair') {",
      "    foreach ($line in $stdinLines) { Write-Output ('REPAIRED:' + $line) }",
      "    exit 0",
      "  }",
      "  Write-Output ('fake pixi ' + ($Rest -join ' '))",
      "  exit 0",
      "}",
      "",
    ].join("\r\n"));
    await writeFile(path.join(fakeBin, "bcftools.cmd"), [
      "@echo off",
      ">> \"%~dp0..\\calls.log\" echo BCFTOOLS^|%*^|STDIN=",
      "echo VCF-LINE",
      "exit /b 0",
      "",
    ].join("\r\n"));
    await writeFile(path.join(fakeBin, "samtools.cmd"), [
      "@echo off",
      "setlocal EnableDelayedExpansion",
      "set \"allArgs=%*\"",
      "set \"out=\"",
      ":scan",
      "if \"%~1\"==\"\" goto scanned",
      "if \"%~1\"==\"-o\" set \"out=%~2\"",
      "shift",
      "goto scan",
      ":scanned",
      "if not defined out (",
      "  >> \"%~dp0..\\calls.log\" echo SAMTOOLS^|%allArgs%^|STDIN=",
      "  echo SAM-LINE",
      "  exit /b 0",
      ")",
      "set \"stdin=\"",
      "for /f \"delims=\" %%A in ('findstr \"^\"') do set \"stdin=!stdin!%%A\"",
      ">> \"%~dp0..\\calls.log\" echo SAMTOOLS^|%allArgs%^|STDIN=!stdin!",
      "> \"%out%\" echo BAM:!stdin!",
      "exit /b 0",
      "",
    ].join("\r\n"));
    process.env.PIXI = fakePixi;
    process.env.WGSEXTRACT_APP_DIR = appDir;
    const updatedPath = `${fakeBin}${path.delimiter}${process.env.Path ?? process.env.PATH ?? ""}`;
    process.env.Path = updatedPath;
    process.env.PATH = updatedPath;

    const vcfResult = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(scriptsRoot, "repair-ftdna-vcf.ps1"),
      vcfInput,
      outDir,
    ], { env: process.env });
    assert.equal(vcfResult.exitCode, 0, vcfResult.stderr);
    const repairedVcf = await readFile(path.join(outDir, "sample_repaired.vcf"), "utf8");
    assert.match(repairedVcf, /REPAIRED:VCF-LINE/);

    const bamResult = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(scriptsRoot, "repair-ftdna-bam.ps1"),
      bamInput,
      outDir,
      reference,
    ], { env: process.env });
    assert.equal(bamResult.exitCode, 0, bamResult.stderr);
    const repairedBam = await readFile(path.join(outDir, "sample_repaired.bam"), "utf8");
    assert.match(repairedBam, /BAM:REPAIRED:SAM-LINE/);

    const calls = await readFile(path.join(tempRoot, "calls.log"), "utf8");
    assert.match(calls, /PIXI\|run\|wgsextract\|repair\|ftdna-vcf\|STDIN=VCF-LINE/);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_APP_DIR", previousAppDir);
    setOrDeleteEnv("Path", previousPath);
    setOrDeleteEnv("PATH", previousUpperPath);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows runtime wrapper does not wait for stdin unless requested", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows PowerShell wrapper behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceScripts = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-no-stdin-"));
  const scriptsRoot = path.join(tempRoot, "scripts");
  const appDir = path.join(tempRoot, "app");
  const fakePixi = path.join(tempRoot, "pixi.cmd");
  const previousPixi = process.env.PIXI;
  const previousAppDir = process.env.WGSEXTRACT_APP_DIR;
  const previousForwardStdin = process.env.WGSEXTRACT_FORWARD_STDIN;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceScripts, scriptsRoot, { recursive: true });
    await mkdir(appDir, { recursive: true });
    await writeFile(fakePixi, [
      "@echo off",
      `>> "${path.join(tempRoot, "calls.log")}" echo PIXI^|%*`,
      "exit /b 0",
      "",
    ].join("\r\n"));
    process.env.PIXI = fakePixi;
    process.env.WGSEXTRACT_APP_DIR = appDir;
    delete process.env.WGSEXTRACT_FORWARD_STDIN;

    const result = await processManager.runProcess(path.join(scriptsRoot, "run-wgsextract-env.ps1"), [
      "wgsextract",
      "ref",
      "list",
    ], { env: process.env, timeoutMs: 5_000 });

    assert.equal(result.exitCode, 0, result.stderr);
    const calls = await readFile(path.join(tempRoot, "calls.log"), "utf8");
    assert.match(calls, /PIXI\|run wgsextract ref list/);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_APP_DIR", previousAppDir);
    setOrDeleteEnv("WGSEXTRACT_FORWARD_STDIN", previousForwardStdin);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows reference delete treats missing files as no-op", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows delete script behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const script = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows", "delete-reference-genome.ps1");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-delete-ref-"));
  const reference = path.join(tempRoot, "reference");
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await mkdir(path.join(reference, "genomes"), { recursive: true });
    const result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      script,
      reference,
      "missing.fa",
    ], {});
    assert.equal(result.exitCode, 0, result.stderr);
    assert.match(`${result.stdout}\n${result.stderr}`, /No files found/);
  } finally {
    processManager.terminateAllProcesses();
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows VCF wrapper resolves sibling test-genome FASTA", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows PowerShell wrapper behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceScripts = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-vcf-wrapper-"));
  const scriptsRoot = path.join(tempRoot, "scripts");
  const genomeRoot = path.join(tempRoot, "genomes", "wgsextract-benchmark-hg19-mini");
  const referenceRoot = path.join(tempRoot, "reference");
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceScripts, scriptsRoot, { recursive: true });
    await mkdir(genomeRoot, { recursive: true });
    await mkdir(referenceRoot, { recursive: true });
    const inputPath = path.join(genomeRoot, "HG00096.hg19-mini.cram");
    const fastaPath = path.join(genomeRoot, "hg19-mini.fa.gz");
    await writeFile(inputPath, "");
    await writeFile(fastaPath, "");
    await writeFile(path.join(referenceRoot, "ploidy_hg19.txt"), "*  * *     M 2\n");
    await writeFile(path.join(scriptsRoot, "run-wgsextract.ps1"), [
      "param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)",
      "Set-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.log') -Value ($Rest -join '|')",
      "exit 0",
      "",
    ].join("\r\n"));

    const result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(scriptsRoot, "run-wgsextract-vcf.ps1"),
      "snp",
      "--input",
      inputPath,
      "--ref",
      referenceRoot,
      "--outdir",
      path.join(tempRoot, "output"),
    ], {});

    assert.equal(result.exitCode, 0, result.stderr);
    const resolvedFastaPath = await realpath(fastaPath);
    const call = await readFile(path.join(scriptsRoot, "calls.log"), "utf8");
    assert.match(call, new RegExp(`vcf\\|snp\\|--input\\|${escapeRegExp(inputPath)}\\|--ref\\|${escapeRegExp(resolvedFastaPath)}`));
    assert.match(call, new RegExp(`--ploidy-file\\|${escapeRegExp(path.join(referenceRoot, "ploidy_hg19.txt"))}`));
  } finally {
    processManager.terminateAllProcesses();
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows microarray wrapper resolves sibling test-genome files", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows PowerShell wrapper behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceScripts = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-microarray-wrapper-"));
  const scriptsRoot = path.join(tempRoot, "scripts");
  const genomeRoot = path.join(tempRoot, "genomes", "wgsextract-benchmark-hg19-mini");
  const referenceRoot = path.join(tempRoot, "reference");
  const appDir = path.join(tempRoot, "app");
  const fakePixi = path.join(tempRoot, "pixi.cmd");
  const previousPixi = process.env.PIXI;
  const previousAppDir = process.env.WGSEXTRACT_APP_DIR;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceScripts, scriptsRoot, { recursive: true });
    await mkdir(genomeRoot, { recursive: true });
    await mkdir(referenceRoot, { recursive: true });
    await mkdir(appDir, { recursive: true });
    const inputPath = path.join(genomeRoot, "HG00096.hg19-mini.bam");
    const fastaPath = path.join(genomeRoot, "hg19-mini.fa.gz");
    const targetTabPath = path.join(genomeRoot, "HG00096.hg19-mini.targets.tab.gz");
    await writeFile(inputPath, "");
    await writeFile(fastaPath, "");
    await writeFile(targetTabPath, "");
    await writeFile(path.join(genomeRoot, "manifest.json"), JSON.stringify({
      files: {
        ref: "hg19-mini.fa.gz",
        targets: "HG00096.hg19-mini.targets.tab.gz",
      },
    }));
    await writeFile(fakePixi, [
      "@echo off",
      `>> "${path.join(tempRoot, "calls.log")}" echo PIXI^|%*`,
      "exit /b 0",
      "",
    ].join("\r\n"));
    process.env.PIXI = fakePixi;
    process.env.WGSEXTRACT_APP_DIR = appDir;

    const result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(scriptsRoot, "run-wgsextract-microarray.ps1"),
      "--input",
      inputPath,
      "--ref",
      referenceRoot,
      "--formats",
      "23andme-v5",
      "--outdir",
      path.join(tempRoot, "output"),
    ], { env: process.env, timeoutMs: 5_000 });

    assert.equal(result.exitCode, 0, result.stderr);
    const call = await readFile(path.join(tempRoot, "calls.log"), "utf8");
    assert.match(call, new RegExp(`PIXI\\|run wgsextract microarray --input ${escapeRegExp(inputPath)}`));
    assert.match(call, new RegExp(`--ref ${escapeRegExp(fastaPath)}`));
    assert.match(call, new RegExp(`--ref-vcf-tab ${escapeRegExp(targetTabPath)}`));
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_APP_DIR", previousAppDir);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows microarray wrapper resolves reference-root SNP targets", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows PowerShell wrapper behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceScripts = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-microarray-ref-target-"));
  const scriptsRoot = path.join(tempRoot, "scripts");
  const inputRoot = path.join(tempRoot, "inputs");
  const referenceRoot = path.join(tempRoot, "reference");
  const appDir = path.join(tempRoot, "app");
  const fakePixi = path.join(tempRoot, "pixi.cmd");
  const previousPixi = process.env.PIXI;
  const previousAppDir = process.env.WGSEXTRACT_APP_DIR;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceScripts, scriptsRoot, { recursive: true });
    await mkdir(inputRoot, { recursive: true });
    await mkdir(path.join(referenceRoot, "genomes"), { recursive: true });
    await mkdir(appDir, { recursive: true });
    const inputPath = path.join(inputRoot, "sample.cram");
    const fastaPath = path.join(referenceRoot, "genomes", "hs38DH.fa.gz");
    const targetTabPath = path.join(referenceRoot, "snps_hg38.vcf.gz");
    await writeFile(inputPath, "");
    await writeFile(fastaPath, "");
    await writeFile(targetTabPath, "");
    await writeFile(path.join(referenceRoot, "snps_grch38.vcf.gz"), "");
    await writeFile(fakePixi, [
      "@echo off",
      `>> "${path.join(tempRoot, "calls.log")}" echo PIXI^|%*`,
      "exit /b 0",
      "",
    ].join("\r\n"));
    process.env.PIXI = fakePixi;
    process.env.WGSEXTRACT_APP_DIR = appDir;

    const result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(scriptsRoot, "run-wgsextract-microarray.ps1"),
      "--input",
      inputPath,
      "--ref",
      referenceRoot,
      "--formats",
      "23andme-v5",
      "--outdir",
      path.join(tempRoot, "output"),
    ], { env: process.env, timeoutMs: 5_000 });

    assert.equal(result.exitCode, 0, result.stderr);
    const call = await readFile(path.join(tempRoot, "calls.log"), "utf8");
    assert.match(call, new RegExp(`--ref ${escapeRegExp(fastaPath)}`));
    assert.match(call, new RegExp(`--ref-vcf-tab ${escapeRegExp(targetTabPath)}`));
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_APP_DIR", previousAppDir);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("runs WGSExtract POSIX setup scripts from nested script folders", async (t) => {
  if (process.platform === "win32") {
    t.skip("This regression covers POSIX packaged setup script paths.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceBundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-posix-setup-"));
  const bundleRoot = path.join(tempRoot, "WGSExtract");
  const appDir = path.join(bundleRoot, "runtime", "wgsextract-cli", "app");
  const fakePixi = path.join(tempRoot, "pixi");
  const previousPixi = process.env.PIXI;
  const previousSkipMappabilityMaps = process.env.WGSEXTRACT_SKIP_MAPPABILITY_MAPS;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceBundleRoot, bundleRoot, { recursive: true });
    await rm(path.join(bundleRoot, "reference"), { force: true, recursive: true });
    await mkdir(appDir, { recursive: true });
    await writeFile(fakePixi, `#!/bin/sh
if [ "$1" = "run" ] && [ "$2" = "bcftools" ] && [ "$3" = "call" ]; then
  printf 'X 1 60000 M 1\\n*  * *     M 2\\n*  * *     F 2\\n' >&2
  exit 255
fi
echo fake pixi "$@"
exit 0
`);
    await chmod(fakePixi, 0o755);
    process.env.PIXI = fakePixi;
    delete process.env.WGSEXTRACT_SKIP_MAPPABILITY_MAPS;

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    const manifest = await loadManifestFromRoot(bundleRoot);
    const result = await runSetupStep(
      manifest,
      bundleRoot,
      processManager.runProcess,
      "bootstrap-reference-library",
    );

    assert.equal(result.status, "ok", [result.stdout, result.stderr].filter(Boolean).join("\n"));
    assert.match(result.command, /scripts\/posix\/bootstrap-reference-library\.sh/);
    assert.match(result.stdout, /fake pixi run wgsextract ref bootstrap --ref .* --install-mappability-maps/);
    assert.match(result.stdout, /Mappability maps are part of setup/);
    assert.match(result.stdout, /Reference bootstrap support files are ready\./);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_SKIP_MAPPABILITY_MAPS", previousSkipMappabilityMaps);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("runs WGSExtract platform setup scripts from nested script folders", async (t) => {
  if (process.platform !== "win32") {
    t.skip("This regression covers the packaged Windows setup script path.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const bundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-setup-"));
  const appDir = path.join(tempRoot, "runtime", "wgsextract-cli", "app");
  const fakeBin = path.join(tempRoot, "bin");
  const referenceLibrary = path.join(tempRoot, "reference");
  const fakePixi = path.join(tempRoot, "pixi.cmd");
  const previousPixi = process.env.PIXI;
  const previousAppDir = process.env.WGSEXTRACT_APP_DIR;
  const previousReferenceLibrary = process.env.WGSEXTRACT_REFERENCE_LIBRARY;
  const previousSkipMappabilityMaps = process.env.WGSEXTRACT_SKIP_MAPPABILITY_MAPS;
  const previousPath = process.env.Path;
  const previousUpperPath = process.env.PATH;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await mkdir(appDir, { recursive: true });
    await mkdir(fakeBin, { recursive: true });
    await writeFile(fakePixi, [
      "@echo off",
      "echo fake pixi %*",
      "exit /b 0",
      "",
    ].join("\r\n"));
    await writeFile(path.join(fakeBin, "bcftools.cmd"), [
      "@echo off",
      "if \"%1\"==\"call\" (",
      "  echo X 1 60000 M 1 1>&2",
      "  echo *  * *     M 2 1>&2",
      "  echo *  * *     F 2 1>&2",
      "  exit /b 255",
      ")",
      "exit /b 0",
      "",
    ].join("\r\n"));
    await chmod(fakePixi, 0o755);
    process.env.PIXI = fakePixi;
    process.env.WGSEXTRACT_APP_DIR = appDir;
    process.env.WGSEXTRACT_REFERENCE_LIBRARY = referenceLibrary;
    delete process.env.WGSEXTRACT_SKIP_MAPPABILITY_MAPS;
    const updatedPath = `${fakeBin}${path.delimiter}${process.env.Path ?? process.env.PATH ?? ""}`;
    process.env.Path = updatedPath;
    process.env.PATH = updatedPath;
    await mkdir(referenceLibrary, { recursive: true });
    await writeFile(path.join(referenceLibrary, "ploidy_hg19.txt"), "*  * *     M 2\n");
    await writeFile(path.join(referenceLibrary, "ploidy_hg38.txt"), "*  * *     M 2\n");

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    const manifest = await loadManifestFromRoot(bundleRoot);
    const result = await runSetupStep(
      manifest,
      bundleRoot,
      processManager.runProcess,
      "bootstrap-reference-library",
    );

    assert.equal(result.status, "ok", [result.stdout, result.stderr].filter(Boolean).join("\n"));
    assert.match(result.command, /scripts\\windows\\bootstrap-reference-library\.ps1/);
    assert.match(result.stdout, /fake pixi run wgsextract ref bootstrap --ref .* --install-mappability-maps/);
    assert.match(result.stdout, /Mappability maps are part of setup/);
    assert.match(result.stdout, /Reference bootstrap support files are ready\./);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("PIXI", previousPixi);
    setOrDeleteEnv("WGSEXTRACT_APP_DIR", previousAppDir);
    setOrDeleteEnv("WGSEXTRACT_REFERENCE_LIBRARY", previousReferenceLibrary);
    setOrDeleteEnv("WGSEXTRACT_SKIP_MAPPABILITY_MAPS", previousSkipMappabilityMaps);
    setOrDeleteEnv("Path", previousPath);
    setOrDeleteEnv("PATH", previousUpperPath);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("WGSExtract Windows bootstrap installs mappability maps by default", async (t) => {
  if (process.platform !== "win32") {
    t.skip("Windows PowerShell setup behavior is platform-specific.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceScript = path.join(repoRoot, "examples", "WGSExtract", "scripts", "windows", "bootstrap-reference-library.ps1");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-bootstrap-default-"));
  const scriptRoot = path.join(tempRoot, "scripts", "windows");
  const script = path.join(scriptRoot, "bootstrap-reference-library.ps1");
  const referenceLibrary = path.join(tempRoot, "reference");
  const previousReferenceLibrary = process.env.WGSEXTRACT_REFERENCE_LIBRARY;
  const previousInstallMappabilityMaps = process.env.WGSEXTRACT_INSTALL_MAPPABILITY_MAPS;
  const previousSkipMappabilityMaps = process.env.WGSEXTRACT_SKIP_MAPPABILITY_MAPS;
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await mkdir(scriptRoot, { recursive: true });
    await cp(sourceScript, script);
    await writeFile(path.join(scriptRoot, "run-wgsextract.ps1"), [
      "Write-Output \"fake wgsextract $($args -join ' ')\"",
      "exit 0",
      "",
    ].join("\r\n"));
    await mkdir(referenceLibrary, { recursive: true });
    await writeFile(path.join(referenceLibrary, "common_all.vcf.gz"), "");
    await writeFile(path.join(referenceLibrary, "ploidy_hg19.txt"), "*  * *     M 2\n");
    await writeFile(path.join(referenceLibrary, "ploidy_hg38.txt"), "*  * *     M 2\n");
    process.env.WGSEXTRACT_REFERENCE_LIBRARY = referenceLibrary;
    delete process.env.WGSEXTRACT_INSTALL_MAPPABILITY_MAPS;
    delete process.env.WGSEXTRACT_SKIP_MAPPABILITY_MAPS;

    const result = await processManager.runProcess("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      script,
    ], { env: process.env });

    assert.equal(result.exitCode, 0, result.stderr);
    assert.match(result.stdout, /fake wgsextract ref bootstrap --ref .* --install-mappability-maps/);
    assert.match(result.stdout, /Mappability maps are part of setup/);
    assert.match(result.stdout, /Reference bootstrap support files are ready\./);
  } finally {
    processManager.terminateAllProcesses();
    setOrDeleteEnv("WGSEXTRACT_REFERENCE_LIBRARY", previousReferenceLibrary);
    setOrDeleteEnv("WGSEXTRACT_INSTALL_MAPPABILITY_MAPS", previousInstallMappabilityMaps);
    setOrDeleteEnv("WGSEXTRACT_SKIP_MAPPABILITY_MAPS", previousSkipMappabilityMaps);
    await rm(tempRoot, { force: true, recursive: true });
  }
});

test("runs WGSExtract uninstall steps and removes bundle runtime", async (t) => {
  if (process.platform !== "win32") {
    t.skip("This regression covers the packaged Windows uninstall script path.");
    return;
  }

  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  const sourceBundleRoot = path.join(repoRoot, "examples", "WGSExtract");
  const tempRoot = await mkdtemp(path.join(tmpdir(), "gui-for-cli-wgsextract-uninstall-"));
  const bundleRoot = path.join(tempRoot, "WGSExtract");
  const runtimeRoot = path.join(bundleRoot, "runtime", "wgsextract-cli");
  const processManager = createProcessManager({ maxOutputBytes: 1_048_576, maxErrorBytes: 65_536 });

  try {
    await cp(sourceBundleRoot, bundleRoot, { recursive: true });
    await mkdir(path.join(runtimeRoot, "app"), { recursive: true });

    const { loadManifestFromRoot } = await import("../dist/web/src/server/bundle-loader.js");
    const manifest = await loadManifestFromRoot(bundleRoot);
    const result = await runUninstall(manifest, bundleRoot, processManager.runProcess);

    assert.equal(result.status, "ok");
    assert.equal(result.results[0].id, "cleanup-wgsextract-runtime");
    await assert.rejects(() => mkdir(path.join(runtimeRoot, "sentinel")), /ENOENT/);
  } finally {
    processManager.terminateAllProcesses();
    await rm(tempRoot, { force: true, recursive: true });
  }
});

function setOrDeleteEnv(key, value) {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}

function escapeRegExp(value) {
  return String(value).replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
}

function tomlBasicStringValue(value) {
  return String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}

test("rejects unknown setup step ids", async () => {
  await assert.rejects(
    runSetupStep({ setup: { steps: [] } }, path.resolve("bundle"), async () => ({ exitCode: 0 }), "missing"),
    /Unknown setup step: missing/
  );
});

test("runs and persists initial setup when no prior setup run exists", async () => {
  const savedStates = [];
  const emittedEvents = [];
  const bundle = {
    manifest: {
      setup: {
        steps: [{ id: "pixi", kind: "pathTool", label: "Find Pixi", value: "pixi" }],
      },
    },
    bundleState: { setupRun: null },
  };
  const runProcess = async (_executable, _args, options) => {
    options.onStdout?.("pixi\n");
    return { exitCode: 0, stdout: "pixi\n", stderr: "" };
  };

  const setupRun = await runInitialSetupIfNeeded(
    bundle,
    path.resolve("bundle"),
    runProcess,
    async (state) => savedStates.push(state),
    (event) => emittedEvents.push(event),
    true,
    () => "2026-05-09T19:20:00.000Z",
  );

  assert.equal(setupRun.status, "ok");
  assert.equal(setupRun.completedAt, "2026-05-09T19:20:00.000Z");
  assert.equal(setupRun.results[0].id, "pixi");
  assert.equal(bundle.bundleState.setupRun, setupRun);
  assert.deepEqual(savedStates, [{ setupRun }]);
  assert.deepEqual(emittedEvents.map((event) => event.type), ["step-start", "output", "step-complete", "complete"]);
});

test("streams setup process output before step completion", async () => {
  const emittedEvents = [];
  const manifest = {
    setup: {
      steps: [{ id: "install", kind: "setupScript", label: "Install", value: "scripts/install.sh" }],
    },
  };
  const runProcess = async (_executable, _args, options) => {
    options.onStdout?.("downloading\n");
    options.onStderr?.("installing\n");
    return { exitCode: 0, stdout: "downloading\n", stderr: "installing\n" };
  };

  const setupRun = await runSetup(manifest, path.resolve("bundle"), runProcess, (event) => {
    emittedEvents.push(event);
  });

  assert.equal(setupRun.status, "ok");
  assert.deepEqual(emittedEvents.map((event) => event.type), [
    "step-start",
    "output",
    "output",
    "step-complete",
    "complete",
  ]);
  assert.equal(emittedEvents[1].text, "downloading\n");
  assert.equal(emittedEvents[2].text, "installing\n");
});

test("setup fails before running steps when initial install size exceeds free space", async () => {
  const emittedEvents = [];
  let runCount = 0;
  const manifest = {
    setup: {
      initialInstallSizeGB: 1_000_000_000,
      steps: [{ id: "install", kind: "setupScript", label: "Install", value: "scripts/install.sh" }],
    },
  };
  const runProcess = async () => {
    runCount += 1;
    return { exitCode: 0, stdout: "", stderr: "" };
  };

  const setupRun = await runSetup(manifest, path.resolve("bundle"), runProcess, (event) => {
    emittedEvents.push(event);
  });

  assert.equal(runCount, 0);
  assert.equal(setupRun.status, "failed");
  assert.match(setupRun.error, /Need .* GB free/);
  assert.deepEqual(emittedEvents.map((event) => event.type), ["complete"]);
  assert.equal(emittedEvents[0].result.preflight.severity, "warning");
});

test("streams setup process output before failed step completion", async () => {
  const emittedEvents = [];
  const manifest = {
    setup: {
      steps: [{ id: "install", kind: "setupScript", label: "Install", value: "scripts/install.sh" }],
    },
  };
  const runProcess = async (_executable, _args, options) => {
    options.onStdout?.("downloaded\n");
    options.onStderr?.("failed install\n");
    return { exitCode: 7, stdout: "downloaded\n", stderr: "failed install\n" };
  };

  const setupRun = await runSetup(manifest, path.resolve("bundle"), runProcess, (event) => {
    emittedEvents.push(event);
  });

  assert.equal(setupRun.status, "failed");
  assert.deepEqual(emittedEvents.map((event) => event.type), [
    "step-start",
    "output",
    "output",
    "step-complete",
    "complete",
  ]);
  assert.equal(emittedEvents[1].text, "downloaded\n");
  assert.equal(emittedEvents[2].text, "failed install\n");
  assert.equal(emittedEvents[3].result.status, "failed");
});

test("skips initial setup when disabled, already run, or no steps exist", async () => {
  let runCount = 0;
  const runProcess = async () => {
    runCount += 1;
    return { exitCode: 0 };
  };
  const saveState = async () => {
    throw new Error("setup should not be persisted");
  };

  assert.equal(
    await runInitialSetupIfNeeded({ manifest: { setup: { steps: [{ id: "a" }] } }, bundleState: {} }, path.resolve("bundle"), runProcess, saveState, undefined, false),
    null,
  );
  assert.equal(
    await runInitialSetupIfNeeded({ manifest: { setup: { steps: [{ id: "a" }] } }, bundleState: { setupRun: { status: "ok" } } }, path.resolve("bundle"), runProcess, saveState),
    null,
  );
  assert.equal(
    await runInitialSetupIfNeeded({ manifest: { setup: { steps: [] } }, bundleState: {} }, path.resolve("bundle"), runProcess, saveState),
    null,
  );
  assert.equal(runCount, 0);
});

test("persists a failed initial setup when launching a setup command throws", async () => {
  const savedStates = [];
  const bundle = {
    manifest: {
      setup: {
        steps: [{ id: "missing", kind: "pathTool", label: "Missing Tool", value: "missing-tool" }],
      },
    },
    bundleState: {},
  };

  const setupRun = await runInitialSetupIfNeeded(
    bundle,
    path.resolve("bundle"),
    async () => {
      throw new Error("spawn failed");
    },
    async (state) => savedStates.push(state),
    undefined,
    true,
    () => "2026-05-09T19:21:00.000Z",
  );

  assert.equal(setupRun.status, "failed");
  assert.equal(setupRun.error, "spawn failed");
  assert.equal(setupRun.completedAt, "2026-05-09T19:21:00.000Z");
  assert.deepEqual(setupRun.results, []);
  assert.deepEqual(savedStates, [{ setupRun }]);
});
