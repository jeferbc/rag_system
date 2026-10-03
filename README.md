# Calma Assistant

An open-source AI assistant engine for health clinics, starting with therapy practices. It answers patient questions from the clinic's own content using retrieval-augmented generation (RAG), and will call live tools for anything that changes minute to minute.

This repository is the engine. It ships with a fictional clinic, "Calma Therapy Center", as demo and test data, written in Spanish because that is the language patients write in. Real clinics configure their own content and credentials privately; none of that belongs in this repo.

> **Status:** early. The knowledge-base ingestion pipeline works; the chat UI, agent and tool calling are next (see the roadmap).

## How it works

Two kinds of information, handled differently:

- **Static content → RAG.** Psychologist bios, therapeutic approach, FAQs and policies are split into chunks, embedded and stored in Postgres with pgvector.
- **Live data → tools at runtime.** Availability and prices are fetched through MCP tools when a patient asks (later phase). They are never embedded.

```
Upload form ──► Document ──► IngestDocumentJob ──► Chunk (embedding) ──► Chunk.search("…")
(PDF, TXT, MD)                chunk + embed
```

Documents are uploaded at `/admin/documents`, several files at a time. Uploading a file with the same name as an earlier upload replaces it. Syncing content from external sources (Google Drive, Notion) is planned for a later iteration.

## Stack

- Ruby 3.4, Rails 8.1, PostgreSQL 17 with [pgvector](https://github.com/pgvector/pgvector)
- [RubyLLM](https://rubyllm.com) 2.x for LLM calls and embeddings (`gemini-embedding-2` by default, switchable)
- [neighbor](https://github.com/ankane/neighbor) for nearest-neighbor search (HNSW, cosine)
- Solid Queue for background and recurring jobs (no Redis)
- Hotwire and Tailwind CSS for the upcoming web channel
- RSpec, FactoryBot and WebMock; the test suite makes no network calls

## Local setup

Requirements: Ruby 3.4.2, Docker.

```bash
bundle install
docker compose up -d            # Postgres + pgvector on localhost:5433
cp .env.example .env            # then set GEMINI_API_KEY
bin/rails db:prepare            # creates the databases and seeds the fictional clinic
bin/rails ruby_llm:load_models  # loads RubyLLM's bundled model registry (offline)
bin/rails documents:ingest      # chunks and embeds the seeded documents (calls the embeddings API)
```

Seeding needs no API key. Only `documents:ingest` and searching call the embeddings API.

### Embeddings provider

Embeddings use Google's `gemini-embedding-2` through RubyLLM. Get a key at [Google AI Studio](https://aistudio.google.com/apikey) and put it in `.env` as `GEMINI_API_KEY`. The Gemini API is billed separately from a Gemini app subscription; it has a free tier, but on the free tier Google states that content may be used to improve its products, so use the paid tier for any real clinic content.

To use another provider, set `EMBEDDING_MODEL` to any RubyLLM embedding model that can output 1,536 dimensions (for example `text-embedding-3-small` with `OPENAI_API_KEY`). Vectors from different models are not comparable, so re-embed everything afterwards with `bin/rails documents:ingest ALL=1`.

Try a search:

```bash
bin/rails runner '
  Chunk.search("psicóloga para la ansiedad que atienda en inglés", limit: 3).each do |chunk|
    puts "#{chunk.neighbor_distance.round(3)}  #{chunk.document.title}"
    puts "       #{chunk.content.truncate(120)}"
  end
'
```

Start the app with `bin/dev` and open <http://localhost:3000/admin/documents> to upload your own documents (PDF, TXT or Markdown). Each upload is chunked and embedded in the background.

The admin area uses HTTP Basic auth: set `ADMIN_PASSWORD` (and optionally `ADMIN_USER`, default `admin`). With no password set it is open in development and locked in every other environment.

Run the tests with `bundle exec rspec`, or everything CI runs with `bin/ci`.

If port 5433 is taken, set `DB_PORT` in `.env` (and in your shell for `docker compose up -d`).

## Keeping real data out of the repo

This repository is public. Seeds, fixtures and test data are synthetic. Do not commit real clinic content, names or credentials. `.env` and `config/*.key` are gitignored; real deployments supply secrets through Rails credentials or environment variables managed outside the repo.

## Roadmap

1. **RAG** — ingestion pipeline and retrieval over the clinic's static content *(in progress)*
2. **Evals** — a question set with expected sources, to tune chunking and retrieval with numbers
3. **Tool calling / agent** — live availability and prices through MCP tools
4. **Guardrails and human handoff** — scope limits, crisis handling, escalation to staff
5. **Channels** — web chat first, then WhatsApp
6. **Observability** — tracing, cost and quality monitoring
