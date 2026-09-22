#!/usr/bin/env python3
"""Export native vector icons from the approved optical SVG masters.

Run only when changing these SVGs; normal app builds use the committed PDFs.
Requires CairoSVG (and Cairo). On Homebrew macOS:
    DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 scripts/make-brand-marks.py
"""

from pathlib import Path

import cairosvg


ROOT = Path(__file__).resolve().parents[1] / "Resources" / "Brand"

for size, name in [(16, "MenuBarMark"), (20, "HeaderMark")]:
    source = ROOT / f"mark-optical-{size}-black.svg"
    destination = ROOT / f"{name}.pdf"
    # 72 dpi keeps one SVG unit equal to one PDF point. Paths remain vectors;
    # AppKit chooses the actual pixel density when drawing on a screen.
    cairosvg.svg2pdf(url=str(source), write_to=str(destination), dpi=72)
    print(f"{source.name} -> {destination.name} ({size} pt, vector)")
