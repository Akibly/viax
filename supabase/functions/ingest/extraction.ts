import JSZip from "npm:jszip@3.10.1";

function decodeXml(value: string): string {
  return value
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(
      /&#x([0-9a-f]+);/gi,
      (_, code) => String.fromCodePoint(Number.parseInt(code, 16)),
    );
}

/** Extract one logical page per slide from an Office Open XML presentation. */
export async function extractPptx(buffer: ArrayBuffer): Promise<string[]> {
  const zip = await JSZip.loadAsync(buffer);
  const slides = Object.keys(zip.files)
    .map((path) => ({
      path,
      match: path.match(/^ppt\/slides\/slide(\d+)\.xml$/),
    }))
    .filter((entry) => entry.match)
    .sort((a, b) => Number(a.match![1]) - Number(b.match![1]));

  if (slides.length === 0) {
    throw new Error("The PPTX contains no readable slides.");
  }

  return await Promise.all(slides.map(async ({ path }) => {
    const xml = await zip.file(path)!.async("string");
    const paragraphs = xml.match(/<a:p(?:\s[^>]*)?>[\s\S]*?<\/a:p>/g) ?? [xml];
    return paragraphs.map((paragraph) =>
      [...paragraph.matchAll(/<a:t(?:\s[^>]*)?>([\s\S]*?)<\/a:t>/g)]
        .map((match) => decodeXml(match[1]).trim())
        .filter(Boolean)
        .join(" ")
    ).filter(Boolean).join("\n");
  }));
}
