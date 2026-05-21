#!/usr/bin/env python3
"""Build a combined geofence policy dataset and firewall oriented exports."""

from __future__ import annotations

import argparse
import csv
import ipaddress
import json
import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None


REQUIRED_CATEGORIES = [
    "sanctions",
    "high_risk",
    "vpn_tor",
    "hosting_providers",
    "fraud_regions",
    "custom_business_rules",
]

ISO_ALPHA2_CODES = {
    "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX", "AZ",
    "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS",
    "BT", "BV", "BW", "BY", "BZ", "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN",
    "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ", "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE",
    "EG", "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FM", "FO", "FR", "GA", "GB", "GD", "GE", "GF",
    "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY", "HK", "HM",
    "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS", "IT", "JE", "JM",
    "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC",
    "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK",
    "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ", "NA",
    "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG",
    "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY", "QA", "RE", "RO", "RS", "RU", "RW",
    "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS",
    "ST", "SV", "SX", "SY", "SZ", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO",
    "TR", "TT", "TV", "TW", "TZ", "UA", "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI",
    "VN", "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW",
}

COUNTRY_ALIASES = {
    "AFGHANISTAN": "AF",
    "ALBANIA": "AL",
    "ALGERIA": "DZ",
    "ANGOLA": "AO",
    "ARMENIA": "AM",
    "AUSTRALIA": "AU",
    "AUSTRIA": "AT",
    "AZERBAIJAN": "AZ",
    "BANGLADESH": "BD",
    "BELARUS": "BY",
    "BELGIUM": "BE",
    "BOSNIA AND HERZEGOVINA": "BA",
    "BRAZIL": "BR",
    "BULGARIA": "BG",
    "CAMBODIA": "KH",
    "CANADA": "CA",
    "CHINA": "CN",
    "COLOMBIA": "CO",
    "CUBA": "CU",
    "CZECHIA": "CZ",
    "DEMOCRATIC REPUBLIC OF THE CONGO": "CD",
    "EGYPT": "EG",
    "ERITREA": "ER",
    "ETHIOPIA": "ET",
    "FRANCE": "FR",
    "GERMANY": "DE",
    "HAITI": "HT",
    "HONG KONG": "HK",
    "INDIA": "IN",
    "INDONESIA": "ID",
    "IRAN": "IR",
    "IRAN ISLAMIC REPUBLIC OF": "IR",
    "IRAQ": "IQ",
    "IRELAND": "IE",
    "ISRAEL": "IL",
    "ITALY": "IT",
    "JAPAN": "JP",
    "KAZAKHSTAN": "KZ",
    "KENYA": "KE",
    "KOREA NORTH": "KP",
    "KOREA DEMOCRATIC PEOPLES REPUBLIC OF": "KP",
    "KYRGYZSTAN": "KG",
    "LEBANON": "LB",
    "LIBYA": "LY",
    "MALI": "ML",
    "MOLDOVA": "MD",
    "MONTENEGRO": "ME",
    "MYANMAR": "MM",
    "NETHERLANDS": "NL",
    "NICARAGUA": "NI",
    "NIGERIA": "NG",
    "PAKISTAN": "PK",
    "PALESTINE": "PS",
    "PANAMA": "PA",
    "PHILIPPINES": "PH",
    "POLAND": "PL",
    "QATAR": "QA",
    "RUSSIA": "RU",
    "RUSSIAN FEDERATION": "RU",
    "SAUDI ARABIA": "SA",
    "SERBIA": "RS",
    "SINGAPORE": "SG",
    "SOMALIA": "SO",
    "SOUTH SUDAN": "SS",
    "SPAIN": "ES",
    "SUDAN": "SD",
    "SYRIA": "SY",
    "SYRIAN ARAB REPUBLIC": "SY",
    "TAIWAN": "TW",
    "TURKEY": "TR",
    "UKRAINE": "UA",
    "UNITED ARAB EMIRATES": "AE",
    "UNITED KINGDOM": "GB",
    "UNITED STATES": "US",
    "UNITED STATES OF AMERICA": "US",
    "VENEZUELA": "VE",
    "VIETNAM": "VN",
    "YEMEN": "YE",
    "ZIMBABWE": "ZW",
}


class PolicyBuildError(Exception):
    """Raised when policy validation fails."""


