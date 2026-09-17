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
import json
import logging
import os
import re
import sys
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup, NavigableString, Tag

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BASE_URL = "https://discover-cameroon.com"
REQUEST_DELAY = 1.5  # seconds between page requests
IMAGE_DOWNLOAD_WORKERS = 5
IMAGE_MIN_SIZE = 200  # min width or height in px
REQUEST_TIMEOUT = 20
MAX_RETRIES = 3

DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "downloads"

# Pages to crawl mapped to their primary category context
PAGES_TO_CRAWL = [
    # Main content pages
    {"url": "/en/about-cameroon/", "type": "overview"},
    {"url": "/en/attractions/", "type": "attractions"},
    {"url": "/en/tours/", "type": "tours"},
    # Regional / city pages
    {"url": "/en/foumban-en/", "type": "region", "default_location": "Foumban, West Region"},
    {"url": "/en/douala/", "type": "region", "default_location": "Douala, Littoral Region"},
    {"url": "/en/history/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/culture-languages-religions/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/limbe/", "type": "region", "default_location": "Limbe, Southwest Region"},
    {"url": "/en/buea-en/", "type": "region", "default_location": "Buea, Southwest Region"},
    {"url": "/en/bamenda/", "type": "region", "default_location": "Bamenda, Northwest Region"},
    {"url": "/en/kribi/", "type": "region", "default_location": "Kribi, South Region"},
    {"url": "/en/things-to-do-in-cameroon/", "type": "content", "default_location": "Cameroon"},
    # Additional city/region pages
    {"url": "/en/yaounde/", "type": "region", "default_location": "Yaoundé, Centre Region"},
    {"url": "/en/garoua/", "type": "region", "default_location": "Garoua, North Region"},
    {"url": "/en/rhumsiki/", "type": "region", "default_location": "Rhumsiki, Far North Region"},
    {"url": "/en/bertoua/", "type": "region", "default_location": "Bertoua, East Region"},
    {"url": "/en/dschang-en/", "type": "region", "default_location": "Dschang, West Region"},
    {"url": "/en/ngaoundere-en/", "type": "region", "default_location": "Ngaoundéré, Adamawa Region"},
    # Special topic pages
    {"url": "/en/cameroon-national-parks/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/cameroon-regions/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/food-and-drinks/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/climate-geographie/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/general-informations/", "type": "content", "default_location": "Cameroon"},
]

# Category keywords for auto-classification
CATEGORY_KEYWORDS = {
    "Kingdom": [
        "kingdom", "palace", "sultan", "sultanate", "royal", "chief",
        "bandjoun", "baham", "bangoulap", "batoufam", "bamoun",
        "bamileke", "grassland people", "feudal", "dynasty",
    ],
    "Landmark": [
        "monument", "memorial", "statue", "fountain", "castle",
        "courthouse", "temple", "church", "mosque", "bridge",
        "colonial building", "reunification",
    ],
    "Artifact": [
        "museum", "artifact", "artwork", "sculpture", "mask",
        "craft", "carving", "pottery", "textile", "work of art",
    ],
    "Legend": [
        "legend", "myth", "crater lake", "sacred", "mystical",
        "magical", "supernatural", "never hits the water",
    ],
    "Culture": [
        "culture", "tradition", "festival", "ceremony", "language",
        "religion", "ethnic", "people", "pygmy", "ba'aka", "bayaka",
        "fang-beti", "coastal people", "sudano-sahelian",
    ],
}

# Region -> location string mapping
REGION_LOCATIONS = {
    "foumban": "Foumban, West Region",
    "douala": "Douala, Littoral Region",
    "limbe": "Limbe, Southwest Region",
    "buea": "Buea, Southwest Region",
    "bamenda": "Bamenda, Northwest Region",
    "kribi": "Kribi, South Region",
    "yaounde": "Yaoundé, Centre Region",
    "garoua": "Garoua, North Region",
    "rhumsiki": "Rhumsiki, Far North Region",
    "bertoua": "Bertoua, East Region",
    "dschang": "Dschang, West Region",
    "ngaoundere": "Ngaoundéré, Adamawa Region",
}

