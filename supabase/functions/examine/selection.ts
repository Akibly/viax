type Concept = { id: string; importance: number };
type Mastery = {
  concept_id: string;
  mastery_pct: number | string | null;
  due_at: string | null;
};

/** Prefer due and weak concepts, while making room for untested material. */
export function selectConcept(
  concepts: Concept[],
  mastery: Mastery[],
  recentIds: string[],
  now = Date.now(),
): string | undefined {
  const byId = new Map(mastery.map((row) => [row.concept_id, row]));
  const fresh = concepts.filter((concept) => !recentIds.includes(concept.id));
  const pool = fresh.length ? fresh : concepts;
  const priority = (concept: Concept) => {
    const state = byId.get(concept.id);
    const numeric = state?.mastery_pct == null
      ? NaN
      : Number(state.mastery_pct);
    const weakness = Number.isFinite(numeric)
      ? 100 - Math.max(0, Math.min(100, numeric))
      : 65;
    const due = state?.due_at ? Date.parse(state.due_at) : NaN;
    return weakness + (due <= now ? 25 : 0) +
      Math.min(5, Math.max(0, concept.importance)) * 3;
  };
  return [...pool].sort((a, b) =>
    priority(b) - priority(a) || a.id.localeCompare(b.id)
  )[0]?.id;
}
