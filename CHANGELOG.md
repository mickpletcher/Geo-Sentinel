# Changelog

Entries are appended automatically after each commit by `.githooks/post-commit`.
The hook then amends the same commit so `CHANGELOG.md` does not remain modified.

To activate the hook after cloning:

```sh
git config core.hooksPath .githooks
```

Each entry follows the format: `YYYY-MM-DD` commit message.

---

## 2026-05-15

- **Fixed broken OFAC data source** — `consolidated.csv` returns HTTP 404. Switched to `add.csv` (SDN address list) at the same Treasury domain. The new file requires a browser User-Agent header to follow the redirect; added `UserAgent` to `Invoke-WebRequest`.

- **Rewrote CSV parser** — `add.csv` has no header row and a different column layout than the old consolidated list. Replaced `ConvertFrom-Csv` header-detection with a regex that extracts the country field directly from each line.

- **Updated IsoMap for new country name conventions** — "North Korea" renamed to "Korea, North"; "Democratic Republic of the Congo" renamed to "Congo, Democratic Republic of the"; ambiguous "Congo" entry replaced with "Congo, Republic of the" (ISO CG). Removed "Transnistria" (no longer present in source data).

- **Fixed PowerShell 5.1 empty-array handling** — `Where-Object` on an empty collection returns `$null` in PS 5.1, not an empty array. Wrapped both diff assignments in `@()`. Added `[AllowEmptyCollection()]` to all `Mandatory` array parameters in `Show-ChangeReport` to prevent binding errors on first run.

- **Added retry logic to OFAC download** — 3 attempts with exponential backoff (5s, 10s, 20s). Download and parse failures are handled separately so retries only fire on network errors.

- **Added webhook notification support** — New `-WebhookUrl` parameter. POSTs a JSON change summary when additions or removals are detected. Failures are logged as warnings and do not abort the run.

- **Always show unmapped country warnings** — Console warning for unmapped countries now appears regardless of whether `-ExportIsoCodes` is specified. Previously only shown during ISO export.

- **Added corrupt baseline recovery** — `Get-Baseline` now catches malformed or truncated JSON, logs a warning, and falls back to an empty baseline instead of throwing.

- **Fixed `$BaselinePath` default to use `$PSScriptRoot`** — Changed default from `'.\OFACCountryBaseline.json'` (relative to working directory) to `Join-Path $PSScriptRoot 'OFACCountryBaseline.json'` so all output files anchor to the script's own directory when run without parameters.

- **Expanded README** — Added full usage examples, parameter table, first-run behavior, scheduling instructions, ISO map extension guide, output file descriptions, webhook payload format, and troubleshooting section.

- **Added `New-OFACScheduledTask.ps1`** — Companion script that registers a Windows Scheduled Task to run the monitor on a daily schedule. Accepts all relevant parameters and passes them through to the main script.

- **Added sample output files** — `samples/OFACCountryBaseline.json` and `samples/OFACGeofenceIsoCodes.txt` show the expected format for both output files.

- **Added auto-changelog git hook** — `.githooks/post-commit` appends an entry to this file after every commit. Activate with `git config core.hooksPath .githooks`.

- **Cleaned up `.gitignore`** — Removed formatting garbage from initial commit. Added `future-upgrades.md` to exclusion list.

- **Added `github-social-preview.jpg`** — 1280x640 social preview image for the GitHub repository page.

- **`-ExportIsoCodes` enabled by default** — ISO code export now runs on every execution without requiring the switch. Output file is `OFACGeofenceIsoCodes.csv`.

- **Changed ISO output format to CSV** — Output file is now `OFACGeofenceIsoCodes.csv` with a `country_code,country_name` header row. Each row is sorted by ISO code.

- **Normalized country display names** — OFAC uses inverted naming conventions ("Congo, Republic of the", "Korea, North"). The CSV now renders these in natural English order ("Republic of the Congo", "North Korea"). IsoMap keys are unchanged for matching purposes.

