/** Reject incomplete model output before it can become a student's mark. */
export const RUBRIC_FIELDS = [
  "concept_accuracy",
  "completeness",
  "technical_vocabulary",
  "logical_flow",
  "depth",
  "examples_used",
] as const;

function text(value: unknown, max: number): boolean {
  return typeof value === "string" && value.trim().length > 0 &&
    value.length <= max;
}

function citations(value: unknown, labels: Set<string>): boolean {
  return Array.isArray(value) && value.length > 0 &&
    value.every((v) =>
      typeof v === "string" && labels.has(v.trim().toUpperCase())
    );
}

export function validateQuestion(
  parsed: Record<string, unknown>,
  labels: Set<string>,
): string | null {
  if (
    !text(parsed.question, 2000) ||
    (parsed.question as string).trim().length < 12
  ) return "missing question";
  if (
    !Array.isArray(parsed.expects) || parsed.expects.length < 1 ||
    parsed.expects.length > 12 ||
    !parsed.expects.every((p) => text(p, 1000))
  ) return "expected points must be a nonempty list of text";
  if (!citations(parsed.cites, labels)) {
    return "question must cite only supplied passages";
  }
  return null;
}

export function validateEvaluation(
  parsed: Record<string, unknown>,
  labels: Set<string>,
): string | null {
  const rubric = parsed.rubric;
  if (!rubric || typeof rubric !== "object" || Array.isArray(rubric)) {
    return "missing rubric";
  }
  for (const field of RUBRIC_FIELDS) {
    const score = (rubric as Record<string, unknown>)[field];
    if (
      typeof score !== "number" || !Number.isFinite(score) || score < 0 ||
      score > 100
    ) {
      return `invalid score: ${field}`;
    }
  }
  if (!text(parsed.verdict, 300) || !text(parsed.feedback, 4000)) {
    return "missing actionable feedback";
  }
  if (!Array.isArray(parsed.gaps) || parsed.gaps.length > 5) {
    return "gaps must be a list of up to five items";
  }
  for (const gap of parsed.gaps) {
    if (
      !gap || typeof gap !== "object" || !text(gap.label, 200) ||
      !text(gap.detail, 2000) || !citations(gap.cites, labels)
    ) return "each gap must explain and cite a supplied passage";
  }
  if (
    RUBRIC_FIELDS.some((field) =>
      (rubric as Record<string, number>)[field] < 100
    ) && !parsed.gaps.length
  ) {
    return "deducted marks need at least one cited explanation";
  }
  return null;
}
