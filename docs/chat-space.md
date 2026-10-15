# ViaX AI space

The Chat destination supports saved general conversations and conversations attached to a subject. Context is fixed after the first message; start a new conversation to switch modes. History displays the latest 100 conversations and 100 turns, while model context uses the latest eight turns with bounded lengths.

General replies use the configured chat provider. There is no live web browsing, universal knowledge, or freshness guarantee. The interface states these limits. The server supplies trusted instructions separately from untrusted conversation and note content.

Subject mode uses lexical matching over ready, non-deleted document chunks owned by the signed-in user. Up to five excerpts are supplied and shown in an expandable source panel. No embedding API is required for this retrieval path, but existing document ingestion still needs its configured embedding provider. Source labels are model-generated references to supplied excerpts, not proof that every generated claim is entailed.

Migration `20261015090000_chat_spaces.sql` adds conversations and turns with row-level ownership policies and a composite ownership foreign key. The authenticated `chat` Edge Function reserves the existing daily AI budget, loads bounded history, generates a reply, and persists one completed turn. A per-send UUID makes completed retries idempotent. Failed sends retain the draft. Simultaneous pending requests can still consume more than one provider call before the unique turn insert resolves.

Private provider keys remain in Supabase secrets. The web bundle contains only the project's publishable client configuration.

Assistant replies render selectable Markdown, including bold, headings, lists, and code blocks. User messages remain literal text. Remote Markdown images are not fetched; links open only for HTTP(S) URLs. Formatting applies to saved replies as well as new ones.