def setup_logging() -> logging.Logger:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    return logging.getLogger("geofence_policy_builder")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build geofence policy files from category datasets.")
    parser.add_argument("--config", default="config/policies.json", help="Path to policies YAML or JSON config.")
    parser.add_argument("--data-root", default="data", help="Root folder for category data.")
    parser.add_argument("--output-root", default="outputs", help="Root folder for generated files.")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as failures.")
    parser.add_argument("--dry-run", action="store_true", help="Parse and validate without writing files.")
    return parser.parse_args()


def parse_bool(value: str) -> bool | str:
    lowered = value.strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return value.strip()


def parse_simple_yaml_config(text: str) -> dict[str, Any]:
    """Parse a small subset of YAML used by config/policies.yaml."""
    config: dict[str, Any] = {"policy_categories": {}}
    current_category: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue

        if line.startswith("policy_categories:"):
            continue

        if line.startswith("  ") and line.strip().endswith(":") and not line.startswith("    "):
            current_category = line.strip()[:-1]
            config["policy_categories"][current_category] = {}
            continue

        if line.startswith("    ") and ":" in line and current_category:
            key, value = line.strip().split(":", 1)
            config["policy_categories"][current_category][key.strip()] = parse_bool(value)
            continue

        raise PolicyBuildError("Unsupported YAML format in config file. Use simple key/value mapping.")

    return config


def normalize_country_token(token: str) -> str:
    value = token.strip()
    if not value:
        raise ValueError("Empty country value")

    if re.fullmatch(r"[A-Za-z]{2}", value):
        code = value.upper()
    else:
        key = re.sub(r"[^A-Za-z0-9]+", " ", value).strip().upper()
        code = COUNTRY_ALIASES.get(key, "")

    if code not in ISO_ALPHA2_CODES:
        raise ValueError(f"Invalid country code or country value: {token}")

    return code


def normalize_cidr_token(token: str) -> str:
    value = token.strip()
    if not value:
        raise ValueError("Empty CIDR value")

    network = ipaddress.ip_network(value, strict=False)
    return str(network)


def split_tokens(text: str) -> list[str]:
    tokens: list[str] = []
    for part in re.split(r"[,;|\t]", text):
        cleaned = part.strip()
        if cleaned:
            tokens.append(cleaned)
    return tokens


def classify_token(token: str) -> str:
    return "cidr" if "/" in token else "country"


def parse_text_like_file(path: Path) -> tuple[list[str], list[str]]:
    countries: list[str] = []
    cidrs: list[str] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            for token in split_tokens(line):
                if classify_token(token) == "cidr":
                    cidrs.append(token)
                else:
                    countries.append(token)
    return countries, cidrs


def parse_csv_file(path: Path) -> tuple[list[str], list[str]]:
    countries: list[str] = []
    cidrs: list[str] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            return countries, cidrs

        for row in reader:
            for field_name, cell_value in row.items():
                if not cell_value:
                    continue
                for token in split_tokens(cell_value):
                    kind = classify_token(token)
                    if kind == "cidr":
                        cidrs.append(token)
                    else:
                        countries.append(token)
    return countries, cidrs


def extract_json_values(obj: Any, countries: list[str], cidrs: list[str]) -> None:
    if isinstance(obj, dict):
        for key, value in obj.items():
            lowered = key.lower()
            if lowered in {"countries", "country", "country_codes", "country_code"}:
                if isinstance(value, list):
                    countries.extend(str(item) for item in value)
                else:
                    countries.append(str(value))
                continue
            if lowered in {"cidrs", "cidr", "networks", "ranges", "ips"}:
                if isinstance(value, list):
                    cidrs.extend(str(item) for item in value)
                else:
                    cidrs.append(str(value))
                continue
            extract_json_values(value, countries, cidrs)
    elif isinstance(obj, list):
        for item in obj:
            extract_json_values(item, countries, cidrs)
    elif isinstance(obj, str):
        token = obj.strip()
        if not token:
            return
        if classify_token(token) == "cidr":
            cidrs.append(token)
        else:
            countries.append(token)


def parse_json_file(path: Path) -> tuple[list[str], list[str]]:
    countries: list[str] = []
    cidrs: list[str] = []
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    extract_json_values(data, countries, cidrs)
    return countries, cidrs


