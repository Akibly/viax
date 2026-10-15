import mammoth from "https://esm.sh/mammoth@1.8.0";

const buffer = new ArrayBuffer(8);
try {
  await mammoth.extractRawText({ arrayBuffer: buffer });
  console.log("arrayBuffer worked");
} catch (e) {
  console.error("arrayBuffer failed:", e.message);
}

try {
  await mammoth.extractRawText({ buffer: new Uint8Array(buffer) });
  console.log("buffer with Uint8Array worked");
} catch (e) {
  console.error("buffer failed:", e.message);
}

import { Buffer } from "node:buffer";
try {
  await mammoth.extractRawText({ buffer: Buffer.from(buffer) });
  console.log("buffer with node:buffer worked");
} catch (e) {
  console.error("buffer with node:buffer failed:", e.message);
}
