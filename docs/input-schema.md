<!-- repo path: docs/input-schema.md -->

# Input schema

`items.json` is a **JSON array of objects**, one object per output image. An empty array or a
top-level object is rejected by `json_load()` before anything renders.

Field names below are exactly what `curve-text.sh` reads. Unknown keys are ignored, so extra
metadata is harmless. `null`, an absent key, and `""` are all treated as "not set": a missing
optional field takes its default, a missing required field is fatal for that run.

## Common fields

Required for every item regardless of mode.

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `mode` | string | yes | — | `arc` \| `perspective` \| `displace` \| `cylinderize`. Anything else is rejected by `validate_mode`. Overridable for a whole run with `--mode`. |
| `text` | string | yes | — | The label copy. Newlines wrap; it is also wrapped automatically at `label_width`. Passed to ImageMagick on stdin, never spliced into a command line, so `@`, quotes and `%` are safe. |
| `font` | string | yes | — | Path to a `.ttf`/`.otf`/`.ttc`, or a family name ImageMagick can resolve. Paths are checked on disk; family names are checked against `magick -list font`. Prefer paths — see `fonts/README.md`. |
| `mockup` | string | yes | — | Path to the product image the label is composited onto. |
| `center_x` | number | yes | — | Label centre on the mockup, px. Ignored in `perspective` mode, where the corners are already absolute. |
| `center_y` | number | yes | — | As above. |

## Typography

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `pointsize` | number | no | `96` | Honoured exactly, not shrunk to fit — `label_render` passes a width-only `-size`. Not comparable across mockups of different resolutions; see `docs/tuning.md`. |
| `fill` | string | no | `#222222` | Any ImageMagick colour. Also the input to the `blend` guess when `blend` is unset. |
| `label_width` | number | no | `1200` | Wrap width in px. Height grows to fit. A single word wider than this is a hard error, not a silent overhang. |
| `interline` | number | no | `0` | Extra leading in px. Negative tightens. Only visible on multi-line text. |
| `pad` | number | no | `24` | Transparent border around the trimmed label, px. Headroom so the distortion filters do not clip the glyph edges. Raise it if the ends of an arc look shaved. |

## Composite

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `blend` | string | no | guessed from `fill` | `multiply` \| `screen` \| `overlay` \| `over`. `composite_pick_blend` returns `screen` for near-white fills and `multiply` otherwise, which is wrong whenever the product is dark — set it explicitly there. |
| `opacity` | number | no | `0.92` | 0..1, scales the label's alpha. Slightly under 1 reads as printed ink rather than a decal. |
| `level_floor` | number | no | `18` | Black-point lift, percent. Bounds how dark the multiply can go so text survives on the shadow side. Above ~35 it looks washed out. |

## Mode: `arc`

Bends the label along a circular arc. See `docs/modes.md`.

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `arc_degrees` | number | **yes** | — | Angle the label spans. Roughly `57.3 × label_width / radius_px`. 90–140 is the useful range for a mug or tin. |
| `arc_rotate` | number | no | unset | Rotation of the arc centre, degrees. Pass `180` for text on the lower half of an object, or the curve reads inside-out. |

## Mode: `perspective`

Tilts the label into the plane of an off-axis shot. The four corners are **absolute mockup
coordinates**, so the label is already positioned and `center_x`/`center_y` are not used for
placement.

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `corners.tl` | `[x, y]` | **yes** | — | Top-left destination, px. |
| `corners.tr` | `[x, y]` | **yes** | — | Top-right. |
| `corners.br` | `[x, y]` | **yes** | — | Bottom-right. |
| `corners.bl` | `[x, y]` | **yes** | — | Bottom-left. |

Both elements of each pair are required and must be numeric. Order is clockwise from
top-left; swapping two corners produces a mirrored or folded label rather than an error.

## Mode: `displace`

Pushes pixels around using a greyscale map. The deep version is `docs/displacement-maps.md`.

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `displace_map` | string | **yes** | — | Path to the greyscale shading map. Must exist. Crop it to the region the label covers: it is stretched onto the label's box, not aligned to the mockup. |
| `displace_x` | number | no | `10` | Max horizontal offset in px at full black/white. This is the one that does the work on a vertical cylinder. |
| `displace_y` | number | no | `4` | Max vertical offset in px. Set to `0` for a clean upright cylinder. |

## Mode: `cylinderize`

Hands the prepared label to Fred Weinhaus' `cylinderize.sh`, which must already be on `PATH`
(or pointed at with the `CYLINDERIZE_BIN` environment variable). It is deliberately not
vendored; see `docs/troubleshooting.md`.

| Field | Type | Required | Default | Notes |
|-------|------|:--------:|---------|-------|
| `cyl_radius` | number | **yes** | — | Cylinder radius in px, at the mockup's scale. |
| `cyl_length` | number | **yes** | — | Cylinder length in px. |
| `cyl_wrap` | number | **yes** | — | Degrees of circumference the label covers. |
| `cyl_pitch` | number | no | `0` | Camera pitch, degrees. |
| `cyl_roll` | number | no | `0` | Camera roll, degrees. |
| `cyl_yaw` | number | no | `0` | Camera yaw, degrees. |
| `cyl_offset_x` | number | no | `0` | Translate the rendered cylinder within its canvas, px. |
| `cyl_offset_y` | number | no | `0` | As above. |

## Ignored but conventional

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | Not read by the tool. Kept in the example file as a human label for the item, since the manifest identifies rows by index. Useful in diffs. |

## Output naming

Each item produces `<outdir>/<NN>_<slug>.png`, where `NN` is the zero-padded array index and
`<slug>` comes from `slugify(text)`: lowercased, every non-alphanumeric run collapsed to a
single dash, trimmed, capped at 48 characters. `"Loose Leaf No. 3"` at index 2 gives
`02_loose-leaf-no-3.png`. Text that slugifies to nothing falls back to `item`.

The index prefix means two items with the same text do not collide, and the sort order of the
output directory matches the order of the JSON.

## Worked example

Matches the shipped `items.json`.

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
    "interline": -6,
    "mockup": "mockups/mug.png",
    "arc_degrees": 42,
    "center_x": 640,
    "center_y": 520,
    "blend": "multiply",
    "opacity": 0.92,
    "level_floor": 18
  },
  {
    "name": "bottle-wrap",
    "mode": "displace",
    "text": "Cold Pressed",
    "font": "fonts/DejaVuSerif.ttf",
    "pointsize": 120,
    "fill": "#f4f1ea",
    "label_width": 900,
    "mockup": "mockups/bottle.png",
    "displace_map": "mockups/bottle-shading.png",
    "displace_x": 14,
    "displace_y": 4,
    "center_x": 512,
    "center_y": 760,
    "blend": "screen",
    "opacity": 0.88,
    "level_floor": 12
  }
]
```

The bottle item is the instructive one: a light `fill` on a dark product, so `blend` is
`screen` rather than the multiply default, and `level_floor` is lowered because the clamp is
protecting against the opposite problem.

## Validation order

`validate_item` runs per item, before that item's first render:

1. `mode` is one of the four known values.
2. `text`, `mockup`, `font`, `center_x`, `center_y` are present.
3. `mockup` exists and is readable.
4. `font` exists on disk, or resolves in `magick -list font`.
5. `pointsize`, `center_x`, `center_y` are numeric.
6. The mode's own required fields, per the tables above.

Paths and numbers are checked before any ImageMagick call, so a typo in item 12 of 30 fails
fast rather than after eleven renders. It is not a whole-file pre-flight, though: item 12 is
validated when item 12 is reached, so items 0–11 will already have been written.
