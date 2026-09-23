"""Concurrent image downloading for the Cameroon crawler."""

import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlparse

import config
from session import download_stream

log = logging.getLogger("crawler")


def get_image_extension(url: str) -> str:
    """Determine image file extension from URL."""
    path = urlparse(url).path.lower()
    for ext in (".png", ".gif", ".webp", ".bmp", ".tiff"):
        if ext in path:
            return ext
    return ".jpg"


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

    log.info(f"Downloading {len(tasks)} images with {config.IMAGE_DOWNLOAD_WORKERS} workers...")
    success_count = 0

    def _download_one(url: str, dest: Path, item_id: str) -> bool:
        try:
            resp = download_stream(url)
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

    with ThreadPoolExecutor(max_workers=config.IMAGE_DOWNLOAD_WORKERS) as pool:
        futures = {
            pool.submit(_download_one, url, dest, iid): (url, dest)
            for url, dest, iid in tasks
        }
        for future in as_completed(futures):
            if future.result():
                success_count += 1

    return success_count