- **Added `-ExportIsoCodeList` switch** — Writes `OFACGeofenceIsoCodes.txt` with one ISO code per line. For use with ipverse/country-ip-blocks or tools that expect a bare code list. Independent of `-ExportIsoCodes`; both can be used together.

- **Added `completed-upgrades.md`** — Tracks upgrades moved out of `future-upgrades.md` once implemented. Includes date, tier, and description for each completed item. Linked from README.

- **Expanded README** — Added full usage examples, parameter table, output file descriptions, first-run behavior, scheduling instructions, webhook payload format, ISO map extension guide, and link to `completed-upgrades.md`.

- **Hardened baseline JSON validation** — `Get-Baseline` now validates structure after parsing: checks for null result, missing `Countries` property, and unexpected property type. Each case logs a distinct warning and falls back to an empty baseline.

- **Added `-SkipIfNoChanges` switch** — When set and the diff is empty, exits after a single log entry with no console output. Designed for scheduled task use where silent runs are expected.

- **Added unmapped countries file** — Writes `OFACUnmappedCountries.txt` when any country names can't be resolved to an ISO code. Automatically deleted on clean runs so file presence alone signals action is needed.

- **2026-05-15** `0ebc4fa` Add OFAC country monitoring improvements and project scaffolding - Rewrote OFAC data source: switched from consolidated.csv (404) to   add.csv with browser User-Agent and regex parser - Added retry logic (3 attempts, exponential backoff) - Added webhook notification support (-WebhookUrl) - Fixed PS 5.1 empty-array handling in diff and Show-ChangeReport - Fixed $BaselinePath and $OutputPath defaults to use $PSScriptRoot - Added corrupt and structurally invalid baseline recovery - Added -ExportIsoCodes (default on), CSV format with country_code,country_name - Added -ExportIsoCodeList for plain-text code-only output - Added -SkipIfNoChanges for silent scheduled task runs - Added OFACUnmappedCountries.txt written when unresolvable countries exist - Normalized OFAC inverted country names (Congo, Republic of the -> Republic of the Congo) - Updated IsoMap for current OFAC naming conventions - Added New-OFACScheduledTask.ps1 companion script - Added CHANGELOG.md with auto-update git hook (.githooks/post-commit) - Added completed-upgrades.md tracking implemented backlog items - Expanded README with full parameter table, output file descriptions,   usage examples, scheduling, webhook payload format, and ISO map guide - Added github-social-preview.jpg (1280x640) - Added sample output files under samples/

- **2026-05-15** `a1c8194` updated

- **2026-05-15** `e249cab` update2

- **2026-05-15** `722edca` Update changelog and worktree reference

- **2026-05-15** `60e6db5` Record latest changelog entry

- **2026-05-15** `077a6a7` json file push

- **2026-05-15** `c101c2b` updated gitignore file

- **2026-05-15** `1f0faf0` updated changelog

## 2026-05-20

- **Made curated strict profile the default strict behavior** - `python scripts/build_geofence_policy.py --strict` now automatically uses curated validation scope. Use `--strict-profile all` when you need strict validation across every discovered source file.

- **Added strict profile switch for policy builds** - Added `--strict-profile` to `scripts/build_geofence_policy.py` with `all` and `curated` modes. Use `--strict --strict-profile curated` to validate only `countries.txt` and `cidrs.txt` inputs and avoid failures from noisy downloaded feed files.

- **Hardened policy builder parsing for external source noise** - Updated CSV and text token handling in `scripts/build_geofence_policy.py` to ignore unsupported token types and convert malformed country or CIDR entries into warnings instead of crashing with a traceback.

- **Fixed Python script default path resolution** - Updated `scripts/build_geofence_policy.py` and `scripts/ingest/download_policy_sources.py` to use repo root based default paths so commands work from inside `scripts/` and not only from the repository root.

