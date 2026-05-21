# Geo Sentinel

Geo Sentinel creates geofence policy outputs from country and network data.

If you are new to this repo, start with the Quick Start section.

## One Command Quick Start

If you want the fastest path, run this from the repository root:

```powershell
python scripts/build_geofence_policy.py
```

Then open these files to confirm success:

1. outputs/geofence-policy.json
2. outputs/geofence-policy.csv

## 60 Second Start

Run these 3 commands from the repository root.

```powershell
python --version
python scripts/ingest/download_policy_sources.py --dry-run
python scripts/build_geofence_policy.py
```

Then confirm these files exist:

1. outputs/geofence-policy.json
2. outputs/geofence-policy.csv
3. outputs/pihole/regex-blocklist.txt

## What This Project Does

Geo Sentinel combines data from several categories:

1. Sanctions
2. High risk regions
3. VPN and Tor signals
4. Hosting provider networks
5. Fraud focused regions
6. Custom business rules

Then it generates ready to use output files for common platforms.

## Quick Start For First Time Users

Use this if you want working output as fast as possible.

### Step 1: Install Prerequisites

1. Install Python 3.10 or newer.
2. Open a terminal in the repository root.
3. Confirm Python is available:

```powershell
python --version
```

### Step 2: Refresh Source Data (Optional but Recommended)

```powershell
python scripts/ingest/download_policy_sources.py
```

Preview what would download without changing files:

```powershell
python scripts/ingest/download_policy_sources.py --dry-run
```

### Step 3: Build Policy Outputs

```powershell
python scripts/build_geofence_policy.py
```

### Step 4: Check Generated Files

After a successful run, look in the outputs folder:

1. outputs/geofence-policy.json
2. outputs/geofence-policy.csv
3. outputs/unifi/firewall-groups.txt
4. outputs/pihole/regex-blocklist.txt
5. outputs/cloudflare/waf-rules.txt
6. outputs/nginx/geoip-map.conf
7. outputs/iptables/ipset-rules.sh

Note: The outputs folder is created during build if it does not already exist.

## Common Commands

Run with stricter validation:

```powershell
python scripts/build_geofence_policy.py --strict
```

Run a safe preview only:

```powershell
python scripts/build_geofence_policy.py --dry-run
```

Use explicit paths:

```powershell
python scripts/build_geofence_policy.py --config config/policies.json --data-root data --output-root outputs
```

## Configuration Basics

1. Default config is config/policies.json.
2. YAML config is also supported with config/policies.yaml.
3. Category folders are inside data.

Category folders:

1. data/sanctions
2. data/high_risk
3. data/vpn_tor
4. data/hosting_providers
5. data/fraud_regions
6. data/custom_business_rules

## Legacy PowerShell Workflow

The repo also includes older PowerShell scripts.

1. Get-OFAC-Country-Changes.ps1
2. Invoke-GeofenceEvaluation.ps1
3. Export-GeofenceRules.ps1

Examples:

```powershell
pwsh .\Get-OFAC-Country-Changes.ps1
pwsh .\Invoke-GeofenceEvaluation.ps1 -IPAddress 198.51.100.10 -AsJson
pwsh .\Export-GeofenceRules.ps1
pwsh .\Export-GeofenceRules.ps1 -Format PiHole
```

## Beginner FAQ

I ran the build command and got a command not found error.

1. Reinstall Python.
2. During install, select Add Python to PATH.
3. Close the terminal.
4. Open a new terminal.
5. Run python --version.

I ran the command but do not see an outputs folder.

1. Confirm you are in the repository root.
2. Run python scripts/build_geofence_policy.py again.
3. Check for errors in the terminal output.
4. Confirm data files exist under data.

How do I test without writing files.

1. Run python scripts/build_geofence_policy.py --dry-run.

What command should I run most of the time.

1. Start with python scripts/build_geofence_policy.py.
2. Use --strict when you want stronger validation.
3. Use --dry-run before big changes.

Do I need PowerShell for the main workflow.

1. No.
2. Python is the main policy builder workflow.
3. PowerShell scripts are for the legacy workflow.

How do I export Pi-hole format from legacy PowerShell.

1. Run pwsh .\Export-GeofenceRules.ps1 -Format PiHole.

## Testing

Run PowerShell tests:

```powershell
Invoke-Pester .\tests\Geo.Sentinel.Tests.ps1 -Output Detailed
```

## Project Layout

```text
Geo-Sentinel
|-- config
|   |-- geofence.settings.json
|   |-- policies.json
|   |-- policies.yaml
|   `-- policy-sources.json
|-- data
|   |-- sanctions
|   |-- high_risk
|   |-- vpn_tor
|   |-- hosting_providers
|   |-- fraud_regions
|   `-- custom_business_rules
|-- docs
|   |-- policy-model.md
|   `-- sources.md
|-- scripts
|   |-- build_geofence_policy.py
|   |-- ingest
|   |   `-- download_policy_sources.py
|   |-- normalize
|   `-- export
|-- Modules
|-- tests
|-- Get-OFAC-Country-Changes.ps1
|-- Invoke-GeofenceEvaluation.ps1
`-- Export-GeofenceRules.ps1
```

## Documentation

1. docs/policy-model.md
2. docs/sources.md
3. completed-upgrades.md

## Compliance Disclaimer

This project helps automate geofencing and sanctions screening logic. It does not replace legal or compliance review.