def read_raw_entries(category_path: Path) -> tuple[list[str], list[str]]:
    countries: list[str] = []
    cidrs: list[str] = []

    if not category_path.exists():
        return countries, cidrs

    for path in sorted(category_path.rglob("*")):
        if not path.is_file() or path.name.lower() == "readme.md":
            continue

        suffix = path.suffix.lower()
        if suffix in {".txt", ".list"}:
            parsed_countries, parsed_cidrs = parse_text_like_file(path)
        elif suffix == ".csv":
            parsed_countries, parsed_cidrs = parse_csv_file(path)
        elif suffix == ".json":
            parsed_countries, parsed_cidrs = parse_json_file(path)
        else:
            continue

        countries.extend(parsed_countries)
        cidrs.extend(parsed_cidrs)

    return countries, cidrs


def load_policy_config(config_path: Path) -> dict[str, Any]:
    if not config_path.exists():
        raise PolicyBuildError(f"Config file was not found: {config_path}")

    suffix = config_path.suffix.lower()
    if suffix == ".json":
        with config_path.open("r", encoding="utf-8") as handle:
            config = json.load(handle) or {}
    elif yaml is not None:
        with config_path.open("r", encoding="utf-8") as handle:
            config = yaml.safe_load(handle) or {}
    else:
        with config_path.open("r", encoding="utf-8") as handle:
            config = parse_simple_yaml_config(handle.read())

    categories = config.get("policy_categories", {})
    if not isinstance(categories, dict):
        raise PolicyBuildError("policy_categories must be a map in policies.yaml")

    missing = [name for name in REQUIRED_CATEGORIES if name not in categories]
    if missing:
        raise PolicyBuildError(
            "Missing required categories in config/policies.yaml: " + ", ".join(missing)
        )

    return config


def build_policy(
    config: dict[str, Any],
    data_root: Path,
    logger: logging.Logger,
) -> tuple[dict[str, dict[str, list[str]]], dict[str, int], list[str]]:
    categories_config = config["policy_categories"]
    category_data: dict[str, dict[str, list[str]]] = {}

    duplicate_count = 0
    warnings: list[str] = []

    for category in REQUIRED_CATEGORIES:
        settings = categories_config.get(category, {})
        if isinstance(settings, dict) and settings.get("enabled", True) is False:
            logger.info("Skipping disabled category: %s", category)
            continue

        raw_countries, raw_cidrs = read_raw_entries(data_root / category)
        normalized_countries: set[str] = set()
        normalized_cidrs: set[str] = set()

        for country in raw_countries:
            code = normalize_country_token(country)
            if code in normalized_countries:
                duplicate_count += 1
                continue
            normalized_countries.add(code)

        for cidr in raw_cidrs:
            normalized = normalize_cidr_token(cidr)
            if normalized in normalized_cidrs:
                duplicate_count += 1
                continue
            normalized_cidrs.add(normalized)

        category_data[category] = {
            "countries": sorted(normalized_countries),
            "cidrs": sorted(normalized_cidrs),
        }

        if not normalized_countries and not normalized_cidrs:
            warnings.append(f"Policy category '{category}' has no entries")

    summary = {
        "total_categories": len(category_data),
        "total_countries": sum(len(v["countries"]) for v in category_data.values()),
        "total_cidrs": sum(len(v["cidrs"]) for v in category_data.values()),
        "duplicates_removed": duplicate_count,
    }

    if duplicate_count > 0:
        warnings.append(f"Removed {duplicate_count} duplicate entries")

    return category_data, summary, warnings


def ensure_output_dirs(output_root: Path) -> None:
    required_dirs = [
        output_root,
        output_root / "unifi",
        output_root / "pihole",
        output_root / "cloudflare",
        output_root / "nginx",
        output_root / "iptables",
    ]
    for directory in required_dirs:
        directory.mkdir(parents=True, exist_ok=True)