- **Cleaned stale generated artifacts from repo root** - Removed untracked runtime files `OFACCountryBaseline.json`, `OFACGeofenceIsoCodes.csv`, `OFACUnmappedCountries.txt`, `Get-OFACCountryChanges.log`, and regenerated `Outputs/` folder to keep the working tree clean.

- **Added repository assessment baseline** - Created `assessment.md` with current state scorecard, architecture snapshot, risk findings, and a required checklist for keeping the assessment updated when behavior or risk changes.

- **Added a 60 second startup path to README** - Added a 3 command startup section for first run success and a simple file check list so new users can verify output quickly.

- **Expanded README with beginner quick path and FAQ** - Added a one command quick start at the top and a larger beginner FAQ that covers missing Python, missing outputs, dry run usage, main workflow guidance, and PiHole export command.

- **Rewrote README for novice onboarding** - Added a copy and paste quick start, prerequisites check, beginner friendly workflow steps, common commands, troubleshooting, and updated legacy PowerShell examples including PiHole export.

- **Added Pi-hole export format to legacy PowerShell workflow** - Added `PiHole` format support to `Export-GeofenceRules.ps1` and `Export-GeofenceArtifacts`, including a generated regex blocklist output at `Outputs/pihole-regex-blocklist.txt`.

- **Added policy based repository architecture** — Introduced `data/`, `scripts/`, `outputs/`, and `docs/` policy workflow folders with category subfolders and placeholder `README.md` files to document purpose and usage.

- **Added policy category configuration** — Added `config/policies.yaml` and `config/policies.json` defining: `sanctions`, `high_risk`, `vpn_tor`, `hosting_providers`, `fraud_regions`, and `custom_business_rules`.

- **Added geofence policy builder** — Added `scripts/build_geofence_policy.py` to parse category inputs, normalize ISO country codes and CIDRs, deduplicate entries, validate data, assign policy categories, and generate consolidated outputs:
	- `outputs/geofence-policy.json`
	- `outputs/geofence-policy.csv`
	- `outputs/unifi/firewall-groups.txt`
	- `outputs/pihole/regex-blocklist.txt`
	- `outputs/cloudflare/waf-rules.txt`
	- `outputs/nginx/geoip-map.conf`
	- `outputs/iptables/ipset-rules.sh`

- **Removed install requirement for default workflow** — Updated builder to default to `config/policies.json` and run directly from repo without requiring package installation. YAML config is still supported via `--config`.

- **Added repo local source downloader** — Added `scripts/ingest/download_policy_sources.py` and `config/policy-sources.json` to refresh source lists directly into `data/*` folders from curated remote sources.

- **Added sample data for immediate testing** — Added starter country and CIDR files across all policy categories so build and validation runs work out of the box.

- **Updated documentation** — Expanded root `README.md`, added `docs/policy-model.md`, `docs/sources.md`, and folder level READMEs to document model, sources, and execution flow.

- **Removed legacy generated artifacts from old OFAC flow** — Deleted stale output files no longer needed for the new policy workflow:
	- `OFACCountryBaseline.json`
	- `OFACGeofenceIsoCodes.csv`
	- `OFACGeofenceIsoCodes.txt`
	- `OFACUnmappedCountries.txt`
	- `Outputs/` directory (legacy generated output folder)

- **Refreshed README to current repo state** — Replaced stale architecture and output references with the current policy builder first workflow, current folder layout, generated `outputs` behavior, and explicit legacy script section.

- **2026-05-20** `efb9342` feat: add policy model workflow with repo local data refresh

- **2026-05-20** `1da7446` changelog update

- **2026-05-20** `fb63b19` changelog update

- **2026-05-20** `f68654a` feat: add policy model workflow with repo local data refresh

- **2026-05-20** `8ac0d07` chore: sync changelog after policy workflow commit

- **2026-05-20** `8444ea4` fix: keep changelog clean after commits

- **2026-05-20** fix: stabilize changelog hook entry format

- **2026-05-20** docs: refresh README to match current policy workflow
