// Model provider, behind one seam.
//
// OpenRouter and NVIDIA NIM both speak the OpenAI wire format, so the only
// things that actually differ are the base URL, the key and the model names.
// Keeping that in one place means switching providers is a secrets change,
// not a rewrite — which matters because the binding constraint on OpenRouter's
// free tier is 50 requests/day, and one viva exchange costs four.
//
// Provider is chosen by which key is present, so setting NVIDIA_API_KEY is
// enough to move over. OpenRouter stays as the fallback.

export interface Provider {
  name: string;
  baseUrl: string;
  key: string;
  chatModels: string[];
  embedModel: string;
  /** Whether the embeddings endpoint honours an explicit output size. */
  supportsDimensions: boolean;
  extraHeaders: Record<string, string>;
  /** NVIDIA's retrieval embedders need to know query vs passage. */
  inputTypeField: boolean;
}

/// Must match chunk.embedding halfvec(1024). Pinned in the column, the
/// backend and here; a silent mismatch degrades retrieval without erroring.
export const DIMENSIONS = 1024;
const responseModels = new WeakMap<object, string>();
/** Provider provenance must reflect the model that actually succeeded. */
export function responseModel(response: Record<string, unknown>): string {
  return responseModels.get(response) ?? "unknown";
}

function env(...names: string[]): string | undefined {
  for (const name of names) {
    const value = Deno.env.get(name)?.trim();
    if (value) return value;
  }
  return undefined;
}

function modelList(value: string | undefined, fallback: string[]): string[] {
  const configured =
    value?.split(",").map((model) => model.trim()).filter(Boolean) ?? [];
  return [...new Set([...configured, ...fallback])];
}

export function resolveProvider(): Provider {
  // Supabase secrets conventionally use the short name while the FastAPI
  // service uses VIVAX_* names. Accepting both prevents a perfectly valid
  // deployment from looking like "AI is broken" because the two runtimes
  // read different spellings of the same secret.
  // Prefer the dedicated low-latency chat provider when both keys exist.
  // OpenRouter remains an optional chat fallback. Picking
  // it first just because its secret was present meant `openrouter/free`
  // could consume the whole request timeout while the healthy NVIDIA key was
  // never attempted.
  const nvidia = env("NVIDIA_API_KEY", "VIVAX_NVIDIA_API_KEY");
  if (nvidia) {
    return {
      name: "nvidia",
      baseUrl: "https://integrate.api.nvidia.com/v1",
      key: nvidia,
      chatModels: modelList(env("NVIDIA_CHAT_MODELS"), [
        "nvidia/nemotron-3.5-lightning-30b-a3b",
        "nvidia/nemotron-3-super-120b-a12b",
        "nvidia/nemotron-3-nano-30b-a3b",
      ]),
      embedModel: "",
      supportsDimensions: false,
      extraHeaders: {},
      inputTypeField: true,
    };
  }

  const openrouter = env("OPENROUTER_API_KEY", "VIVAX_OPENROUTER_API_KEY");
  if (openrouter) {
    const configuredModels = env(
      "OPENROUTER_CHAT_MODELS",
      "VIVAX_MODEL_FALLBACKS",
    );
    return {
      name: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      key: openrouter,
      // Individual free slugs churn. openrouter/free is a maintained router
      // that chooses a currently available model with the capabilities in
      // the request (including JSON output), so it is the durable fallback.
      chatModels: modelList(configuredModels, [
        "nvidia/nemotron-3.5-lightning:free",
        "openrouter/free",
      ]),
      embedModel: env("OPENROUTER_EMBED_MODEL") ??
        "liquid/lfm-2.5-embedding-350m:free",
      supportsDimensions: false,
      extraHeaders: {
        "HTTP-Referer": "https://vivax.app",
        "X-Title": "VivaX",
      },
      inputTypeField: false,
    };
  }

  throw new Error(
    "no model provider configured: set NVIDIA_API_KEY or OPENROUTER_API_KEY",
  );
}