def build_json_output(category_data: dict[str, dict[str, list[str]]], summary: dict[str, int]) -> dict[str, Any]:
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "categories": category_data,
        "summary": summary,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def write_csv(path: Path, category_data: dict[str, dict[str, list[str]]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["category", "entry_type", "value"])
        for category in REQUIRED_CATEGORIES:
            if category not in category_data:
                continue
            for country in category_data[category]["countries"]:
                writer.writerow([category, "country", country])
            for cidr in category_data[category]["cidrs"]:
                writer.writerow([category, "cidr", cidr])


def all_countries(category_data: dict[str, dict[str, list[str]]]) -> list[str]:
    combined: set[str] = set()
    for values in category_data.values():
        combined.update(values["countries"])
    return sorted(combined)


def all_cidrs(category_data: dict[str, dict[str, list[str]]]) -> list[str]:
    combined: set[str] = set()
    for values in category_data.values():
        combined.update(values["cidrs"])
    return sorted(combined)


def write_unifi(path: Path, cidrs: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("# UniFi firewall group entries\n")
        for cidr in cidrs:
            handle.write(f"{cidr}\n")


def write_pihole(path: Path, countries: list[str], cidrs: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("# Pi-hole regex blocklist generated from policy entries\n")
        for code in countries:
            handle.write(rf"(^|\.){code.lower()}$" + "\n")
        for cidr in cidrs:
            escaped = re.escape(cidr)
            handle.write(rf"^{escaped}$" + "\n")


def write_cloudflare(path: Path, countries: list[str], cidrs: list[str]) -> None:
    country_clause = " ".join(f'"{code}"' for code in countries)
    cidr_clause = " ".join(cidrs)

    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("# Cloudflare WAF expression\n")
        handle.write(f"(ip.src.country in {{{country_clause}}} or ip.src in {{{cidr_clause}}})\n")


def write_nginx(path: Path, countries: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("# Nginx geo map generated from policy countries\n")
        handle.write("map $geoip2_data_country_code $geofence_block {\n")
        handle.write("    default 0;\n")
        for code in countries:
            handle.write(f"    {code} 1;\n")
        handle.write("}\n")


def write_iptables(path: Path, cidrs: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("#!/usr/bin/env sh\n")
        handle.write("set -e\n")
        handle.write("ipset create geofence hash:net -exist\n")
        for cidr in cidrs:
            handle.write(f"ipset add geofence {cidr} -exist\n")
        handle.write("iptables -A INPUT -m set --match-set geofence src -j DROP\n")


def main() -> int:
    logger = setup_logging()
    args = parse_args()

    config_path = Path(args.config)
    data_root = Path(args.data_root)
    output_root = Path(args.output_root)

    try:
        config = load_policy_config(config_path)
        category_data, summary, warnings = build_policy(config, data_root, logger)
    except (PolicyBuildError, ValueError, OSError, json.JSONDecodeError) as exc:
        logger.error(str(exc))
        return 1

    for warning in warnings:
        logger.warning(warning)

    if args.strict and warnings:
        logger.error("Strict mode failed because warnings were found")
        return 1

    countries = all_countries(category_data)
    cidrs = all_cidrs(category_data)

    generated_files = [
        output_root / "geofence-policy.json",
        output_root / "geofence-policy.csv",
        output_root / "unifi" / "firewall-groups.txt",
        output_root / "pihole" / "regex-blocklist.txt",
        output_root / "cloudflare" / "waf-rules.txt",
        output_root / "nginx" / "geoip-map.conf",
        output_root / "iptables" / "ipset-rules.sh",
    ]

    if args.dry_run:
        logger.info("Dry run mode enabled. No files written.")
    else:
        ensure_output_dirs(output_root)
        write_json(output_root / "geofence-policy.json", build_json_output(category_data, summary))
        write_csv(output_root / "geofence-policy.csv", category_data)
        write_unifi(output_root / "unifi" / "firewall-groups.txt", cidrs)
        write_pihole(output_root / "pihole" / "regex-blocklist.txt", countries, cidrs)
        write_cloudflare(output_root / "cloudflare" / "waf-rules.txt", countries, cidrs)
        write_nginx(output_root / "nginx" / "geoip-map.conf", countries)
        write_iptables(output_root / "iptables" / "ipset-rules.sh", cidrs)

    logger.info("Total countries: %s", summary["total_countries"])
    logger.info("Total CIDRs: %s", summary["total_cidrs"])
    logger.info("Duplicates removed: %s", summary["duplicates_removed"])
    logger.info("Files generated: %s", len(generated_files))

    for generated in generated_files:
        logger.info("Generated file: %s", generated)

    return 0


if __name__ == "__main__":
    sys.exit(main())
