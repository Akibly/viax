/** Normalise whitespace and Unicode so a verbatim evidence span survives extraction. */
export function normalizeEvidence(value: string): string {
  return value.normalize("NFKC").replace(/\s+/g, " ").trim()
    .toLocaleLowerCase();
}

/** Return only source chunks that contain the model's claimed verbatim evidence. */
export function evidenceMatches<T extends { content: string }>(
  chunks: T[],
  evidence: string,
): T[] {
  const normalized = normalizeEvidence(evidence);
  const wordCount = normalized.split(/\s+/).filter(Boolean).length;
  if (normalized.length < 24 || wordCount < 5) return [];
  return chunks.filter((chunk) =>
    normalizeEvidence(chunk.content).includes(normalized)
  );
}
