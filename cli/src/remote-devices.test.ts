/**
 * The scopes a paired device can have. `backlog` files cards in the backlog and
 * nothing else (the server enforces it; the CLI only has to write and list it).
 */

import { strict as assert } from "node:assert";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, test } from "node:test";
import { addDevice, REMOTE_SCOPES, type RemoteScope } from "./remote-devices.js";

let dir: string;
let path: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "remote-devices-"));
  path = join(dir, "devices.json");
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("remote device scopes", () => {
  test("the list has every scope the server knows", () => {
    assert.deepEqual([...REMOTE_SCOPES].sort(), ["agent", "backlog", "full", "peer", "terminal"]);
  });

  test("addDevice writes a backlog device", () => {
    const { device, token } = addDevice("claude", "backlog", path);
    assert.equal(device.scope, "backlog");
    const file = JSON.parse(readFileSync(path, "utf8")) as { devices: { scope: string; tokenHash: string }[] };
    assert.equal(file.devices.length, 1);
    assert.equal(file.devices[0]!.scope, "backlog");
    assert.ok(token.startsWith("kc_"));
    assert.notEqual(file.devices[0]!.tokenHash, token);
  });

  test("an unknown scope is refused and nothing is written", () => {
    assert.throws(() => addDevice("x", "nope" as RemoteScope, path), /Unknown scope 'nope'/);
    assert.throws(() => readFileSync(path, "utf8"));
  });
});
