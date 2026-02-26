#!/usr/bin/env python3
"""
Content preflight checks for SuzyApp assets.

Checks:
1) Local file exists and is non-empty.
2) Coloring mask sanity:
   - expects alpha to be only 0/255 (no semi-transparent pixels)
   - warns for opaque black regions (can be treated as boundaries in app)
   - warns for suspicious unique-color counts
   - warns for very tiny regions
3) Optional URL reachability for remote assets.
4) Audio sanity (0-byte mp3/wav).

Usage:
  python tools/preflight_content_check.py
  python tools/preflight_content_check.py --check-urls
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple
from urllib.error import URLError, HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

try:
    import numpy as np
    from PIL import Image
except Exception as exc:  # pragma: no cover
    print(f"Missing dependency: {exc}")
    print("Install with: pip install pillow numpy")
    sys.exit(2)


ROOT = Path(__file__).resolve().parents[1]
COLORING_JSON = ROOT / "assets" / "coloring" / "coloring_pages.json"
SFX_DIR = ROOT / "assets" / "audio" / "sfx"


@dataclass
class Issue:
    level: str  # ERROR | WARN | INFO
    scope: str
    message: str


def is_remote(path: str) -> bool:
    p = path.strip().lower()
    return p.startswith("http://") or p.startswith("https://") or p.startswith("gs://")


def normalize_local_asset(path: str) -> Path:
    p = path.strip().replace("\\", "/")
    if p.startswith("/"):
        p = p[1:]
    if p.startswith("./"):
        p = p[2:]
    while p.startswith("assets/assets/"):
        p = p.replace("assets/assets/", "assets/", 1)
    if not p.startswith("assets/"):
        p = f"assets/{p}"
    return ROOT / p


def load_coloring_pages() -> List[Dict[str, str]]:
    if not COLORING_JSON.exists():
        raise FileNotFoundError(f"Missing {COLORING_JSON}")
    data = json.loads(COLORING_JSON.read_text(encoding="utf-8"))
    pages = data.get("pages", [])
    if not isinstance(pages, list):
        raise ValueError("coloring_pages.json: `pages` must be a list")
    return pages


def check_exists_nonempty(path: Path, scope: str, issues: List[Issue]) -> None:
    if not path.exists():
        issues.append(Issue("ERROR", scope, f"Missing file: {path}"))
        return
    if not path.is_file():
        issues.append(Issue("ERROR", scope, f"Not a file: {path}"))
        return
    size = path.stat().st_size
    if size <= 0:
        issues.append(Issue("ERROR", scope, f"Empty file (0 bytes): {path}"))


def check_url(url: str, scope: str, issues: List[Issue]) -> None:
    if url.lower().startswith("gs://"):
        issues.append(Issue("WARN", scope, f"gs:// URL cannot be fetched directly: {url}"))
        return
    try:
        req = Request(url, method="HEAD")
        with urlopen(req, timeout=8) as resp:
            code = getattr(resp, "status", 200)
            if code >= 400:
                issues.append(Issue("ERROR", scope, f"URL HEAD failed ({code}): {url}"))
    except HTTPError as e:
        issues.append(Issue("ERROR", scope, f"URL failed ({e.code}): {url}"))
    except URLError as e:
        issues.append(Issue("ERROR", scope, f"URL unreachable: {url} ({e.reason})"))
    except Exception as e:
        issues.append(Issue("ERROR", scope, f"URL check failed: {url} ({e})"))


def _opaque_color_stats(rgba: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    alpha = rgba[:, :, 3]
    opaque = alpha == 255
    colors = rgba[:, :, :3][opaque]
    if colors.size == 0:
        return np.empty((0, 3), dtype=np.uint8), np.empty((0,), dtype=np.int64)
    unique, counts = np.unique(colors, axis=0, return_counts=True)
    return unique, counts


def check_mask(mask_path: Path, scope: str, issues: List[Issue]) -> None:
    try:
        with Image.open(mask_path) as img:
            rgba = np.array(img.convert("RGBA"))
    except Exception as e:
        issues.append(Issue("ERROR", scope, f"Mask decode failed: {mask_path} ({e})"))
        return

    if rgba.ndim != 3 or rgba.shape[2] != 4:
        issues.append(Issue("ERROR", scope, f"Mask is not RGBA: {mask_path}"))
        return

    alpha = rgba[:, :, 3]
    unique_alpha = np.unique(alpha)
    allowed_alpha = set([0, 255])
    if any(int(a) not in allowed_alpha for a in unique_alpha):
        mid = [int(a) for a in unique_alpha if int(a) not in allowed_alpha]
        issues.append(
            Issue(
                "WARN",
                scope,
                f"Semi-transparent pixels found ({len(mid)} alpha values). Expected alpha 0/255 only.",
            )
        )

    opaque_colors, counts = _opaque_color_stats(rgba)
    color_count = int(opaque_colors.shape[0])
    if color_count == 0:
        issues.append(Issue("ERROR", scope, "No opaque regions in mask."))
        return

    if color_count < 2:
        issues.append(Issue("WARN", scope, f"Only {color_count} opaque color region(s)."))
    if color_count > 80:
        issues.append(Issue("WARN", scope, f"Very high region color count ({color_count})."))

    # Opaque black can conflict with app's "ignore black" boundary logic.
    black_idx = np.where(
        (opaque_colors[:, 0] == 0)
        & (opaque_colors[:, 1] == 0)
        & (opaque_colors[:, 2] == 0)
    )[0]
    if black_idx.size > 0:
        issues.append(Issue("WARN", scope, "Opaque black region present in id-map."))

    # Tiny-region sanity by color pixel counts.
    tiny_threshold = 24
    tiny = int(np.sum(counts < tiny_threshold))
    if tiny > 0:
        issues.append(
            Issue(
                "WARN",
                scope,
                f"{tiny} region colors are tiny (<{tiny_threshold} px).",
            )
        )


def check_audio_sfx(issues: List[Issue]) -> None:
    if not SFX_DIR.exists():
        issues.append(Issue("WARN", "audio", f"Missing directory: {SFX_DIR}"))
        return
    for file in sorted(SFX_DIR.iterdir()):
        if not file.is_file():
            continue
        if file.suffix.lower() not in {".mp3", ".wav", ".ogg"}:
            continue
        if file.stat().st_size <= 0:
            issues.append(Issue("ERROR", "audio", f"Empty audio file: {file}"))


def collect_paths(page: Dict[str, str]) -> Tuple[str, str]:
    # Keep this aligned with current standardized schema.
    outline = str(page.get("outlineUrl") or page.get("imageAsset") or "").strip()
    mask = str(page.get("idMapUrl") or page.get("maskAsset") or "").strip()
    return outline, mask


def run(check_urls: bool) -> int:
    issues: List[Issue] = []
    pages = load_coloring_pages()

    seen_ids = set()
    for i, page in enumerate(pages):
        pid = str(page.get("id", "")).strip() or f"row_{i}"
        scope = f"coloring:{pid}"
        if pid in seen_ids:
            issues.append(Issue("WARN", scope, f"Duplicate page id: {pid}"))
        seen_ids.add(pid)

        outline, mask = collect_paths(page)
        if not outline:
            issues.append(Issue("ERROR", scope, "Missing outlineUrl/imageAsset."))
        if not mask:
            issues.append(Issue("ERROR", scope, "Missing idMapUrl/maskAsset."))

        for label, raw in (("outline", outline), ("mask", mask)):
            if not raw:
                continue
            if is_remote(raw):
                if check_urls:
                    check_url(raw, f"{scope}:{label}", issues)
                continue

            local = normalize_local_asset(raw)
            check_exists_nonempty(local, f"{scope}:{label}", issues)
            if label == "mask" and local.exists() and local.stat().st_size > 0:
                check_mask(local, f"{scope}:{label}", issues)

    check_audio_sfx(issues)

    errors = [x for x in issues if x.level == "ERROR"]
    warns = [x for x in issues if x.level == "WARN"]

    for item in issues:
        print(f"[{item.level}] {item.scope} - {item.message}")

    print(
        f"\nSummary: {len(errors)} error(s), {len(warns)} warning(s), "
        f"{len(issues) - len(errors) - len(warns)} info."
    )
    return 1 if errors else 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Preflight check for coloring/audio content.")
    parser.add_argument(
        "--check-urls",
        action="store_true",
        help="Check reachability for remote URLs (HTTP HEAD).",
    )
    args = parser.parse_args()
    sys.exit(run(check_urls=args.check_urls))


if __name__ == "__main__":
    main()
