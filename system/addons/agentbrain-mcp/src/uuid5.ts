import { createHash } from "node:crypto";

// Hyphenated UUID string -> 16 raw bytes.
function uuidToBytes(uuid: string): Buffer {
  return Buffer.from(uuid.replace(/-/g, ""), "hex");
}

// RFC 4122 v5 UUID: SHA-1(namespace_bytes || utf8(name)), then stamp version 5 + variant.
// Matches Python's uuid.uuid5 (the algorithm scripts/uuid5-gen.sh relies on).
export function uuid5(namespace: string, name: string): string {
  const digest = createHash("sha1")
    .update(uuidToBytes(namespace))
    .update(Buffer.from(name, "utf8"))
    .digest();
  const b = Buffer.from(digest.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50; // version 5
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  const h = b.toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

// Deterministic id for a brain note path (without .md), mirroring uuid5-gen.sh's
// "agentBrain/<path>" name input. Pass the brain-relative path, e.g. "local/learnings/foo".
export function noteId(namespace: string, notePath: string): string {
  return uuid5(namespace, `agentBrain/${notePath}`);
}