/**
 * Use NVIDIA's dimension-configurable retrieval model for both stored passages
 * and query embeddings. Request 1024 dimensions at the API; never slice vectors.
 */
export function resolveEmbedProvider(): Provider {
  const nvidia = env("NVIDIA_API_KEY", "VIVAX_NVIDIA_API_KEY");
  if (nvidia) {
    return {
      name: "nvidia",
      baseUrl: "https://integrate.api.nvidia.com/v1",
      key: nvidia,
      chatModels: [],
      embedModel: env("NVIDIA_EMBED_MODEL") ?? "nvidia/llama-nemotron-embed-vl-1b-v2",
      supportsDimensions: true,
      extraHeaders: {},
      inputTypeField: true,
    };
  }
  const openrouter = env("OPENROUTER_API_KEY", "VIVAX_OPENROUTER_API_KEY");
  if (openrouter) {
    const embedModel = env("OPENROUTER_EMBED_MODEL") ??
      "liquid/lfm-2.5-embedding-350m:free";
    return {
      name: "openrouter-embed",
      baseUrl: "https://openrouter.ai/api/v1",
      key: openrouter,
      chatModels: [],
      embedModel,
      // OpenAI's embedding model can be shortened explicitly. The default
      // free Liquid model already emits exactly 1024 dimensions and does not
      // advertise a dimensions parameter.
      supportsDimensions: embedModel.includes("text-embedding-3"),
      extraHeaders: { "HTTP-Referer": "https://vivax.app", "X-Title": "VivaX" },
      inputTypeField: false,
    };
  }
  throw new Error(
    "no embedding provider configured: set NVIDIA_API_KEY or OPENROUTER_API_KEY",
  );
}

/**
 * Every model worth trying, across providers, in order.
 *
 * A single provider's rate limit should not end a viva. NVIDIA's free tier
 * returns 429 under load and its catalogue turns over — models present last
 * week 404 today — so the chain continues into OpenRouter rather than
 * stopping at the end of one vendor's list.
 */
function chatChain(primary: Provider): { model: string; provider: Provider }[] {
  const chain = primary.chatModels.map((model) => ({
    model,
    provider: primary,
  }));

  const openrouter = env("OPENROUTER_API_KEY", "VIVAX_OPENROUTER_API_KEY");
  if (openrouter && primary.name !== "openrouter") {
    const fallback: Provider = {
      name: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      key: openrouter,
      chatModels: [],
      embedModel: env("OPENROUTER_EMBED_MODEL") ??
        "liquid/lfm-2.5-embedding-350m:free",
      supportsDimensions: false,
      extraHeaders: { "HTTP-Referer": "https://vivax.app", "X-Title": "VivaX" },
      inputTypeField: false,
    };
    // Verified working and returning parseable JSON, tested against the live
    // catalogue rather than chosen by reputation. Free models churn: two
    // earlier picks now answer 403 "only available on agentic harnesses", and
    // one was withdrawn entirely.
    for (
      const model of modelList(
        env("OPENROUTER_CHAT_MODELS", "VIVAX_MODEL_FALLBACKS"),
        ["nvidia/nemotron-3.5-lightning:free", "openrouter/free"],
      )
    ) {
      chain.push({ model, provider: fallback });
    }
  }

  const nvidia = env("NVIDIA_API_KEY", "VIVAX_NVIDIA_API_KEY");
  if (nvidia && primary.name !== "nvidia") {
    const fallback: Provider = {
      name: "nvidia",
      baseUrl: "https://integrate.api.nvidia.com/v1",
      key: nvidia,
      chatModels: [],
      embedModel: "",
      supportsDimensions: false,
      extraHeaders: {},
      inputTypeField: true,
    };
    for (
      const model of modelList(env("NVIDIA_CHAT_MODELS"), [
        "nvidia/nemotron-3.5-lightning-30b-a3b",
        "nvidia/nemotron-3-super-120b-a12b",
        "nvidia/nemotron-3-nano-30b-a3b",
      ])
    ) {
      chain.push({ model, provider: fallback });
    }
  }
  return chain;
}

