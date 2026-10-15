# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Students preparing for oral examinations from their own lecture notes, slides, and course documents. They need to discover weak concepts, practise recall, and receive evidence-linked feedback without the system inventing material outside their uploads.

## Product Purpose

ViaX turns a student's course material into a grounded concept map, adaptive revision queue, and oral-exam practice loop. Success means a student can upload real material, receive questions supported by that material, understand why an answer was weak, and return to the exact cited passage.

## Positioning

ViaX assesses rather than merely chats: questions, evaluations, gaps, and revision decisions are tied to retrieved passages and an explicit prerequisite graph. A citation is a stored relationship to an uploaded chunk, not model-written prose.

## Operating Context

Students use the Flutter app on a phone while preparing for an upcoming viva. They create subjects, upload PDF, PowerPoint, Word, Markdown, text, or CSV files, wait for extraction and concept mapping, study grounded cards, and run typed or spoken viva sessions. Supabase provides authentication, private storage, database policies, and Edge Functions; FastAPI contains the separately tested ingestion and examiner domain services.

## Capabilities and Constraints

- Uploaded files are private and limited to 25 MB.
- Supported study sources are PDF, PPTX, DOCX, Markdown, plain text, and CSV. Scanned PDFs without a text layer are rejected with recovery guidance; OCR remains an open product decision.
- Questions and evaluation require a configured server-side model provider and sufficient grounded material.
- A subject needs at least five extracted concepts before ViaX will begin a viva.
- Model output is treated as untrusted structured data; retrieval and citation ownership are enforced by database rules.
- Free model capacity can be rate-limited, so provider failures must be explicit and recoverable rather than replaced with synthetic content.

## Brand Commitments

The canonical product name is ViaX. The voice is direct, calm, academically credible, and honest about uncertainty or missing material. The app remains subject-agnostic: visual examples must never imply that ViaX belongs to one academic discipline.

## Evidence on Hand

- Product and architecture source documents live under `docs/`.
- The database schema, RLS tests, ingestion pipeline, examiner functions, and Flutter client are implemented in this repository.
- There are no approved testimonials, customer logos, benchmark claims, or production sample datasets. Future work must not fabricate them.

## Product Principles

1. Show only real student data; label any demonstration material as synthetic.
2. Ground every learning claim in the student's uploaded source.
3. Make slow or failed processing understandable and recoverable.
4. Prefer accurate refusal over a plausible ungrounded answer.
5. Keep the next useful study action obvious without gamifying anxiety.

## Accessibility & Inclusion

Typing remains available whenever voice input is offered. Statuses use words as well as colour, controls target comfortable touch sizes, and the interface must remain usable with text scaling, dark mode, and reduced motion.
