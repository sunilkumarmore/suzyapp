Suzy Coloring Samples (Animals) — Outline + Mask

Files:
- dino/dino_outline.png   : black outline, transparent background
- dino/dino_mask.png      : region mask (flat colors), transparent background
- lion/lion_outline.png
- lion/lion_mask.png

How to use (tap-to-color):
1) Render outline on top.
2) Use mask for hit-testing: read pixel at tap coordinate to identify region.
3) Fill region in your paint layer.

Notes:
- These masks are "single-image region maps" (multiple regions encoded as different colors).
- For production, keep regions big & closed; avoid tiny islands.
