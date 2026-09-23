#!/usr/bin/env python3
"""
Cameroon Cultural Content Crawler
=================================
Extracts stories, landmarks, artifacts, kingdoms, and legends from
https://discover-cameroon.com and downloads associated high-res images.

Usage:
    python3 main.py              # Full crawl + download
    python3 main.py --dry-run    # Crawl only, no image downloads
    python3 main.py --output DIR # Custom output directory
"""

import argparse
import logging
from pathlib import Path

import config
from runner import crawl_all

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)


def main():
    parser = argparse.ArgumentParser(
        description="Cameroon Cultural Content Crawler"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=config.DEFAULT_OUTPUT_DIR,
        help=f"Output directory (default: {config.DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Crawl pages only, skip image downloads",
    )
    args = parser.parse_args()

    # Create output directories
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "images" / "artifacts").mkdir(parents=True, exist_ok=True)
    (args.output / "images" / "landmarks").mkdir(parents=True, exist_ok=True)
    (args.output / "images" / "stories").mkdir(parents=True, exist_ok=True)

    crawl_all(args.output, dry_run=args.dry_run)


if __name__ == "__main__":
    main()