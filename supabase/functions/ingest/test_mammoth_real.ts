import mammoth from "https://esm.sh/mammoth@1.8.0";
import { Buffer } from "node:buffer";

async function main() {
  // Fetch a sample docx
  const resp = await fetch("https://file-examples.com/storage/fe39e8387066f1e29202ed6/2017/02/file-sample_100kB.docx");
  if (!resp.ok) {
    console.error("Failed to fetch test docx:", resp.status);
    Deno.exit(1);
  }
  const buffer = await resp.arrayBuffer();
  
  try {
    const result = await mammoth.extractRawText({ buffer: Buffer.from(buffer) });
    console.log("Success! Extracted text length:", result.value.length);
  } catch (e) {
    console.error("Buffer.from failed:", e.message);
  }
}

main();
