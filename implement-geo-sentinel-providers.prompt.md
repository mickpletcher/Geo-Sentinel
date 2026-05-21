Implement the next version of this repository:

https://github.com/mickpletcher/Geo-Sentinel

Goal:
Turn the project from a static country geofence list into a provider based compliance and threat intelligence engine.

Implement the following architecture:

Geo-Sentinel
├── Providers
│   ├── MaxMind
│   ├── IP2Location
│   ├── DBIP
│   ├── IPInfo
│   └── ASNLookup
├── Rules
│   ├── OFAC
│   ├── EU
│   ├── UK
│   ├── Custom
│   └── HighRisk
├── ThreatIntel
│   ├── Tor
│   ├── VPN
│   ├── Proxy
│   └── Datacenter
├── Outputs
│   ├── FirewallRules
│   ├── CloudflareRules
│   ├── NginxMaps
│   ├── PowerShell
│   └── JSON

Requirements:

1. Create a clean provider interface

Create a shared provider abstraction that supports:

- Provider name
- Provider type
- Enabled flag
- Refresh interval
- Source URL
- Local cache path
- Last updated timestamp
- Fetch method
- Parse method
- Validate method
- Export method

2. Add sanctions rule providers

Create providers for:

- OFAC
- EU sanctions
- UK sanctions
- Custom local rules
- High risk country rules

Do not hardcode only one source. The system must allow multiple sanctions sources to be merged into one normalized ruleset.

3. Add IP geolocation providers

Add provider stubs and configuration for:

- MaxMind GeoLite2
- IP2Location LITE
- DB IP
- ipdeny country CIDR lists

The first implementation should support local cache files and mocked test data if API keys or licensed files are not present.

4. Add threat intelligence providers

Add support for:

- Tor exit node list
- VPN detection provider stub
- Proxy detection provider stub
- Datacenter or hosting provider detection
- ASN lookup using iptoasn style data

5. Create a normalized decision engine

Implement a decision pipeline:

Input:
- IP address
- Optional country code
- Optional ASN
- Optional region
- Optional provider metadata

Output:
- Allow
- Deny
- Review
- Reason codes
- Matched rules
- Source providers
- Confidence score

Example reason codes:

- OFAC_COUNTRY_MATCH
- OFAC_REGION_MATCH
- EU_SANCTIONS_MATCH
- UK_SANCTIONS_MATCH
- TOR_EXIT_NODE
- VPN_DETECTED
- PROXY_DETECTED
- DATACENTER_ASN
- HIGH_RISK_COUNTRY
- CUSTOM_RULE_MATCH

6. Add configuration

Create a config file such as:

config/geofence.settings.json

It should support:

- Enabled providers
- Cache paths
- Refresh intervals
- Output formats
- Country allowlist
- Country denylist
- Region denylist
- ASN denylist
- Tor blocking
- VPN blocking
- Proxy blocking
- Datacenter blocking
- Review instead of deny mode
- Strict compliance mode

7. Add output generators

Implement exporters for:

- JSON decision rules
- PowerShell objects
- nginx map files
- Cloudflare compatible country rules
- Firewall CIDR blocklists

8. Add test data

Create a test data folder:

tests/data

Include safe mocked sample files for:

- OFAC style sanctions data
- EU style sanctions data
- UK style sanctions data
- ipdeny CIDR data
- Tor exit node data
- ASN lookup data
- MaxMind style country lookup data

Do not include licensed MaxMind databases.

9. Add tests

Create unit tests for:

- Provider loading
- Provider parsing
- Sanctions merge logic
- Country match logic
- Region match logic
- Tor match logic
- ASN match logic
- Final decision output
- Export generation

10. Update documentation

Update README.md with:

- Project purpose
- Architecture diagram
- Supported providers
- Configuration examples
- Usage examples
- Compliance disclaimer
- Local development instructions
- How to add a new provider
- Example outputs

Add a clear disclaimer:

This project helps automate geofencing and sanctions screening logic but does not replace legal or compliance review.

11. Preserve existing functionality

Do not break the existing repository behavior. If the current project has scripts, outputs, or data files, keep them working. Add compatibility wrappers if needed.

12. Implementation priorities

Work in this order:

1. Inspect the current repository structure.
2. Identify the current language and runtime.
3. Add the provider abstraction.
4. Add config loading.
5. Add normalized rule models.
6. Add decision engine.
7. Add mocked provider implementations.
8. Add exporters.
9. Add tests.
10. Update README.md.

13. Quality requirements

- Keep code modular.
- Avoid hardcoded paths.
- Use clear naming.
- Add inline comments only where useful.
- Use deterministic test data.
- Fail safely.
- Log provider failures without crashing the full pipeline.
- Prefer deny or review when confidence is low in strict mode.
- Keep secrets and licensed databases out of the repo.

Final output:

After implementation, provide:

- Summary of changed files
- How to run tests
- Example command to evaluate an IP address
- Example command to export firewall rules
- Any assumptions made