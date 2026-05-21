# Policy Model

The policy model organizes geofence controls into six categories.

## Categories

1. sanctions
   Country and CIDR indicators sourced from sanctions authorities.
2. high_risk
   Countries and CIDRs from high risk jurisdiction guidance.
3. vpn_tor
   TOR exit and VPN ranges for elevated risk handling.
4. hosting_providers
   Datacenter and cloud provider ranges used for stricter controls.
5. fraud_regions
   Regions and networks associated with fraud trend data.
6. custom_business_rules
   Organization specific countries and CIDRs.

## Entry Types

Each category can include:

1. Country entries normalized to ISO 3166 alpha 2.
2. CIDR entries normalized by IP network canonical format.

## Validation Rules

1. Invalid country values fail the build.
2. Invalid CIDR values fail the build.
3. Duplicate entries are removed and logged as warnings.
4. Empty categories are logged as warnings.
5. Strict mode fails on warnings.

## Build Outputs

The policy builder generates:

1. Combined JSON and CSV policy files.
2. Firewall friendly format exports for UniFi, Pi-hole, Cloudflare, nginx, and iptables.
