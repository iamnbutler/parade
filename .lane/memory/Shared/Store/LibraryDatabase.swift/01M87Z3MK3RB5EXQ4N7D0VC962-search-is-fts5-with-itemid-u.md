---
id: 01M87Z3MK3RB5EXQ4N7D0VC962
anchor: upsert
created: 2026-11-24T23:43:56Z
norm: '1'
---

search is FTS5 with itemID UNINDEXED: never DELETE FROM search WHERE itemID (full index scan per fic, quadratic at first index). Rows are keyed by searchRow.rowid (migration v2-search-rowids).