/** Walk the model chain. Raises only when every candidate has refused. */
export async function chat(
  p: Provider,
  system: string,
  user: string,
  temperature: number,
  maxTokens = 2000,
): Promise<string> {
  let last = "no models tried";
  const deadline = Date.now() + 60_000;
  for (const { model, provider } of chatChain(p)) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    let response: Response;
    try {
      response = await fetch(`${provider.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${provider.key}`,
          "Content-Type": "application/json",
          ...provider.extraHeaders,
        },
        body: JSON.stringify({
          model,
          temperature,
          max_tokens: maxTokens,
          ...(provider.name === "nvidia"
            ? {
              top_p: 0.95,
              chat_template_kwargs: { enable_thinking: false },
            }
            : {}),
          messages: [
            { role: "system", content: system },
            { role: "user", content: user },
          ],
        }),
        signal: AbortSignal.timeout(Math.min(20_000, remaining)),
      });
    } catch (e) {
      last = `${model}: ${e instanceof Error ? e.message : String(e)}`;
      continue;
    }

    if (response.status === 429) {
      // Shedding load. Move on rather than hammer it.
      last = `${model}: rate limited`;
      continue;
    }
    if (!response.ok) {
      last = `${model}: HTTP ${response.status} ${
        (await response.text()).slice(0, 120)
      }`;
      continue;
    }
    try {
      const body = await response.json();
      const content = body?.choices?.[0]?.message?.content;
      if (typeof content === "string" && content.trim()) return content;
      last = `${model}: empty reply`;
    } catch {
      last = `${model}: malformed response`;
    }
  }
  throw new Error(`every model failed (${last})`);
}

/**
 * Embed one or more texts.
 *
 * `passage` distinguishes indexing from querying: asymmetric retrieval models
 * embed the two differently, and using the wrong side quietly costs recall.
 */
