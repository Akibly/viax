import { assertEquals } from "jsr:@std/assert@1";
import JSZip from "npm:jszip@3.10.1";
import { extractPptx } from "./extraction.ts";

Deno.test("extractPptx keeps slide order and decodes XML", async () => {
  const zip = new JSZip();
  zip.file(
    "ppt/slides/slide2.xml",
    "<a:p><a:r><a:t>Second &amp; final</a:t></a:r></a:p>",
  );
  zip.file(
    "ppt/slides/slide1.xml",
    "<a:p><a:r><a:t>First slide</a:t></a:r></a:p>",
  );
  const bytes = await zip.generateAsync({ type: "uint8array" });
  const pages = await extractPptx(bytes.buffer as ArrayBuffer);
  assertEquals(pages, ["First slide", "Second & final"]);
});
