# Geo Sentinel

Geo Sentinel builds policy driven geofence outputs from sanctions, risk, network, and business rule datasets.

The repository currently supports two workflows:

1. Policy builder workflow using Python scripts and data category folders.
2. Legacy PowerShell workflow for evaluation and OFAC monitoring.

## Current Repository Layout

```text
Geo-Sentinel
├── config
│   ├── geofence.settings.json
│   ├── policies.json
│   ├── policies.yaml
│   └── policy-sources.json
├── data
│   ├── sanctions
│   ├── high_risk
│   ├── vpn_tor
│   ├── hosting_providers
│   ├── fraud_regions
│   └── custom_business_rules
├── docs
│   ├── policy-model.md
│   └── sources.md
├── scripts
│   ├── build_geofence_policy.py
│   ├── ingest
│   │   └── download_policy_sources.py
│   ├── normalize
│   └── export
├── Modules
├── tests
├── Get-OFAC-Country-Changes.ps1
├── Invoke-GeofenceEvaluation.ps1
└── Export-GeofenceRules.ps1
```

Note:

1. The `outputs` folder is generated when the builder runs.
2. Legacy generated OFAC output files were removed from the repository.

## Policy Builder Workflow

No system install step is required. Run directly from repository root with Python 3.

Refresh source files into category folders:

```powershell
python scripts/ingest/download_policy_sources.py
python scripts/ingest/download_policy_sources.py --dry-run
```

Build outputs:

```powershell
python scripts/build_geofence_policy.py
python scripts/build_geofence_policy.py --dry-run
python scripts/build_geofence_policy.py --strict
python scripts/build_geofence_policy.py --config config/policies.json --data-root data --output-root outputs
```

Default config:

1. `config/policies.json` is the default and needs no extra packages.
2. `config/policies.yaml` is still supported via `--config`.

Policy categories:

1. `data/sanctions`
2. `data/high_risk`
3. `data/vpn_tor`
4. `data/hosting_providers`
5. `data/fraud_regions`
6. `data/custom_business_rules`

Generated files:

1. `outputs/geofence-policy.json`
2. `outputs/geofence-policy.csv`
3. `outputs/unifi/firewall-groups.txt`
4. `outputs/pihole/regex-blocklist.txt`
5. `outputs/cloudflare/waf-rules.txt`
6. `outputs/nginx/geoip-map.conf`
7. `outputs/iptables/ipset-rules.sh`

## Legacy PowerShell Workflow

Legacy scripts remain available:

1. `Get-OFAC-Country-Changes.ps1`
2. `Invoke-GeofenceEvaluation.ps1`
3. `Export-GeofenceRules.ps1`

Example commands:

```powershell
pwsh .\Get-OFAC-Country-Changes.ps1
pwsh .\Invoke-GeofenceEvaluation.ps1 -IPAddress 198.51.100.10 -AsJson
pwsh .\Export-GeofenceRules.ps1
```

## Documentation

1. Policy model: `docs/policy-model.md`
2. Source expectations: `docs/sources.md`
3. Completed upgrade notes: `completed-upgrades.md`

## Testing

Run Pester tests:

```powershell
Invoke-Pester .\tests\Geo.Sentinel.Tests.ps1 -Output Detailed
```

## Compliance Disclaimer

This project helps automate geofencing and sanctions screening logic but does not replace legal or compliance review.
