# Calma Assistant

An open-source AI assistant engine for health clinics, starting with therapy practices. It answers patient questions from the clinic's own content using retrieval-augmented generation (RAG), and will call live tools for anything that changes minute to minute.

This repository is the engine. It ships with a fictional clinic, "Calma Therapy Center", as demo and test data. Real clinics configure their own content and credentials privately; none of that belongs in this repo.

> **Status:** early. The knowledge-base ingestion pipeline works; the chat UI, agent and tool calling are next (see the roadmap).

## How it works

Two kinds of information, handled differently:

- **Static content → RAG.** Psychologist bios, therapeutic approach, FAQs and policies are synced from a content source, split into chunks, embedded and stored in Postgres with pgvector.
- **Live data → tools at runtime.** Availability and prices are fetched through MCP tools when a patient asks (later phase). They are never embedded.

```
Content source ──► Sources::Sync ──► Document ──► IngestDocumentJob ──► Chunk (embedding)
(Google Drive,      create / update /              chunk + embed          │
 seeds, …)          skip / delete                                         ▼
                                                              Chunk.search("…")
```

- `Sources::GoogleDrive` walks a Drive folder with a read-only service account. Google Docs are exported as text, PDFs go through `pdf-reader`, other file types are skipped with a warning. Files inside a `psy-<id>-<slug>` folder are tagged with that folder name as `psychologist_ref`.
- `SyncDriveJob` runs hourly (`config/recurring.yml`). Files whose `modifiedTime` has not changed are skipped; documents whose file disappeared from the folder are deleted with their chunks.
- New sources (Notion, uploads, …) implement the three methods of `Sources::Base` and reuse `Sources::Sync`.

## Stack

- Ruby 3.4, Rails 8.1, PostgreSQL 17 with [pgvector](https://github.com/pgvector/pgvector)
- [RubyLLM](https://rubyllm.com) 2.x for LLM calls and embeddings (`text-embedding-3-small`)
- [neighbor](https://github.com/ankane/neighbor) for nearest-neighbor search (HNSW, cosine)
- Solid Queue for background and recurring jobs (no Redis)
- Hotwire and Tailwind CSS for the upcoming web channel
- RSpec, FactoryBot and WebMock; the test suite makes no network calls

## Local setup

Requirements: Ruby 3.4.2, Docker.

```bash
bundle install
docker compose up -d            # Postgres + pgvector on localhost:5433
cp .env.example .env            # then set OPENAI_API_KEY
bin/rails db:prepare            # creates the databases and seeds the fictional clinic
bin/rails ruby_llm:load_models  # loads RubyLLM's bundled model registry (offline)
bin/rails documents:ingest      # chunks and embeds the seeded documents (calls OpenAI)
```

Seeding needs no API key or Drive credentials. Only `documents:ingest` and searching call the embeddings API.

Try a search:

```bash
bin/rails runner '
  Chunk.search("psychologist for anxiety in English", limit: 3).each do |chunk|
    puts "#{chunk.neighbor_distance.round(3)}  #{chunk.document.title}"
    puts "       #{chunk.content.truncate(120)}"
  end
'
```

Start the app with `bin/dev`. Run the tests with `bundle exec rspec`, or everything CI runs with `bin/ci`.

If port 5433 is taken, set `DB_PORT` in `.env` (and in your shell for `docker compose up -d`).

### Syncing from Google Drive (optional)

1. Create a Google Cloud service account, enable the Drive API, and share the clinic's content folder with the service account's email as a **Viewer**. The app only requests the `drive.readonly` scope.
2. Put the service-account key in Rails credentials (`bin/rails credentials:edit`):

   ```yaml
   google_drive:
     service_account: |
       { "type": "service_account", "project_id": "…", "private_key": "…", "client_email": "…" }
   ```

3. Set the folder ID with `GOOGLE_DRIVE_FOLDER_ID` (or `google_drive.folder_id` in credentials).
4. Run a sync: `bin/rails runner 'SyncDriveJob.perform_now'`. In production it runs every hour.

Expected folder layout:

```
<clinic folder>/
├── FAQ - Booking                  (Google Doc, no psychologist_ref)
├── Cancellation Policy.pdf
├── psy-101-elena-marsh/           (psychologist_ref = "psy-101-elena-marsh")
│   └── Bio
└── psy-102-tomas-rivera/
    └── Bio
```

## Keeping real data out of the repo

This repository is public. Seeds, fixtures and test data are synthetic. Do not commit real clinic content, names, credentials or folder IDs. `.env` and `config/*.key` are gitignored; real deployments supply secrets through Rails credentials or environment variables managed outside the repo.

## Roadmap

1. **RAG** — ingestion pipeline and retrieval over the clinic's static content *(in progress)*
2. **Evals** — a question set with expected sources, to tune chunking and retrieval with numbers
3. **Tool calling / agent** — live availability and prices through MCP tools
4. **Guardrails and human handoff** — scope limits, crisis handling, escalation to staff
5. **Channels** — web chat first, then WhatsApp
6. **Observability** — tracing, cost and quality monitoring
