# Geo-Sentinel

Geo-Sentinel now supports two related workflows:

1. The original OFAC country change monitor in `Get-OFAC-Country-Changes.ps1`
2. A provider based compliance and threat intelligence engine for geofencing decisions and rule exports

The new engine merges sanctions, geolocation, and threat intelligence sources into one normalized decision pipeline.

This project helps automate geofencing and sanctions screening logic but does not replace legal or compliance review.

## Project Purpose

Use this repository when you need to:

1. Detect country level changes in OFAC source data and maintain ISO export files.
2. Evaluate an IP address against sanctions, region restrictions, ASN policy, and threat indicators.
3. Export normalized geofencing outputs for downstream systems such as firewalls, Cloudflare, and nginx.

## Architecture

```text
Geo-Sentinel
├── Get-OFAC-Country-Changes.ps1
├── Invoke-GeofenceEvaluation.ps1
├── Export-GeofenceRules.ps1
├── Modules
│   └── Geo.Sentinel
│       └── Geo.Sentinel.psm1
├── config
│   └── geofence.settings.json
├── tests
│   ├── Geo.Sentinel.Tests.ps1
│   └── data
│       ├── sanctions
│       ├── geolocation
│       ├── threat
│       └── asn
└── Outputs
```

Decision pipeline:

```text
IP input
  -> geolocation lookup
  -> ASN lookup
  -> sanctions rule match
  -> threat intel match
  -> config policy overlay
  -> Allow | Deny | Review
```

## Supported Providers

### Sanctions

1. OFAC
2. EU
3. UK
4. Custom local rules
5. High risk country rules

### Geolocation

1. MaxMind GeoLite2 style mocked CSV
2. IP2Location LITE style mocked CSV
3. DB IP style mocked CSV
4. ipdeny country CIDR lists

### Threat Intelligence

1. Tor exit node list
2. VPN detection stub
3. Proxy detection stub
4. Datacenter or hosting ASN detection
5. ASN lookup using iptoasn style data

The repository ships only safe mocked data. Licensed databases and secrets are intentionally excluded.

## Configuration

Primary settings file:

`config/geofence.settings.json`

It supports:

1. Enabled providers
2. Cache paths
3. Refresh intervals
4. Output formats and output paths
5. Country allowlist and denylist
6. Region denylist
7. ASN denylist
8. Tor, VPN, proxy, and datacenter blocking
9. Review instead of deny mode
10. Strict compliance mode
11. Provider precedence

Example snippet:

```json
{
  "TorBlocking": true,
  "StrictComplianceMode": true,
  "ProviderPrecedence": {
    "Geolocation": ["MaxMind", "IP2Location", "DBIP", "ipdeny"]
  },
  "CountryDenylist": [],
  "Providers": [
    {
      "Name": "OFAC",
      "ProviderType": "Sanctions",
      "Enabled": true,
      "LocalCachePath": "../tests/data/sanctions/ofac.json"
    }
  ]
}
```

## Usage

### Build policy outputs

The repository now includes a policy based data model and output builder:

`scripts/build_geofence_policy.py`

No system install step is required. Run scripts directly from the repository with Python 3.

Optional source refresh script:

`scripts/ingest/download_policy_sources.py`

Download or refresh source files into `data/*` folders:

```powershell
python scripts/ingest/download_policy_sources.py
python scripts/ingest/download_policy_sources.py --dry-run
```

Run from repository root:

```powershell
python scripts/build_geofence_policy.py
```

Optional arguments:

```powershell
python scripts/build_geofence_policy.py --config config/policies.json --data-root data --output-root outputs
python scripts/build_geofence_policy.py --dry-run
python scripts/build_geofence_policy.py --strict
```

The default config is `config/policies.json` and requires no extra packages.
You can still use `config/policies.yaml` with `--config`.

Generated policy outputs:

1. `outputs/geofence-policy.json`
2. `outputs/geofence-policy.csv`
3. `outputs/unifi/firewall-groups.txt`
4. `outputs/pihole/regex-blocklist.txt`
5. `outputs/cloudflare/waf-rules.txt`
6. `outputs/nginx/geoip-map.conf`
7. `outputs/iptables/ipset-rules.sh`

Policy input categories:

1. `data/sanctions`
2. `data/high_risk`
3. `data/vpn_tor`
4. `data/hosting_providers`
5. `data/fraud_regions`
6. `data/custom_business_rules`

### Evaluate an IP address

```powershell
pwsh .\Invoke-GeofenceEvaluation.ps1 -IPAddress 198.51.100.10
```

JSON output:

```powershell
pwsh .\Invoke-GeofenceEvaluation.ps1 -IPAddress 198.51.100.10 -AsJson
```

