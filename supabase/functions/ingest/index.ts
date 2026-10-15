// Ingestion: a PDF becomes chunks, embeddings and concepts.
//
// This runs as an Edge Function rather than in the Flutter client for one
// reason that matters: the provider key stays server-side. A key shipped in
// a web bundle is a key anyone can read from devtools and spend.
//
// It runs under the *caller's* JWT, not the service role, so every insert is
// still subject to RLS. A bug here cannot write into another student's rows.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.47.10";
import { extractText, getDocumentProxy } from "https://esm.sh/unpdf@0.12.1";
import mammoth from "https://esm.sh/mammoth@1.8.0/mammoth.browser.js";
import { extractPptx } from "./extraction.ts";
import { evidenceMatches, normalizeEvidence } from "./grounding.ts";
import {
  chatJson,
  embed,
  resolveEmbedProvider,
  resolveProvider,
} from "../_shared/llm.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/** Split page text into overlapping windows, keeping the page number. */
function chunkPages(pages: string[], size = 1100, overlap = 150) {
  const out: { content: string; page: number }[] = [];
  pages.forEach((raw, i) => {
    const text = raw.replace(/\s+/g, " ").trim();
    if (text.length < 40) return; // a page of headers carries nothing to ask about
    for (let start = 0; start < text.length; start += size - overlap) {
      const slice = text.slice(start, start + size).trim();
      if (slice.length >= 40) out.push({ content: slice, page: i + 1 });
      if (start + size >= text.length) break;
    }
  });
  return out;
}

/** Ask for the concepts a viva would actually examine. */
async function extractConcepts(
  sample: string,
  p: ReturnType<typeof resolveProvider>,
) {
  const parsed = await chatJson(
    p,
    "You identify examinable concepts in study notes. Reply with minified JSON only: " +
      '{"concepts":[{"name":string,"description":string,"importance":1-3,"prerequisites":[string],"evidence":string}]}. ' +
      'Use a concept name that occurs in its evidence quote (such as "Deadlock" or "Virtual Memory"), not ' +
      "section headings. description must be a concise definition supported only by " +
      "the notes. For each concept, evidence must be a verbatim quote of at least " +
      "five words copied from one passage in the notes that directly supports the " +
      "concept and its description. Do not invent evidence, concepts, or definitions. " +
      "Prerequisites must reference other names in your own list, or be empty. " +
      "Return only concepts for which you can quote exact evidence; fewer than five " +
      "is better than unsupported concepts.",
    `NOTES:
${sample}`,
    0.2,
    (o) =>
      Array.isArray(o.concepts) && o.concepts.length > 0
        ? null
        : "returned no concepts",
  );
  return (parsed.concepts ?? []) as {
    name: string;
    description?: string;
    importance?: number;
    prerequisites?: string[];
    evidence?: string;
  }[];
}

/**
 * Reserve budget before spending money.
 *
 * Every model request in this function goes through here. The reservation is
 * atomic in Postgres, so two concurrent requests cannot both pass the last
 * unit of a nearly-exhausted budget — a check done in TypeScript would leave
 * exactly that race.
 */
