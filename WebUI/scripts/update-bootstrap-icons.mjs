import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const webuiRoot = path.resolve(scriptDir, "..");
const packageRoot = path.join(webuiRoot, "node_modules", "bootstrap-icons");
const sourceFontRoot = path.join(packageRoot, "font");
const vendorRoot = path.join(webuiRoot, "vendor", "bootstrap-icons");
const vendorFontRoot = path.join(vendorRoot, "fonts");

const packageJSON = JSON.parse(await readFile(path.join(packageRoot, "package.json"), "utf8"));

await rm(vendorRoot, { recursive: true, force: true });
await mkdir(vendorFontRoot, { recursive: true });

await copyFile(path.join(sourceFontRoot, "bootstrap-icons.css"), path.join(vendorRoot, "bootstrap-icons.css"));
await copyFile(path.join(sourceFontRoot, "fonts", "bootstrap-icons.woff"), path.join(vendorFontRoot, "bootstrap-icons.woff"));
await copyFile(path.join(sourceFontRoot, "fonts", "bootstrap-icons.woff2"), path.join(vendorFontRoot, "bootstrap-icons.woff2"));
await copyFile(path.join(packageRoot, "LICENSE"), path.join(vendorRoot, "LICENSE"));
await writeFile(
  path.join(vendorRoot, "VERSION.json"),
  `${JSON.stringify({ package: "bootstrap-icons", version: packageJSON.version }, null, 2)}\n`,
  "utf8",
);

console.log(`Vendored Bootstrap Icons ${packageJSON.version} into ${path.relative(webuiRoot, vendorRoot)}`);