export async function embed(
  p: Provider,
  texts: string[],
  passage: boolean,
): Promise<number[][]> {
  const vectors: number[][] = [];
  // NVIDIA caps a batch well below OpenAI's, so keep batches conservative.
  const batchSize = p.name === "nvidia" ? 32 : 64;

  for (let i = 0; i < texts.length; i += batchSize) {
    const batch = texts.slice(i, i + batchSize);
    const payload: Record<string, unknown> = {
      model: p.embedModel,
      input: batch,
    };
    if (p.supportsDimensions) payload.dimensions = DIMENSIONS;
    if (p.inputTypeField) {
      payload.input_type = passage ? "passage" : "query";
      payload.truncate = "END";
    }

    const r = await fetch(`${p.baseUrl}/embeddings`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${p.key}`,
        "Content-Type": "application/json",
        ...p.extraHeaders,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(90_000),
    });
    if (!r.ok) {
      throw new Error(
        `embedding failed: ${r.status} ${(await r.text()).slice(0, 200)}`,
      );
    }
    const body = await r.json();
    if (!Array.isArray(body.data) || body.data.length !== batch.length) {
      throw new Error("embedding response count does not match input count");
    }
    const ordered: number[][] = new Array(batch.length);
    for (const d of body.data) {
      if (
        !Number.isInteger(d?.index) || d.index < 0 || d.index >= batch.length ||
        ordered[d.index]
      ) {
        throw new Error("embedding response has invalid or duplicate indices");
      }
      if (
        !Array.isArray(d.embedding) || d.embedding.length !== DIMENSIONS ||
        !d.embedding.every((value: unknown) =>
          typeof value === "number" && Number.isFinite(value)
        ) ||
        !d.embedding.some((value: number) => value !== 0)
      ) {
        throw new Error(
          `invalid embedding: expected ${DIMENSIONS} finite, nonzero dimensions`,
        );
      }
      ordered[d.index] = d.embedding;
    }
    vectors.push(...ordered);
  }
  return vectors;
}

/** Extract one object without confusing braces inside quoted strings with syntax. */
export function extractJson(raw: string): Record<string, unknown> {
  const text = raw.replace(/<think>[\s\S]*?<\/think>/gi, "");
  for (let start = 0; start < text.length; start++) {
    if (text[start] !== "{") continue;
    let depth = 0, quoted = false, escaped = false;
    for (let end = start; end < text.length; end++) {
      const char = text[end];
      if (quoted) {
        if (escaped) escaped = false;
        else if (char === "\\") escaped = true;
        else if (char === '"') quoted = false;
        continue;
      }
      if (char === '"') quoted = true;
      else if (char === "{") depth++;
      else if (char === "}" && --depth === 0) {
        try {
          const value = JSON.parse(text.slice(start, end + 1));
          if (value && typeof value === "object" && !Array.isArray(value)) {
            return value;
          }
        } catch {
          /* Skip malformed candidates; the provider walk can retry. */
        }
        break;
      }
    }
  }
  throw new Error("model reply contained no valid JSON object");
}

/**
 * Ask for JSON and keep asking until a model produces some.
 *
 * A model that answers with truncated or malformed JSON has failed just as
 * surely as one that returns 429, but the original code treated only the
 * transport as retryable: `chat` succeeded, parsing threw outside the loop,
 * and the remaining models were never tried. Parsing belongs inside the walk.
 *
 * `validate` lets the caller reject a reply that parses but is not an answer —
 * some models echo the example schema back verbatim, which is valid JSON and
 * completely useless.
 */
export async function chatJson(
  p: Provider,
  system: string,
  user: string,
  temperature: number,
  validate?: (parsed: Record<string, unknown>) => string | null,
): Promise<Record<string, unknown>> {
  let last = "no models tried";
  const deadline = Date.now() + 60_000;
  for (const { model, provider } of chatChain(p)) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    const single: Provider = { ...provider, chatModels: [model] };
    let raw: string;
    try {
      // A single-model provider, so `chat` does not re-walk the whole chain
      // from inside this loop.
      raw = await chatOnly(
        single,
        model,
        system,
        user,
        temperature,
        Math.min(20_000, remaining),
      );
    } catch (e) {
      last = e instanceof Error ? e.message : String(e);
      continue;
    }
    try {
      const parsed = extractJson(raw);
      const complaint = validate?.(parsed);
      if (complaint) {
        last = `${model}: ${complaint}`;
        continue;
      }
      responseModels.set(parsed, `${provider.name}/${model}`);
      return parsed;
    } catch (e) {
      last = `${model}: ${e instanceof Error ? e.message : String(e)}`;
      continue;
    }
  }
  throw new Error(`no model returned usable JSON (${last})`);
}

/** One request to one model. No chain walking. */
async function chatOnly(
  p: Provider,
  model: string,
  system: string,
  user: string,
  temperature: number,
  timeoutMs: number,
): Promise<string> {
  const r = await fetch(`${p.baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${p.key}`,
      "Content-Type": "application/json",
      ...p.extraHeaders,
    },
    body: JSON.stringify({
      model,
      temperature,
      max_tokens: 1600,
      ...(p.name === "nvidia"
        ? {
          top_p: 0.95,
          chat_template_kwargs: { enable_thinking: false },
        }
        : {}),
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      // NVIDIA models are prompted to emit JSON but do not all implement the
      // OpenAI response_format extension. Sending it to those models turns a
      // valid provider into a deterministic 400, so enforce the format only
      // where the endpoint advertises it.
      ...(p.name.startsWith("openrouter")
        ? { response_format: { type: "json_object" } }
        : {}),
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) {
    throw new Error(
      `${model}: HTTP ${r.status} ${(await r.text()).slice(0, 100)}`,
    );
  }
  const body = await r.json();
  const content = body?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) {
    throw new Error(`${model}: empty reply`);
  }
  return content;
}
