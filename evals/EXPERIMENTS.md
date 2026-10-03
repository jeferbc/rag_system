# Retrieval experiments

A log of changes tried against `bin/rails evals:retrieval`, kept so nobody
repeats an experiment or wonders why a setting is what it is. Add an entry
whenever you test a change to chunking, the embedding input or the model,
whether or not it wins.

With 53 questions, one question is worth about 0.019 of hit@1. Treat a
difference of one or two questions as noise, not as a result.

## 2026-10-03 · Baseline

`gemini-embedding-2`, 1,536 dimensions, chunks ≤ 800 characters, embedding
input `title: … | text: …`, 53 scored questions, K=3.

| hit@1 | hit@3 | MRR |
|---|---|---|
| 0.925 | 1.000 | 0.962 |

Notes:
- Every expected document is in the top 3. The four that are not first are
  outranked by a document that is also a reasonable answer (for example the
  crisis FAQ for a panic-attack question).
- Distances cannot separate "answer found" from "no answer": expected
  documents sit at 0.190 to 0.426, while the nearest document for
  unanswerable questions sits at 0.256 to 0.452. The answer service has to
  judge from the content, not from a distance cutoff.

## 2026-10-03 · Chunks ≤ 400 characters (rejected)

Same setup with `Chunker::MAX_CHARS = 400` (75 chunks instead of 32).

| hit@1 | hit@3 | MRR |
|---|---|---|
| 0.906 (-0.019) | 1.000 (=) | 0.950 (-0.012) |

One question worse overall: psychologist questions lost three first places,
policy and multi-document questions gained two. Smaller chunks split a
psychologist's specialties from their name and approach. Within noise and no
improvement, so 800 stays.
