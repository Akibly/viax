import { assertEquals } from "jsr:@std/assert@1";
import { evidenceMatches } from "./grounding.ts";

Deno.test("evidence must occur verbatim in a real source chunk", () => {
  const chunks = [
    {
      content:
        "A semaphore is a synchronization variable used to control access to shared resources.",
    },
  ];

  assertEquals(
    evidenceMatches(
      chunks,
      "A semaphore is a synchronization variable used to control access to shared resources.",
    ).length,
    1,
  );
  assertEquals(
    evidenceMatches(
      chunks,
      "Semaphores prevent race conditions and deadlocks in every concurrent program.",
    ).length,
    0,
  );
  assertEquals(evidenceMatches(chunks, "a semaphore is useful"), []);
});