Override country, ASN, or region when upstream data is already known:

```powershell
pwsh .\Invoke-GeofenceEvaluation.ps1 -IPAddress 203.0.113.10 -CountryCode UA -Region Crimea
```

### Export rules

Export all configured outputs:

```powershell
pwsh .\Export-GeofenceRules.ps1
```

Export only firewall CIDR data:

```powershell
pwsh .\Export-GeofenceRules.ps1 -Format FirewallRules -PassThru
```

Generated output files default to `Outputs\` and include:

1. `geofence-rules.json`
2. `geofence-rules.clixml`
3. `geofence.map.conf`
4. `cloudflare-country-rules.json`
5. `firewall-cidr-blocklist.txt`

### Legacy OFAC country change monitoring

The original script remains intact.

```powershell
.\Get-OFAC-Country-Changes.ps1
```

Useful options:

```powershell
.\Get-OFAC-Country-Changes.ps1 -OutputPath C:\Geofence
.\Get-OFAC-Country-Changes.ps1 -ExportIsoCodeList
.\Get-OFAC-Country-Changes.ps1 -SkipIfNoChanges
.\Get-OFAC-Country-Changes.ps1 -WebhookUrl 'https://hooks.slack.com/services/...'
.\Get-OFAC-Country-Changes.ps1 -WhatIf
```

Legacy output files:

1. `OFACCountryBaseline.json`
2. `OFACGeofenceIsoCodes.csv`
3. `OFACGeofenceIsoCodes.txt`
4. `OFACUnmappedCountries.txt`
5. `Get-OFACCountryChanges.log`

## Decision Output

The decision engine returns:

1. `Allow`, `Deny`, or `Review`
2. Reason codes
3. Matched rules
4. Source providers
5. Confidence score

Example result:

```json
{
  "IPAddress": "198.51.100.10",
  "CountryCode": "CU",
  "Region": "Havana",
  "ASN": "64510",
  "Decision": "Deny",
  "ReasonCodes": ["OFAC_COUNTRY_MATCH"],
  "SourceProviders": ["OFAC", "MaxMind", "ASNLookup"],
  "ConfidenceScore": 80
}
```

Example reason codes:

1. `OFAC_COUNTRY_MATCH`
2. `OFAC_REGION_MATCH`
3. `EU_SANCTIONS_MATCH`
4. `UK_SANCTIONS_MATCH`
5. `TOR_EXIT_NODE`
6. `VPN_DETECTED`
7. `PROXY_DETECTED`
8. `DATACENTER_ASN`
9. `HIGH_RISK_COUNTRY`
10. `CUSTOM_RULE_MATCH`

## Output Generators

### JSON

Exports normalized sanctions rules and core policy settings.

### PowerShell

Exports the full rule set as CLIXML for PowerShell native consumption.

### nginx map

Exports country based decisions as an nginx map file.

### Cloudflare rules

Exports a Cloudflare compatible country block expression.

### Firewall CIDR blocklist

Builds a CIDR list from deny country codes using `ipdeny` test data.

## Test Data

Test data lives under `tests/data`.

Included mocked samples:

1. OFAC style sanctions data
2. EU sanctions data
3. UK sanctions data
4. Custom rules
5. High risk country rules
6. MaxMind style country lookup data
7. IP2Location style country lookup data
8. DB IP style country lookup data
9. ipdeny CIDR files
10. Tor exit node data
11. VPN and proxy stub data
12. Datacenter ASN stub data
13. ASN lookup data

## Local Development

Use PowerShell 7 for the provider engine and tests.

Run tests:

```powershell
Invoke-Pester .\tests\Geo.Sentinel.Tests.ps1 -Output Detailed
```

Re import the module during development:

```powershell
Import-Module .\Modules\Geo.Sentinel\Geo.Sentinel.psm1 -Force
```

## How To Add A New Provider

1. Add a provider entry to `config/geofence.settings.json`.
2. Add a matching case in `Get-GeofenceProviders` inside `Modules\Geo.Sentinel\Geo.Sentinel.psm1`.
3. Implement `Fetch`, `Parse`, `Validate`, and `Export` behavior.
4. Add deterministic sample data under `tests/data`.
5. Add or extend Pester coverage in `tests\Geo.Sentinel.Tests.ps1`.

## Compliance Disclaimer

This project helps automate geofencing and sanctions screening logic but does not replace legal or compliance review.

Use exported rules and decision results as operational inputs, not as a substitute for counsel, policy review, or regulator specific interpretation.

## Additional Notes

Completed upgrade history is tracked in `completed-upgrades.md`.
