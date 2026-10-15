import {
  chatJson,
  DIMENSIONS,
  embed,
  extractJson,
  type Provider,
  responseModel,
} from "./llm.ts";

const provider: Provider = {
  name: "test",
  baseUrl: "https://example.invalid",
  key: "test",
  chatModels: ["first", "second"],
  embedModel: "test",
  supportsDimensions: false,
  inputTypeField: false,
  extraHeaders: {},
};
function assert(ok: unknown): asserts ok {
  if (!ok) throw new Error("assertion failed");
}

Deno.test("JSON extraction handles fences, reasoning, and braces in strings", () => {
  assert(
    extractJson('```json\n{"text":"a } brace"}\n```').text === "a } brace",
  );
  assert(extractJson('<think>{"wrong":true}</think> {"ok":true}').ok === true);
  assert(extractJson('preface {bad} then {"ok":true}').ok === true);
});

Deno.test("invalid JSON falls through to the next model", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (() =>
    Promise.resolve(Response.json({
      choices: [{
        message: {
          content: ++calls === 1 ? "broken" : '{"answer":"grounded"}',
        },
      }],
    }))) as typeof fetch;
  try {
    const result = await chatJson(provider, "system", "user", 0);
    assert(result.answer === "grounded" && calls === 2);
    assert(responseModel(result) === "test/second");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("embeddings are reordered by input index", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(Response.json({
      data: [
        { index: 1, embedding: Array(DIMENSIONS).fill(2) },
        { index: 0, embedding: Array(DIMENSIONS).fill(1) },
      ],
    }))) as typeof fetch;
  try {
    const result = await embed(provider, ["first", "second"], true);
    assert(result[0][0] === 1 && result[1][0] === 2);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("missing, duplicate, zero and invalid embedding vectors are refused", async () => {
  const original = globalThis.fetch;
  try {
    for (
      const data of [[], [{ index: 0, embedding: Array(DIMENSIONS).fill(1) }, {
        index: 0,
        embedding: Array(DIMENSIONS).fill(1),
      }], [{ index: 0, embedding: Array(DIMENSIONS).fill(0) }, {
        index: 1,
        embedding: Array(DIMENSIONS).fill(1),
      }], [{ index: 0, embedding: Array(DIMENSIONS).fill(null) }, {
        index: 1,
        embedding: Array(DIMENSIONS).fill(1),
      }]]
    ) {
      globalThis.fetch = (() =>
        Promise.resolve(Response.json({ data }))) as typeof fetch;
      let rejected = false;
      try {
        await embed(provider, ["first", "second"], true);
      } catch {
        rejected = true;
      }
      assert(rejected);
    }
  } finally {
    globalThis.fetch = original;
  }
});
