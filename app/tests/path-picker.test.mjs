import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";

const { pickPath, takeNativePickerEndpoint } = await import("../dist/web/src/server/path-picker.js");
const {
  bundlePickerDefaultPath,
  parentDirectory,
  rememberBundlePickerPath,
} = await import("../dist/web/src/client/bundle-picker-memory.js");
const { pathPickerDefaultPath } = await import("../dist/web/src/client/path-picker-defaults.js");

test("delegates path picking to the Tauri native picker bridge", async () => {
  const server = createServer((request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    assert.equal(url.pathname, "/pick");
    assert.equal(url.searchParams.get("kind"), "directory");
    assert.equal(url.searchParams.get("title"), "Choose output");
    assert.equal(request.headers["x-gfc-token"], "picker-token");
    response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ path: "C:\\Users\\mac\\Documents", kind: "directory", cancelled: false }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    assert.deepEqual(await pickPath({ kind: "directory", title: "Choose output", nativePicker: { port: address.port, token: "picker-token" } }), {
      path: "C:\\Users\\mac\\Documents",
      kind: "directory",
      cancelled: false,
    });
  } finally {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
});

test("preserves native picker cancellation", async () => {
  const server = createServer((_request, response) => {
    response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ kind: "file", cancelled: true }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    assert.deepEqual(await pickPath({ kind: "file", nativePicker: { port: address.port, token: "picker-token" } }), { kind: "file", cancelled: true });
  } finally {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
});

test("takes the native picker endpoint out of the environment so children never inherit it", () => {
  const environment = { GFC_NATIVE_PICKER_PORT: "4567", PATH: "/bin" };

  assert.deepEqual(takeNativePickerEndpoint("token", environment), { port: 4567, token: "token" });
  assert.deepEqual(environment, { PATH: "/bin" });
  assert.equal(takeNativePickerEndpoint("token", {}), undefined);
  assert.throws(() => takeNativePickerEndpoint("token", { GFC_NATIVE_PICKER_PORT: "nope" }), /Invalid GFC_NATIVE_PICKER_PORT/);
});

test("uses configured genome library as the default picker directory", () => {
  assert.equal(
    pathPickerDefaultPath(
      { id: "bam_path", kind: "path", defaultDirectory: "{{genome_library}}" },
      "",
      {
        fieldValues: { genome_library: "/genomes" },
        checkedOptions: {},
        configValues: {},
        bundleRootPath: "/bundle",
      },
    ),
    "/genomes",
  );
  assert.equal(
    pathPickerDefaultPath(
      { id: "bam_path", kind: "path", defaultDirectory: "{{genome_library}}" },
      "/samples/current.bam",
      {
        fieldValues: { genome_library: "/genomes" },
        checkedOptions: {},
        configValues: {},
        bundleRootPath: "/bundle",
      },
    ),
    "/samples/current.bam",
  );
});

test("bundle picker remembers its last directory separately from normal path defaults", () => {
  const storage = new MemoryStorage();
  storage.setItem("guiForCLI.pathPicker.lastDirectory", "/ordinary/files");

  assert.equal(bundlePickerDefaultPath("/initial/bundle", storage), "/initial/bundle");
  rememberBundlePickerPath("/examples/GitHelper", storage);

  assert.equal(bundlePickerDefaultPath("/initial/bundle", storage), "/examples");
  assert.equal(storage.getItem("guiForCLI.pathPicker.lastDirectory"), "/ordinary/files");
  assert.equal(parentDirectory("C:\\Users\\mac\\Bundles\\CurlWorkbench"), "C:\\Users\\mac\\Bundles");
});

class MemoryStorage {
  constructor() {
    this.values = new Map();
  }

  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }

  setItem(key, value) {
    this.values.set(key, String(value));
  }
}
