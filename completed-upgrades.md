# Completed Upgrades

Items moved here from `future-upgrades.md` once implemented.
Each entry records the original tier, description, and date completed.
When moving an item here, add a replacement upgrade to `future-upgrades.md`.

---

| Date | Tier | Upgrade |
|------|------|---------|
| 2026-05-15 | Tier 1 | **Unmapped country warnings always shown** — Console warning for unmapped countries now appears on every run, not just when `-ExportIsoCodes` is set. |
| 2026-05-15 | Tier 1 | **Corrupt baseline recovery** — `Get-Baseline` catches malformed or truncated JSON and falls back to an empty baseline instead of throwing. |
| 2026-05-15 | Tier 2 | **Retry logic on download** — 3 attempts with exponential backoff (5s, 10s, 20s). Network failures retry independently of parse failures. |
| 2026-05-15 | Tier 2 | **Webhook notification support** — `-WebhookUrl` parameter POSTs a JSON change summary to Slack, Teams, or any custom HTTP endpoint when changes are detected. |
| 2026-05-15 | Tier 1 | **Validate baseline JSON structure on load** — `Get-Baseline` now checks for a null result, missing `Countries` property, and unexpected property type after parsing. Each case logs a warning and falls back to an empty baseline. |
| 2026-05-15 | Tier 1 | **Added `-SkipIfNoChanges` switch** — When set and the diff is empty, the script logs a single "no changes" entry and exits without producing any console output. Reduces noise in scheduled task logs during stable periods. |
| 2026-05-15 | Tier 1 | **Write unmapped countries to a dedicated file** — Writes `OFACUnmappedCountries.txt` when any country names couldn't be resolved to an ISO code. File is deleted automatically on runs where all countries are mapped, so its presence alone signals action is needed. |
