import { selectConcept } from "./selection.ts";
Deno.test("adaptive selection prioritizes weak material and rotates recent topics", () => {
  const concepts = [{ id: "strong", importance: 3 }, {
    id: "weak",
    importance: 3,
  }, { id: "new", importance: 3 }];
  const mastery = [
    { concept_id: "strong", mastery_pct: 95, due_at: null },
    { concept_id: "weak", mastery_pct: 20, due_at: null },
  ];
  if (selectConcept(concepts, mastery, []) !== "weak") {
    throw new Error("must target weakness");
  }
  if (selectConcept(concepts, mastery, ["weak"]) !== "new") {
    throw new Error("must rotate");
  }
  if (selectConcept([], [], []) !== undefined) throw new Error("empty corpus");
});
