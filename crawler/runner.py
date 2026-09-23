"""Crawl orchestration: fetch pages, extract items, download images, persist JSON."""

import json
import logging
from pathlib import Path

import config
from extractors import (
    extract_attractions_page,
    extract_content_page,
    extract_overview_page,
    extract_region_page,
    extract_tours_page,
)
from images import download_images
from session import fetch_page

log = logging.getLogger("crawler")


def crawl_all(output_dir: Path, dry_run: bool = False) -> list[dict]:
    """Main crawl orchestrator."""
    all_items = []

    log.info(f"Starting crawl of {len(config.PAGES_TO_CRAWL)} pages...")

    for page_info in config.PAGES_TO_CRAWL:
        url = page_info["url"]
        page_type = page_info["type"]
        log.info(f"\n--- Crawling [{page_type}] {url} ---")

        soup = fetch_page(url)
        if not soup:
            continue

        # Dispatch to appropriate extractor
        if page_type == "region":
            items = extract_region_page(soup, page_info)
        elif page_type == "tours":
            items = extract_tours_page(soup, page_info)
        elif page_type == "overview":
            items = extract_overview_page(soup, page_info)
        elif page_type == "attractions":
            items = extract_attractions_page(soup, page_info)
        else:
            items = extract_content_page(soup, page_info)

        log.info(f"  Extracted {len(items)} items from {url}")
        all_items.extend(items)

    # Deduplicate by id, merging images
    seen_ids = {}
    unique_items = []
    for item in all_items:
        if item["id"] not in seen_ids:
            seen_ids[item["id"]] = len(unique_items)
            unique_items.append(item)
        else:
            existing = unique_items[seen_ids[item["id"]]]
            existing["images"].extend(item["images"])
            # Update description if new one is longer
            if len(item["description"]) > len(existing["description"]):
                existing["description"] = item["description"]

    log.info(f"\nTotal unique items: {len(unique_items)}")

    # Count images
    total_images = sum(len(item["images"]) for item in unique_items)
    log.info(f"Total images to download: {total_images}")

    # Download images
    if not dry_run and total_images > 0:
        downloaded = download_images(unique_items, output_dir)
        log.info(f"Successfully downloaded {downloaded}/{total_images} images")

    # Write JSON output
    json_path = output_dir / "cameroon_content.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(unique_items, f, indent=2, ensure_ascii=False)
    log.info(f"\nJSON output written to: {json_path}")

    # Summary
    print(f"\n{'='*60}")
    print(f"CRAWL COMPLETE")
    print(f"{'='*60}")
    print(f"Items extracted:  {len(unique_items)}")
    print(f"  Kingdoms:       {sum(1 for i in unique_items if i['category'] == 'Kingdom')}")
    print(f"  Landmarks:      {sum(1 for i in unique_items if i['category'] == 'Landmark')}")
    print(f"  Artifacts:      {sum(1 for i in unique_items if i['category'] == 'Artifact')}")
    print(f"  Legends:        {sum(1 for i in unique_items if i['category'] == 'Legend')}")
    print(f"  Culture:        {sum(1 for i in unique_items if i['category'] == 'Culture')}")
    print(f"Images found:     {total_images}")
    print(f"JSON output:      {json_path}")
    print(f"Images dir:       {output_dir / 'images'}")
    print(f"{'='*60}")

    return unique_items