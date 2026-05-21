#!/usr/bin/env python3
"""Download policy source files directly into repository data folders."""

from __future__ import annotations

import argparse
import json
import logging
import sys
import urllib.error
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def setup_logging() -> logging.Logger:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    return logging.getLogger("policy_source_downloader")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download policy source files into data categories.")
    parser.add_argument("--manifest", default=str(REPO_ROOT / "config" / "policy-sources.json"), help="Path to source manifest JSON.")
    parser.add_argument("--data-root", default=str(REPO_ROOT / "data"), help="Root data directory in this repository.")
    parser.add_argument("--timeout", type=int, default=90, help="HTTP request timeout in seconds.")
    parser.add_argument("--dry-run", action="store_true", help="Show planned downloads without writing files.")
    return parser.parse_args()


def load_manifest(path: Path) -> list[dict]:
    if not path.exists():
        raise FileNotFoundError(f"Manifest file not found: {path}")

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    sources = data.get("sources", [])
    if not isinstance(sources, list):
        raise ValueError("Manifest 'sources' must be a list")

    return sources


def download_file(url: str, target_path: Path, timeout: int) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "Geo-Sentinel-PolicyUpdater/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        target_path.write_bytes(response.read())


def main() -> int:
    logger = setup_logging()
    args = parse_args()

    manifest_path = Path(args.manifest)
    data_root = Path(args.data_root)

    try:
        sources = load_manifest(manifest_path)
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        logger.error(str(exc))
        return 1

    planned = 0
    downloaded = 0
    skipped = 0
    failed = 0

    for source in sources:
        if not source.get("enabled", True):
            skipped += 1
            continue

        category = str(source.get("category", "")).strip()
        url = str(source.get("url", "")).strip()
        target_name = str(source.get("target", "")).strip()
        name = str(source.get("name", "unnamed_source")).strip()

        if not category or not url or not target_name:
            logger.warning("Skipping invalid source entry: %s", source)
            skipped += 1
            continue

        target_dir = data_root / category
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / target_name

        planned += 1

        if args.dry_run:
            logger.info("Dry run download: %s -> %s", url, target_path)
            continue

        try:
            download_file(url, target_path, args.timeout)
            logger.info("Downloaded %s to %s", name, target_path)
            downloaded += 1
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            logger.warning("Failed %s from %s: %s", name, url, exc)
            failed += 1

    logger.info("Sources planned: %s", planned)
    logger.info("Sources downloaded: %s", downloaded)
    logger.info("Sources skipped: %s", skipped)
    logger.info("Sources failed: %s", failed)

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
