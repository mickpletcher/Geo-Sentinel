# OFACGeoFence

Monitors the OFAC Consolidated Sanctions List for country-level changes and outputs ISO code lists for geofencing policy automation.

---

## Overview

Downloads the OFAC SDN address list, extracts unique sanctioned countries, maps them to ISO 3166-1 alpha-2 codes, compares against a stored baseline, and reports additions or removals. Designed to run on a schedule as part of an automated geofencing policy pipeline.

---

## Usage

```powershell
# Default run — compares against baseline, exports CSV, saves updated baseline
.\Get-OFAC-Country-Changes.ps1

# Specify an output directory
.\Get-OFAC-Country-Changes.ps1 -OutputPath C:\Geofence

# Also export a plain-text code list (one ISO code per line)
.\Get-OFAC-Country-Changes.ps1 -ExportIsoCodeList

# Suppress console output when nothing has changed (useful for scheduled tasks)
.\Get-OFAC-Country-Changes.ps1 -SkipIfNoChanges

# Send a webhook notification on detected changes
.\Get-OFAC-Country-Changes.ps1 -WebhookUrl 'https://hooks.slack.com/services/...'

# Preview changes without writing any files
.\Get-OFAC-Country-Changes.ps1 -WhatIf
```

---

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-BaselinePath` | String | `$PSScriptRoot\OFACCountryBaseline.json` | Path to the JSON baseline file |
| `-OutputPath` | String | `$PSScriptRoot` | Directory for all output files |
| `-ExportIsoCodes` | Switch | `$true` | Write `OFACGeofenceIsoCodes.csv` (country_code,country_name) |
| `-ExportIsoCodeList` | Switch | off | Write `OFACGeofenceIsoCodes.txt` (one ISO code per line) |
| `-SkipIfNoChanges` | Switch | off | Exit silently with a log entry when no additions or removals are detected |
| `-WebhookUrl` | String | none | POST a JSON change summary here when changes are detected |
| `-WhatIf` | Switch | off | Show what would happen without writing files |

---

## Output Files

| File | Description |
|------|-------------|
| `OFACCountryBaseline.json` | Stored country snapshot used for change comparison |
| `OFACGeofenceIsoCodes.csv` | ISO codes with country names (`country_code,country_name`) |
| `OFACGeofenceIsoCodes.txt` | ISO codes only, one per line (with `-ExportIsoCodeList`) |
| `OFACUnmappedCountries.txt` | Country names that couldn't be resolved to an ISO code; absent when all countries are mapped |
| `Get-OFACCountryChanges.log` | CMTrace-compatible run log |

---

## First Run

No baseline exists on first run. The script saves the current OFAC state as the baseline and reports no changes. Subsequent runs diff against that saved state.

---

## Scheduling

Use the companion script to register a daily Windows Scheduled Task:

```powershell
.\New-OFACScheduledTask.ps1 -OutputPath C:\Geofence -WebhookUrl 'https://...'
```

---

## Webhook Payload

When changes are detected and `-WebhookUrl` is set, the script POSTs:

```json
{
  "text": "OFAC Sanctions List Change Detected: 1 country/countries added, 0 removed.",
  "added": ["Burma"],
  "removed": [],
  "timestamp": "2026-05-15 08:00:00",
  "source": "https://www.treasury.gov/ofac/downloads/add.csv"
}
```

Compatible with Slack incoming webhooks, Microsoft Teams connectors, and custom HTTP endpoints.

---

## Extending the ISO Map

If a new country appears in OFAC data that isn't in the built-in `$IsoMap`, the script logs a warning and lists it under `UNMAPPED` in the console report. To add it, find the entry in `$IsoMap` in the script and add a line:

```powershell
'Country Name As OFAC Uses It' = 'XX'  # ISO 3166-1 alpha-2 code
```

---

## Completed Upgrades

See [completed-upgrades.md](completed-upgrades.md) for a log of improvements implemented from the upgrade backlog.

---

## Data Source

[OFAC SDN Address List](https://www.treasury.gov/ofac/downloads/add.csv) — U.S. Department of the Treasury
