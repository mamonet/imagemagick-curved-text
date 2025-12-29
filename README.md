# imagemagick-curved-text

A small Bash tool that renders text onto curved and cylindrical product mockups with ImageMagick,
driven from a JSON file. One command turns a list of items into a folder of finished images, with each
item's text, font, position, and curvature read from data rather than nudged by hand.

The point is the part that usually looks wrong: making the text read as *wrapped around* the surface,
picking up its curvature and lighting, instead of pasted on flat. It does that with ImageMagick's
distortion operators and an optional displacement map, and it can also drive Fred Weinhaus'
`cylinderize.sh` where a full cylinder wrap is wanted.

## What it does

- **Data-driven batch.** Reads a JSON array of items and renders one output image per item, so 3 or
  300 is the same command.
- **Text as its own layer first.** Typography (font, size, colour, tracking, wrapping) is settled on a
  transparent label before any bending, so distortion never softens badly-laid-out text.
- **Curve it onto the surface.** `-distort Arc` to bend the baseline around a cylinder, `-distort
  Perspective` for a tilted shot, or a displacement map derived from the product's own shading so the
  text rides the real curvature and highlights.
- **Blend into the lighting.** The wrapped text is composited back with a multiply/overlay pass so it
  picks up existing shadows instead of sitting on top.
- **Optional cylinderize.sh.** For a full wrap, the prepared label is handed to `cylinderize.sh` with
  per-item radius, perspective, and offset parameters, then composited onto the product.

Mockups in the samples are generic (a mug, a bottle, a tin) to keep the tool reusable; it is not tied
to any one product line.

## Requirements

- ImageMagick 7 (`magick`) or 6 (`convert`)
- `jq` for reading the JSON
- Bash
- Optional: `cylinderize.sh` (Fred Weinhaus) on `PATH` for the full-cylinder mode

## Input

```json
[
  {
    "name": "mug-front",
    "mode": "arc",
    "text": "Fresh Roast Daily",
    "font": "fonts/DejaVuSans-Bold.ttf",
    "pointsize": 96,
    "fill": "#2b2b2b",
    "label_width": 1100,
    "mockup": "mockups/mug.png",
    "arc_degrees": 42,
    "center_x": 640, "center_y": 520,
    "blend": "multiply",
    "opacity": 0.92
  }
]
```

`mode` is `arc`, `perspective`, `displace`, or `cylinderize`. Fields a mode does not need are
ignored, so a flat label is just `mode` omitted. Every field, with its default and which modes
require it, is in [docs/input-schema.md](docs/input-schema.md).

## Run

```bash
./curve-text.sh items.json out/
# one item only, for quick iteration
./curve-text.sh items.json out/ --only 0
```

Each run writes `out/<NN>_<slug>.png` (zero-padded index) and logs the parameters used per item, so a result can always
be traced back to its inputs.

## How it works (per item)

```bash
# 1. text as a transparent, high-res label
magick -background none -fill "$fill" -font "$font" -pointsize "$pointsize" \
       -size "${label_width}x" caption:"$text" label.png

# 2a. arc bend around the cylinder
magick label.png -virtual-pixel none -distort Arc "$arc_degrees" wrapped.png

# 2b. or a displacement map from the product shading (most natural)
magick label.png "$displace_map" -compose displace \
       -define compose:args="${displace_x}x${displace_y}" -composite wrapped.png

# 3. composite onto the product, picking up its lighting
magick "$mockup" wrapped.png -geometry "+$off_x+$off_y" \
       -compose "$blend" -composite "$out"
```

The `cylinderize` mode swaps step 2 for a call to `cylinderize.sh` with the item's radius, perspective,
and offset parameters.

## Why the label comes first

Bending text that was laid out badly does not fix it, it just softens the edges of the mistake.
Typography is settled on a flat transparent layer at high resolution, then that finished artwork is
distorted once. It also means the same label can be re-bent for a different mockup without
re-rendering the type.

## Samples

`samples/` holds before/after pairs so the output can be judged without installing anything:

| Mockup | Mode | Before / after |
|--------|------|----------------|
| mug | arc | `mug-arc-before.png` / `mug-arc-after.png` |
| bottle | displacement map | `bottle-displace-before.png` / `bottle-displace-after.png` |
| tin | displacement map | `tin-displace-before.png` / `tin-displace-after.png` |

The mockups in `mockups/` and these sample renders are generated procedurally by
`tools/make-mockups.py` (Python/Pillow), so the repo has usable inputs out of the box with no
photography and no licensed assets. Note that the sample renders therefore come from that
reference implementation, not from `curve-text.sh` itself. See
[samples/README.md](samples/README.md) for what that does and does not prove, and how to
replace them with genuine tool output.

## Repository layout

```
imagemagick-curved-text/
  curve-text.sh          main script (reads JSON, renders each item)
  lib/                   helpers: label render, arc, perspective, displace, cylinderize wrap
  mockups/               generic product images + shading maps
  fonts/                 a couple of open-licence fonts
  samples/               committed before/after outputs
  items.json             example input
  README.md
```

## Notes

- Data is the single source of truth: change a value in the JSON, re-run, get a consistent result.
- Generic mockups and open-licence fonts only; nothing tied to a specific client or product.
- The displacement-map mode is the one worth reading; arc and perspective are the quick paths.

MIT licensed.