# Headings to skip (footer/nav)
SKIP_HEADINGS = {
    "follow & like us :", "our products", "our tours", "languages",
    "terms & conditions", "impressum", "privacy policy", "privacy overview",
    "discover our tours", "book your tours", "cameroon attractions",
    "follow & like us", "discover our tours",
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("crawler")

# ---------------------------------------------------------------------------
# HTTP Session
# ---------------------------------------------------------------------------

_session = requests.Session()
_session.headers.update({
    "User-Agent": (
        "Mozilla/5.0 (compatible; CameroonContentCrawler/1.0; "
        "+https://discover-cameroon.com)"
    )
})


def fetch_page(url: str) -> BeautifulSoup | None:
    """Fetch a page with retries and polite delay."""
    full_url = url if url.startswith("http") else BASE_URL + url
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            log.info(f"Fetching {full_url} (attempt {attempt})")
            resp = _session.get(full_url, timeout=REQUEST_TIMEOUT)
            resp.raise_for_status()
            time.sleep(REQUEST_DELAY)
            return BeautifulSoup(resp.text, "lxml")
        except requests.RequestException as e:
            log.warning(f"  Attempt {attempt} failed: {e}")
            if attempt < MAX_RETRIES:
                time.sleep(2 ** attempt)
    log.error(f"  Failed to fetch {full_url} after {MAX_RETRIES} attempts")
    return None


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

def slugify(text: str) -> str:
    """Convert text to a URL/file-safe slug."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-")[:80]


def classify_category(text: str) -> str:
    """Auto-classify content into a category based on keyword matching."""
    text_lower = text.lower()
    scores = {}
    for cat, keywords in CATEGORY_KEYWORDS.items():
        scores[cat] = sum(1 for kw in keywords if kw in text_lower)
    best = max(scores, key=scores.get)
    return best if scores[best] > 0 else "Culture"


def get_location_from_url(url: str) -> str:
    """Infer location from the page URL path."""
    path = urlparse(url).path.lower()
    for key, loc in REGION_LOCATIONS.items():
        if key in path:
            return loc
    return "Cameroon"


def is_skip_heading(text: str) -> bool:
    """Check if a heading should be skipped (footer/nav)."""
    return text.lower().strip() in SKIP_HEADINGS or len(text.strip()) < 3


def clean_description(text: str) -> str:
    """Remove footer/navigation artifacts and clean description text."""
    if not text:
        return text
    
    # Patterns to remove (footer text, navigation, placeholders)
    footer_patterns = [
        r"Follow & Like us.*",
        r"Facebook.*Instagram.*Twitter.*",
        r"Discover our tours.*",
        r"Book your tours.*",
        r"Our Products.*",
        r"Our Tours.*",
        r"Contact - Us.*",
        r"Contact Us.*",
        r"Privacy Policy.*",
        r"Terms & Conditions.*",
        r"Impressum.*",
        r"Languages.*",
        r"Français.*",
        r"English.*",
        r"Deutsch.*",
        r"XXXXXX.*",
        r"XXX.*",
    ]
    
    for pattern in footer_patterns:
        text = re.sub(pattern, "", text, flags=re.IGNORECASE | re.DOTALL)
    
    # Remove multiple newlines and clean whitespace
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = re.sub(r"\s{2,}", " ", text)
    text = text.strip()
    
    return text


def trim_description(text: str, max_length: int = 1500) -> str:
    """Trim description to a reasonable length, preserving complete sentences."""
    if not text or len(text) <= max_length:
        return text
    
    # Find a good breaking point (end of sentence)
    trimmed = text[:max_length]
    last_period = trimmed.rfind(".")
    last_newline = trimmed.rfind("\n")
    
    # Use the last sentence end or paragraph break
    break_point = max(last_period, last_newline)
    if break_point > max_length * 0.7:  # At least 70% of max_length
        return trimmed[:break_point + 1].strip()
    
    return trimmed.strip() + "..."


# ---------------------------------------------------------------------------
# Elementor DOM Traversal
# ---------------------------------------------------------------------------
# The site uses Elementor which wraps each widget in:
#   div.elementor-column.elementor-col-100.elementor-top-column
#     div.elementor-widget.elementor-widget-heading  → h2 title
#     div.elementor-widget.elementor-widget-image     → img
#     div.elementor-widget.elementor-widget-text-editor → paragraph text
#
# We walk the top-level elementor-top-column divs in order,
# grouping them into sections: heading → image(s) → text


def parse_elementor_sections(article: Tag) -> list[dict]:
    """
    Walk all elementor-top-column divs in document order.
    Returns a list of sections, each with 'title', 'images', 'text'.
    Handles both shallow and nested Elementor structures.
    """
    top_cols = article.find_all(
        "div", class_=lambda c: c and "elementor-top-column" in c
    )

    sections = []
    current_section = None

    for col in top_cols:
        # Find heading widget (may be nested) — standard or CTA widget
        heading_widget = col.find(
            "div", class_=lambda c: c and "elementor-widget-heading" in c
        )
        if not heading_widget:
            # Tours page uses call-to-action widgets for headings
            cta_widget = col.find(
                "div", class_=lambda c: c and "elementor-widget-call-to-action" in c
            )
            if cta_widget:
                heading_widget = cta_widget
        # Find image widget (may be nested)
        image_widget = col.find(
            "div", class_=lambda c: c and "elementor-widget-image" in c
        )
        # Find any widget that contains text (heading, text-editor, or generic)
        text_widget = col.find(
            "div", class_=lambda c: c and (
                "elementor-widget-text-editor" in c
                or ("elementor-widget" in c and "elementor-widget-heading" not in c
                    and "elementor-widget-image" not in c)
            )
        )

        if heading_widget:
            h = heading_widget.find(["h1", "h2", "h3", "h4"])
            if h:
                title = h.get_text(strip=True)
                if is_skip_heading(title):
                    current_section = None
                    continue
                current_section = {
                    "title": title,
                    "tag": h.name,
                    "images": [],
                    "text_parts": [],
                }
                sections.append(current_section)

        elif image_widget and current_section is not None:
            img = image_widget.find("img")
            if img:
                img_data = extract_single_image(img)
                if img_data:
                    current_section["images"].append(img_data)

        elif text_widget and current_section is not None:
            # Get text content from any text-containing widget
            container = text_widget.find("div", class_="elementor-widget-container")
            if not container:
                container = text_widget
            # Extract paragraphs
            paragraphs = container.find_all("p")
            for p in paragraphs:
                t = p.get_text(strip=True)
                if t:
                    current_section["text_parts"].append(t)
            # If no paragraphs, try raw text
            if not paragraphs:
                raw = container.get_text(strip=True)
                if raw:
                    current_section["text_parts"].append(raw)

    return sections


def extract_content_sections(soup: BeautifulSoup) -> list[dict]:
    """Generic section extraction using Elementor top-column traversal."""
    article = soup.find("article") or soup
    return parse_elementor_sections(article)


# ---------------------------------------------------------------------------
# Image Extraction
# ---------------------------------------------------------------------------

def extract_single_image(img: Tag) -> dict | None:
    """Extract a single image's data, filtering out logos/icons/placeholders."""
    # Check dimensions
    try:
        w = int(img.get("width", 0) or 0)
        h = int(img.get("height", 0) or 0)
    except (ValueError, TypeError):
        w, h = 0, 0

    # Skip small images (icons, flags, UI elements)
    if w > 0 and h > 0 and (w < IMAGE_MIN_SIZE or h < IMAGE_MIN_SIZE):
        return None

    # Get the actual image URL (prefer data-src for lazy-loaded images)
    src = img.get("data-src", "") or img.get("src", "")

    # Skip base64 placeholders and empty sources
    if not src or src.startswith("data:"):
        return None

    # Skip non-content images
    if "wp-content/uploads" not in src:
        return None

    # Try to get full-resolution URL from srcset
    srcset = img.get("srcset", "")
    if srcset:
        full_url = parse_srcset_largest(srcset)
        if full_url:
            src = full_url

    # Resolve relative URLs
    src = urljoin(BASE_URL + "/", src)

    alt = img.get("alt", "").strip()

    return {
        "original_url": src,
        "alt_text": alt,
        "width": w,
        "height": h,
    }


def parse_srcset_largest(srcset: str) -> str | None:
    """Parse srcset and return the largest resolution image URL."""
    candidates = []
    for entry in srcset.split(","):
        entry = entry.strip()
        if not entry:
            continue
        parts = entry.split()
        if len(parts) >= 2:
            url = parts[0]
            descriptor = parts[1]
            if descriptor.endswith("w"):
                try:
                    w = int(descriptor[:-1])
                    candidates.append((w, url))
                except ValueError:
                    pass
    if candidates:
        candidates.sort(key=lambda x: x[0], reverse=True)
        return candidates[0][1]
    return None


def extract_images_for_section(section: dict) -> list[dict]:
    """Return images already collected in the section dict."""
    return section.get("images", [])


# ---------------------------------------------------------------------------
# Historical Significance Extractor
# ---------------------------------------------------------------------------

def extract_historical_significance(text: str) -> str:
    """Extract sentences that speak to historical/cultural significance."""
    significance_keywords = [
        "founded", "built", "established", "created", "dating back",
        "years old", "centuries", "ancient", "colonial", "kingdom",
        "dynasty", "heritage", "tradition", "ceremony", "sacred",
        "legend", "myth", "believed", "according to", "historical",
        "monument", "oldest", "first", "origin", "founded in",
        "named after", "dedicated to", "memory", "symbol",
        "was built", "was constructed", "was created",
        "date back", "originated", "played a role",
    ]
    sentences = re.split(r'(?<=[.!?])\s+', text)
    relevant = []
    for sentence in sentences:
        if any(kw in sentence.lower() for kw in significance_keywords):
            relevant.append(sentence.strip())
    return " ".join(relevant) if relevant else ""


# ---------------------------------------------------------------------------
# Page-specific Extractors
# ---------------------------------------------------------------------------

def sections_to_items(
    sections: list[dict],
    source_url: str,
    default_location: str = "Cameroon",
    default_category: str | None = None,
) -> list[dict]:
    """Convert parsed Elementor sections into the output JSON schema."""
    items = []
    for section in sections:
        title = section["title"]
        description = "\n\n".join(section["text_parts"])
        
        # Clean description (remove footer text, placeholders)
        description = clean_description(description)
        
        # Trim oversized descriptions
        description = trim_description(description)
        
        images = section["images"]
        combined = title + " " + description
        category = default_category or classify_category(combined)
        location = default_location

        # Try to infer location from content
        if location == "Cameroon":
            location = infer_location(combined)

        if not description or len(description) < 15:
            continue

        items.append({
            "id": slugify(title),
            "title": title,
            "category": category,
            "location": location,
            "description": description,
            "historical_significance": extract_historical_significance(description),
            "source_url": source_url,
            "images": [
                {
                    "original_url": img["original_url"],
                    "alt_text": img["alt_text"],
                }
                for img in images
            ],
        })
    return items


def infer_location(text: str) -> str:
    """Try to infer a more specific location from text content."""
    text_lower = text.lower()
    location_hints = [
        ("foumban", "Foumban, West Region"),
        ("douala", "Douala, Littoral Region"),
        ("limbe", "Limbe, Southwest Region"),
        ("buea", "Buea, Southwest Region"),
        ("bamenda", "Bamenda, Northwest Region"),
        ("kribi", "Kribi, South Region"),
        ("yaoundé", "Yaoundé, Centre Region"),
        ("yaounde", "Yaoundé, Centre Region"),
        ("garoua", "Garoua, North Region"),
        ("rhumsiki", "Rhumsiki, Far North Region"),
        ("bertoua", "Bertoua, East Region"),
        ("dschang", "Dschang, West Region"),
        ("ngaoundéré", "Ngaoundéré, Adamawa Region"),
        ("mount cameroon", "Mount Cameroon, Southwest Region"),
        ("bandjoun", "Bandjoun, West Region"),
        ("baham", "Baham, West Region"),
        ("bangoulap", "Bangoulap, West Region"),
        ("bimbia", "Bimbia, Southwest Region"),
        ("korup", "Korup National Park, Southwest Region"),
        ("kribi", "Kribi, South Region"),
        ("djé", "Dja Reserve, South Region"),
        ("loéké", "Lobéké National Park, Southeast Region"),
    ]
    for hint, loc in location_hints:
        if hint in text_lower:
            return loc
    return "Cameroon"


# ---------------------------------------------------------------------------
# Page-specific Extractors
# ---------------------------------------------------------------------------

def extract_region_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract items from a regional/city page."""
    source_url = BASE_URL + page_info["url"]
    default_location = page_info.get("default_location", "Cameroon")
    sections = extract_content_sections(soup)
    return sections_to_items(sections, source_url, default_location)


def extract_tours_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract tour items from the tours listing page."""
    source_url = BASE_URL + page_info["url"]
    sections = extract_content_sections(soup)

    # For tours, we need to also extract metadata (duration, price, etc.)
    items = []
    for section in sections:
        title = section["title"]
        description_parts = section["text_parts"]
        images = section["images"]

        # Build full text to extract metadata
        full_text = "\n".join(description_parts)

        # Parse tour metadata
        duration = ""
        price_info = ""
        start_location = "Cameroon"
        attractions = []
        tour_category = "Culture"

        for part in description_parts:
            if part.startswith("Duration:"):
                duration = part.replace("Duration:", "").strip()
            elif part.startswith("Price:"):
                price_info += part + "\n"
            elif part.startswith("Start:"):
                start_location = part.replace("Start:", "").strip()
            elif part.startswith("End"):
                pass  # Skip end location
            elif part == "View Tour":
                continue
            elif part in ("Ecotourism", "Seaside", "Discovery", "Trekking",
                          "Historical", "Cultural", "Ecotourisme"):
                tour_category = part.capitalize()
                if tour_category == "Ecotourisme":
                    tour_category = "Ecotourism"
            elif not part.startswith(("Departure", "Attractions")):
                attractions.append(part)

        # Build description
        desc_lines = []
        if duration:
            desc_lines.append(f"Duration: {duration}")
        if price_info.strip():
            desc_lines.append(price_info.strip())
        if start_location:
            desc_lines.append(f"Start: {start_location}")
        if attractions:
            desc_lines.append("\nKey Attractions:")
            for a in attractions:
                # Filter out placeholders and short items
                if len(a) > 3 and a not in ("XXX", "XXXXXX", "XXXXXXX"):
                    # Clean tour name prefix
                    a = re.sub(r"^Tour:\s*", "", a)
                    desc_lines.append(f"  • {a}")

        description = "\n".join(desc_lines)
        
        # Clean the description
        description = clean_description(description)
        if not description or len(description) < 10:
            continue

        combined = title + " " + description
        category = classify_category(combined)

        location = infer_location(combined) or start_location

        items.append({
            "id": slugify(title),
            "title": title,
            "category": category,
            "location": location,
            "description": description,
            "historical_significance": extract_historical_significance(
                title + " " + description
            ),
            "source_url": source_url,
            "images": [
                {"original_url": img["original_url"], "alt_text": img["alt_text"]}
                for img in images
            ],
        })

    return items


def extract_overview_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract content from the About Cameroon overview page."""
    source_url = BASE_URL + page_info["url"]
    sections = extract_content_sections(soup)
    items = sections_to_items(sections, source_url, "Cameroon")

    # If sections didn't yield much, fall back to article text extraction
    if len(items) < 2:
        article = soup.find("article") or soup
        text = article.get_text(separator="\n", strip=True)
        paragraphs = [p.strip() for p in text.split("\n\n") if len(p.strip()) > 50]
        for i, para in enumerate(paragraphs[:15]):
            # Clean the paragraph
            para = clean_description(para)
            para = trim_description(para)
            
            if not para or len(para) < 50:
                continue
            
            first_line = para.split("\n")[0][:80] if "\n" in para else para[:80]
            combined = first_line + " " + para
            items.append({
                "id": f"about-cameroon-{i+1:02d}",
                "title": first_line.strip(),
                "category": classify_category(combined),
                "location": "Cameroon",
                "description": para,
                "historical_significance": extract_historical_significance(para),
                "source_url": source_url,
                "images": [],
            })

    return items


def extract_attractions_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract attraction category items."""
    source_url = BASE_URL + page_info["url"]
    sections = extract_content_sections(soup)
    return sections_to_items(sections, source_url, "Cameroon")


def extract_content_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract items from general content pages (history, culture, etc.)."""
    source_url = BASE_URL + page_info["url"]
    default_location = page_info.get("default_location", "Cameroon")
    sections = extract_content_sections(soup)
    return sections_to_items(sections, source_url, default_location)


# ---------------------------------------------------------------------------
# Image Downloader
# ---------------------------------------------------------------------------

def download_images(items: list[dict], output_dir: Path) -> int:
    """Download all images for all items. Returns count of successful downloads."""
    tasks = []
    for item in items:
        cat = item["category"]
        if cat in ("Kingdom", "Landmark", "Artifact"):
            img_dir = output_dir / "images" / "landmarks"
        elif cat == "Legend":
            img_dir = output_dir / "images" / "stories"
        else:
            img_dir = output_dir / "images" / "stories"

        for idx, img in enumerate(item["images"], 1):
            ext = get_image_extension(img["original_url"])
            filename = f"{item['id']}-{idx:02d}{ext}"
            local_path = img_dir / filename
            img["local_filename"] = str(local_path.relative_to(output_dir))
            tasks.append((img["original_url"], local_path, item["id"]))

    log.info(f"Downloading {len(tasks)} images with {IMAGE_DOWNLOAD_WORKERS} workers...")
    success_count = 0

    def _download_one(url: str, dest: Path, item_id: str) -> bool:
        try:
            resp = _session.get(url, timeout=REQUEST_TIMEOUT, stream=True)
            resp.raise_for_status()
            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "wb") as f:
                for chunk in resp.iter_content(8192):
                    f.write(chunk)
            log.info(f"  ✓ Downloaded {dest.name} for '{item_id}'")
            return True
        except Exception as e:
            log.warning(f"  ✗ Failed to download {url}: {e}")
            return False

    with ThreadPoolExecutor(max_workers=IMAGE_DOWNLOAD_WORKERS) as pool:
        futures = {
            pool.submit(_download_one, url, dest, iid): (url, dest)
            for url, dest, iid in tasks
        }
        for future in as_completed(futures):
            if future.result():
                success_count += 1

    return success_count


def get_image_extension(url: str) -> str:
    """Determine image file extension from URL."""
    path = urlparse(url).path.lower()
    for ext in (".png", ".gif", ".webp", ".bmp", ".tiff"):
        if ext in path:
            return ext
    return ".jpg"


# ---------------------------------------------------------------------------
# Main Crawler
# ---------------------------------------------------------------------------

def crawl_all(output_dir: Path, dry_run: bool = False) -> list[dict]:
    """Main crawl orchestrator."""
    all_items = []

    log.info(f"Starting crawl of {len(PAGES_TO_CRAWL)} pages...")

    for page_info in PAGES_TO_CRAWL:
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


# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Cameroon Cultural Content Crawler"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})",
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