async function claimBudget(
  supabase: SupabaseClient,
  estimatedTokens: number,
): Promise<{ ok: true; callsLeft: number } | { ok: false; reason: string }> {
  const { data, error } = await supabase
    .rpc("claim_model_call", { p_estimated_tokens: estimatedTokens })
    .single();
  if (error) {
    // Failing closed: a quota system that opens on its own error is not one.
    return { ok: false, reason: `budget check failed: ${error.message}` };
  }
  const row = data as {
    allowed: boolean;
    calls_left: number;
    reason: string | null;
  };
  return row.allowed
    ? { ok: true, callsLeft: row.calls_left }
    : { ok: false, reason: row.reason ?? "daily limit reached" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing Authorization" }, 401);

  // The caller's token, so RLS applies to everything below.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  let documentId = "";
  try {
    const body = await req.json();
    documentId = body.document_id;
    if (!documentId) return json({ error: "document_id is required" }, 400);

    const { data: doc, error: docErr } = await supabase
      .from("document")
      .select("id, subject_id, user_id, storage_path, filename, mime_type")
      .eq("id", documentId)
      .single();
    if (docErr || !doc) return json({ error: "document not found" }, 404);

    // Resolve configuration only after identifying the owned document so
    // configuration failures reach the catch block and stop the spinner.
    let provider, embedProvider;
    try {
      provider = resolveProvider();
      embedProvider = resolveEmbedProvider();
    } catch {
      await supabase.from("document").update({
        status: "failed",
        error_code: "provider_not_configured",
        error_message:
          "Document processing is not configured yet. The app owner needs to add the embedding API key. Your file is saved; retry after setup is complete.",
      }).eq("id", documentId);
      return json({
        error: "provider_not_configured",
        message:
          "Document processing needs an embedding API key. Your uploaded file is saved.",
      }, 503);
    }

    const budget = await claimBudget(supabase, 20000);
    if (!budget.ok) {
      await supabase.from("document").update({
        status: "failed",
        error_code: "quota_exceeded",
        error_message: budget.reason,
      }).eq("id", documentId);
      return json({ error: "quota_exceeded", message: budget.reason }, 429);
    }

    // Preserve source IDs and historical citations on a retry. Uploaded files
    // are immutable by content hash; a different file requires a new document.
    const { data: priorChunks, error: priorErr } = await supabase
      .from("chunk")
      .select("id, content, chunk_index")
      .eq("document_id", documentId);
    if (priorErr) {
      throw new Error(`could not read previous chunks: ${priorErr.message}`);
    }

    await supabase.from("document").update({ status: "extracting", error_code: null, error_message: null }).eq(
      "id",
      documentId,
    );

    // -- 1. text ----------------------------------------------------------
    const { data: file, error: dlErr } = await supabase.storage
      .from("documents")
      .download(doc.storage_path);
    if (dlErr || !file) throw new Error(`download failed: ${dlErr?.message}`);

    const ext = (doc.filename || "").split(".").pop()?.toLowerCase() || "pdf";
    const buffer = await file.arrayBuffer();

    let pages: string[] = [];
    let totalPages = 1;

    if (ext === "pdf") {
      const pdf = await getDocumentProxy(new Uint8Array(buffer));
      const extracted = await extractText(pdf, { mergePages: false });
      pages = Array.isArray(extracted.text) ? extracted.text : [extracted.text];
      totalPages = extracted.totalPages;
    } else if (ext === "docx") {
      const result = await mammoth.extractRawText({ arrayBuffer: buffer });
      pages = [result.value];
    } else if (ext === "pptx") {
      pages = await extractPptx(buffer);
      totalPages = pages.length;
    } else if (
      ext === "txt" || ext === "csv" || ext === "md" || ext === "markdown"
    ) {
      const text = new TextDecoder().decode(buffer);
      pages = [text];
    } else {
      throw new Error(`Unsupported file type: ${ext}`);
    }

    const chunks = chunkPages(pages);
    if (chunks.length === 0) {
      // A scanned PDF with no text layer. Saying so is far more useful than
      // leaving the document stuck on "processing" forever.
      await supabase.from("document").update({
        status: "failed",
        error_code: "no_text",
        error_message:
          "No selectable text found. This looks like a scan — try a PDF exported from the original document.",
      }).eq("id", documentId);
      return json({ error: "no extractable text", pages: totalPages }, 422);
    }

    await supabase.from("document")
      .update({ status: "chunking", page_count: totalPages })
      .eq("id", documentId);

    const step = Math.max(1, Math.floor(chunks.length / 25));
    const sampleChunks = chunks.filter((_, i) => i % step === 0).slice(0, 25);
    const sample = sampleChunks.map((c) => c.content).join("\n---\n").slice(
      0,
      24000,
    );

    // Embeddings and concept extraction are independent once text has been
    // chunked. Running them together removes an entire model round trip from
    // the user's wait without changing either result.
    await supabase.from("document").update({ status: "embedding" }).eq(
      "id",
      documentId,
    );
    const [vectors, extractedConcepts] = await Promise.all([
      embed(embedProvider, chunks.map((c) => c.content), true),
      extractConcepts(sample, provider),
    ]);

    // A model-produced label is not evidence that the notes teach the idea.
    // Keep only concepts whose quoted support can be found byte-for-byte
    // (ignoring case, Unicode composition and whitespace) in a real chunk.
    const concepts = extractedConcepts.flatMap((candidate) => {
      const name = typeof candidate.name === "string"
        ? candidate.name.trim()
        : "";
      const evidence = typeof candidate.evidence === "string"
        ? candidate.evidence.trim()
        : "";
      if (
        name.length < 2 || !evidence ||
        !normalizeEvidence(evidence).includes(normalizeEvidence(name))
      ) return [];
      const matchingChunks = evidenceMatches(chunks, evidence);
      if (matchingChunks.length === 0) return [];
      return [{
        ...candidate,
        name,
        // Flashcards use an exact source excerpt, avoiding generated definitions
        // whose quoted evidence may mention the topic without supporting them.
        description: evidence,
        evidence,
        evidenceChunkIds: new Set(
          matchingChunks.map((chunk) => chunks.indexOf(chunk)),
        ),
      }];
    });

    const priorByIndex = new Map(
      (priorChunks ?? []).map((c) => [c.chunk_index, c]),
    );
    if (
      (priorChunks ?? []).some((c) =>
        chunks[c.chunk_index]?.content !== c.content
      )
    ) {
      throw new Error(
        "The extracted source changed. Upload it as a new document to preserve previous question citations.",
      );
    }
    const missing = chunks.map((c, i) => ({ ...c, chunk_index: i }))
      .filter((c) => !priorByIndex.has(c.chunk_index));
    let inserted = priorChunks ?? [];
    if (missing.length > 0) {
      const { data: addedChunks, error: chunkErr } = await supabase
        .from("chunk")
        .insert(missing.map((c) => ({
          document_id: doc.id,
          subject_id: doc.subject_id,
          user_id: doc.user_id,
          chunk_index: c.chunk_index,
          content: c.content,
          page_number: c.page,
          token_count: Math.ceil(c.content.length / 4),
          embedding: JSON.stringify(vectors[c.chunk_index]),
        })))
        .select("id, content, chunk_index");
      if (chunkErr) throw new Error(`chunk insert failed: ${chunkErr.message}`);
      inserted = [...inserted, ...(addedChunks ?? [])];
    }

    // -- 3. concepts ------------------------------------------------------
    // The unique index is on lower(btrim(canonical_name)), an *expression*,
    // which PostgREST's onConflict cannot target — an upsert naming those
    // columns fails and, unchecked, silently yields zero concepts. So read
    // what exists, insert only what is new, and check the error.
    const { data: existing } = await supabase
      .from("concept")
      .select("id, canonical_name, description, source_evidence")
      .eq("subject_id", doc.subject_id);

    const norm = (s: string) => s.trim().toLowerCase();
    const known = new Map(
      (existing ?? []).map((c) => [norm(c.canonical_name), c.id]),
    );

    const fresh = concepts
      .map((c) => ({
        ...c,
        name: c.name.trim().slice(0, 120),
        description: c.description?.trim().slice(0, 600) ?? "",
        evidence: c.evidence.trim().slice(0, 1200),
      }))
      .filter((c) =>
        c.name.length > 1 && c.evidence.length > 0 && !known.has(norm(c.name))
      );

    // Two concepts differing only in case would violate the index together.
    const seen = new Set<string>();
    const toInsert = fresh.filter((c) => {
      if (seen.has(norm(c.name))) return false;
      seen.add(norm(c.name));
      return true;
    });

    if (toInsert.length > 0) {
      const { data: added, error: conceptErr } = await supabase
        .from("concept")
        .insert(toInsert.map((c) => ({
          subject_id: doc.subject_id,
          user_id: doc.user_id,
          canonical_name: c.name,
          description: c.description || null,
          source_evidence: c.evidence,
          importance: Math.min(3, Math.max(1, Math.round(c.importance ?? 2))),
          source_document_id: doc.id,
        })))
        .select("id, canonical_name, source_evidence");
      if (conceptErr) {
        throw new Error(`concept insert failed: ${conceptErr.message}`);
      }
      for (const c of added ?? []) known.set(norm(c.canonical_name), c.id);
    }

    // Re-ingestion also repairs concepts created by older builds, which left
    // description null and forced the client to invent generic flashcards.
    const groundedByName = new Map(concepts.map((c) => [norm(c.name), c]));
    const existingByName = new Map(
      (existing ?? []).map((c) => [norm(c.canonical_name), c]),
    );
    const evidenceByConcept = new Map<string, string>();
    const evidenceChunkIndexesByConcept = new Map<string, Set<number>>();
    for (const [name, candidate] of groundedByName) {
      const conceptId = known.get(name);
      if (!conceptId) continue;
      evidenceByConcept.set(conceptId, candidate.evidence);
      evidenceChunkIndexesByConcept.set(conceptId, candidate.evidenceChunkIds);
      const prior = existingByName.get(name);
      if (prior) {
        const { error: updateErr } = await supabase.from("concept")
          .update({
            description: candidate.evidence,
            source_evidence: candidate.evidence,
          })
          .eq("id", conceptId);
        if (updateErr) {
          throw new Error(
            `concept grounding update failed: ${updateErr.message}`,
          );
        }
      }
    }

    // -- 4. prerequisite edges -------------------------------------------
    // The differentiator: "you are failing Deadlock because you never learned
    // Mutual Exclusion" needs this graph to exist.
    const edges: {
      subject_id: string;
      user_id: string;
      prerequisite_concept_id: string;
      dependent_concept_id: string;
    }[] = [];
    const edgeSeen = new Set<string>();

    for (const c of concepts) {
      const dependent = known.get(norm(c.name));
      for (const p of c.prerequisites ?? []) {
        const prereq = known.get(norm(p));
        const key = `${prereq}->${dependent}`;
        if (
          dependent && prereq &&
          evidenceByConcept.has(dependent) && evidenceByConcept.has(prereq) &&
          dependent !== prereq && !edgeSeen.has(key)
        ) {
          edgeSeen.add(key);
          edges.push({
            subject_id: doc.subject_id,
            user_id: doc.user_id,
            prerequisite_concept_id: prereq,
            dependent_concept_id: dependent,
          });
        }
      }
    }

    // The graph must be acyclic. Models readily emit both "Deadlock requires
    // Mutual Exclusion" and "Mutual Exclusion is part of Deadlock", and a
    // cycle makes the whole feature useless: "what is holding this back"
    // has no answer when A blocks B and B blocks A. Keep the first edge of
    // any pair and drop the one that closes a loop.
    const reaches = (from: string, to: string, adj: Map<string, string[]>) => {
      const stack = [from];
      const seen = new Set<string>();
      while (stack.length) {
        const at = stack.pop()!;
        if (at === to) return true;
        if (seen.has(at)) continue;
        seen.add(at);
        for (const next of adj.get(at) ?? []) stack.push(next);
      }
      return false;
    };

    const adjacency = new Map<string, string[]>();
    const acyclic: typeof edges = [];
    let dropped = 0;
    for (const e of edges) {
      // Adding prereq -> dependent closes a loop only if dependent already
      // reaches prereq.
      if (
        reaches(e.dependent_concept_id, e.prerequisite_concept_id, adjacency)
      ) {
        dropped++;
        continue;
      }
      acyclic.push(e);
      const list = adjacency.get(e.prerequisite_concept_id) ?? [];
      list.push(e.dependent_concept_id);
      adjacency.set(e.prerequisite_concept_id, list);
    }

    if (acyclic.length > 0) {
      const { error: edgeErr } = await supabase.from("concept_edge").insert(
        acyclic,
      );
      // Concepts are already useful without every edge, so a failure here
      // does not sink the whole ingestion.
      if (edgeErr) console.warn("edge insert:", edgeErr.message);
    }

    // -- 5. concept -> chunk links ---------------------------------------
    // `search_notes` accepts a concept filter and nothing populated this
    // table, so focused practice silently fell back to searching the whole
    // subject. Linking here is what makes "practise Deadlock" actually
    // retrieve the deadlock passages rather than whatever ranked highest.
    //
    // Name matching rather than a second embedding pass: the concept names
    // were extracted *from* this text, so they occur in it almost by
    // construction, and it costs no extra API calls.
    const links: {
      concept_id: string;
      chunk_id: string;
      user_id: string;
      relevance: number;
    }[] = [];

    for (const [conceptId, evidence] of evidenceByConcept) {
      const needle = normalizeEvidence(evidence);
      const eligibleChunkIndexes =
        evidenceChunkIndexesByConcept.get(conceptId) ?? new Set<number>();
      const hits: { id: string; count: number }[] = [];
      for (const c of inserted ?? []) {
        // Match the same evidence-bearing source chunks without relying on a
        // generated concept-name guess or response ordering.
        if (!eligibleChunkIndexes.has(c.chunk_index)) continue;
        if (normalizeEvidence(c.content).includes(needle)) {
          hits.push({ id: c.id, count: 1 });
        }
      }
      if (hits.length === 0) continue;

      // Normalised against the strongest hit, so relevance is comparable
      // across concepts of very different frequency.
      const top = Math.max(...hits.map((h) => h.count));
      for (const h of hits) {
        links.push({
          concept_id: conceptId,
          chunk_id: h.id,
          user_id: doc.user_id,
          relevance: Math.round((h.count / top) * 100) / 100,
        });
      }
    }

    if (links.length > 0) {
      // Ingestion may be retried. Replace links for the concepts verified in
      // this pass so stale, name-only associations cannot survive a repair.
      const verifiedIds = [...evidenceByConcept.keys()];
      if (verifiedIds.length > 0) {
        const { error: deleteLinksErr } = await supabase.from("concept_chunk")
          .delete()
          .in("concept_id", verifiedIds)
          .in("chunk_id", (inserted ?? []).map((chunk) => chunk.id));
        if (deleteLinksErr) {
          throw new Error(
            `concept link refresh failed: ${deleteLinksErr.message}`,
          );
        }
      }
      const { error: linkErr } = await supabase.from("concept_chunk").insert(
        links,
      );
      if (linkErr) {
        throw new Error(
          `concept-to-source link insert failed: ${linkErr.message}`,
        );
      }
    }

    await supabase.from("document")
      .update({ status: "ready", processed_at: new Date().toISOString(), error_code: null, error_message: null })
      .eq("id", documentId);

    return json({
      ok: true,
      pages: totalPages,
      chunks: inserted?.length ?? 0,
      concepts: evidenceByConcept.size,
      edges: acyclic.length,
      concept_links: links.length,
      cycles_dropped: dropped,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (documentId) {
      // Record why, so the UI can show the student something actionable
      // instead of a document stuck on "processing" with no explanation.
      await supabase.from("document").update({
        status: "failed",
        error_code: "ingest_failed",
        error_message: message.slice(0, 500),
      }).eq("id", documentId);
    }
    return json({ error: message }, 500);
  }
});
