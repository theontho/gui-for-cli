import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";

const { pickPath } = await import("../dist/web/src/server/path-picker.js");
const { pathPickerDefaultPath } = await import("../dist/web/src/client/path-picker-defaults.js");

test("delegates path picking to the Tauri native picker bridge", async () => {
  const server = createServer((request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    assert.equal(url.pathname, "/pick");
    assert.equal(url.searchParams.get("kind"), "directory");
    assert.equal(url.searchParams.get("title"), "Choose output");
    response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ path: "C:\\Users\\mac\\Documents", kind: "directory", cancelled: false }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const previousPort = process.env.GFC_NATIVE_PICKER_PORT;
  process.env.GFC_NATIVE_PICKER_PORT = String(address.port);
  try {
    assert.deepEqual(await pickPath({ kind: "directory", title: "Choose output" }), {
      path: "C:\\Users\\mac\\Documents",
      kind: "directory",
      cancelled: false,
    });
  } finally {
    if (previousPort === undefined) {
      delete process.env.GFC_NATIVE_PICKER_PORT;
    } else {
      process.env.GFC_NATIVE_PICKER_PORT = previousPort;
    }
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
  const previousPort = process.env.GFC_NATIVE_PICKER_PORT;
  process.env.GFC_NATIVE_PICKER_PORT = String(address.port);
  try {
    assert.deepEqual(await pickPath({ kind: "file" }), { kind: "file", cancelled: true });
  } finally {
    if (previousPort === undefined) {
      delete process.env.GFC_NATIVE_PICKER_PORT;
    } else {
      process.env.GFC_NATIVE_PICKER_PORT = previousPort;
    }
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
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
