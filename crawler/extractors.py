"""DOM traversal and per-page content extraction for the Cameroon crawler."""

import re
from urllib.parse import urljoin

from bs4 import BeautifulSoup, Tag

import config
from utils import (
    classify_category,
    clean_description,
    infer_location,
    is_skip_heading,
    slugify,
    trim_description,
)


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
    if w > 0 and h > 0 and (w < config.IMAGE_MIN_SIZE or h < config.IMAGE_MIN_SIZE):
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
    src = urljoin(config.BASE_URL + "/", src)

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


def extract_region_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract items from a regional/city page."""
    source_url = config.BASE_URL + page_info["url"]
    default_location = page_info.get("default_location", "Cameroon")
    sections = extract_content_sections(soup)
    return sections_to_items(sections, source_url, default_location)


def extract_tours_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract tour items from the tours listing page."""
    source_url = config.BASE_URL + page_info["url"]
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
    source_url = config.BASE_URL + page_info["url"]
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
    source_url = config.BASE_URL + page_info["url"]
    sections = extract_content_sections(soup)
    return sections_to_items(sections, source_url, "Cameroon")


def extract_content_page(soup: BeautifulSoup, page_info: dict) -> list[dict]:
    """Extract items from general content pages (history, culture, etc.)."""
    source_url = config.BASE_URL + page_info["url"]
    default_location = page_info.get("default_location", "Cameroon")
    sections = extract_content_sections(soup)
    return sections_to_items(sections, source_url, default_location)