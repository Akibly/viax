import {
  RUBRIC_FIELDS,
  validateEvaluation,
  validateQuestion,
} from "./validation.ts";
function assert(ok: unknown): asserts ok {
  if (!ok) throw new Error("assertion failed");
}
const labels = new Set(["P1"]);
const mark = () => ({
  rubric: Object.fromEntries(RUBRIC_FIELDS.map((field) => [field, 75])),
  verdict: "Partially supported",
  feedback: "Explain the condition in your notes.",
  gaps: [{
    label: "Condition",
    detail: "State when this holds.",
    cites: ["P1"],
  }],
});
Deno.test("complete cited evaluations pass", () =>
  assert(validateEvaluation(mark(), labels) === null));
Deno.test("missing and invalid scores cannot become zero marks", () => {
  for (const value of [undefined, "70", -1, 101, NaN, Infinity]) {
    const candidate: Record<string, unknown> = mark();
    (candidate.rubric as Record<string, unknown>).depth = value;
    assert(validateEvaluation(candidate, labels) !== null);
  }
});
Deno.test("uncited gaps and unexplained deductions are refused", () => {
  const candidate = mark();
  candidate.gaps[0].cites = ["P999"];
  assert(validateEvaluation(candidate, labels) !== null);
  candidate.gaps = [];
  assert(validateEvaluation(candidate, labels) !== null);
});
Deno.test("question expected points and citations must be usable", () => {
  const valid = {
    question: "Why does this condition hold?",
    expects: ["Explain the condition"],
    cites: ["P1"],
  };
  assert(validateQuestion(valid, labels) === null);
  assert(
    validateQuestion({ ...valid, expects: "not an array" }, labels) !== null,
  );
  assert(validateQuestion({ ...valid, cites: ["P999"] }, labels) !== null);
});
