<!-- repo path: docs/tuning.md -->

# Tuning

Practical values, and how to arrive at them without guessing forty times.

## Picking `arc_degrees`

`arc_degrees` is the angle the text band subtends around the cylinder, not a style knob. Work
it out from the geometry rather than by eye:

```
degrees ≈ 57.3 × label_width_px / radius_px
```

`radius_px` is half the object's visible width in the mockup at the height of the label —
measure it, do not assume it is half the image. `label_width_px` is the item's `label_width`.

Example: a mug 800px across at label height gives `radius_px = 400`. A 720px label:
`57.3 × 720 / 400 ≈ 103`, so start at 100.

Sanity limits:

- Under ~30°: the curve is not visible; drop to a flat composite instead of pretending.
- 90°–140°: the useful range for a mug or tin seen straight on.
- Over ~150°: the ends of the text are turning away from the camera faster than `Arc` can
  express, because `Arc` does not foreshorten. Switch to `displace` or `cylinderize`.

`-distort Arc` opens the arc **downwards** by default (text curving like a smile needs the
second argument). The full form is `-distort Arc "angle rotate top_radius bottom_radius"`;
pass `180` as the rotate value to flip the curve for text on the lower half of an object.
`arc_apply_below()` in `lib/arc.sh` is that call with the rotate baked in.

Getting the curve upside down is the single most common first-run surprise. Check it before
tuning anything else.

## Matching pointsize across items

`pointsize` is in points at the render density, so the same number gives different physical
sizes on mockups of different resolutions. Two items that "should look the same" will not.

Normalise against a reference width instead of copying the number:

```
pointsize = base_pointsize × (mockup_width / reference_width)
```

Pick one mockup as the reference (say the 1600px mug), tune `base_pointsize` there, then scale
for the others. Rounded to the nearest integer; ImageMagick accepts fractional pointsize but
hinting makes the result inconsistent.

To compare across items in the data rather than in your head, measure the rendered cap height:

```bash
magick -background none -fill black -font fonts/Inter-SemiBold.ttf \
       -pointsize 64 label:'H' -trim -format '%h\n' info:
```

Two items match when that number matches, not when `pointsize` matches. Different families at
the same pointsize differ by 15–20% in cap height, which is very visible on a shelf of
products.

Also watch: `caption:` treats pointsize as an upper bound and shrinks the text to fit a `-size
WxH` box, so a long string silently renders smaller than a short one and the set looks
inconsistent with no error anywhere. `label_render()` avoids this by passing a width only
(`-size "${width}x"`), which honours the pointsize and lets the box grow downwards. If you
call ImageMagick by hand, do the same.

## Render oversized, then downsample

Every distortion is a resample. Distorting at final size gives ragged near-horizontal strokes,
the classic tell that text was bent after the fact.

Render the label at 3–4× and reduce after the distortion, never before:

```bash
scale=4
magick -background none -fill "$fill" -font "$font" \
       -pointsize "$((pointsize * scale))" -size "$((label_width * scale))x" \
       caption:@- label-big.png <<<"$text"

magick label-big.png -virtual-pixel none -distort Arc "$arc_degrees" \
       -filter Lanczos -resize "$((100 / scale))%" wrapped.png
```

Or let ImageMagick supersample the distortion itself, which does the same thing without the
intermediate:

```bash
magick label.png -virtual-pixel none \
       -define distort:scale=4 -distort Arc "$arc_degrees" \
       -filter Lanczos -resize 25% wrapped.png
```

Notes:

- `-filter Lanczos` on the way down. The default `-resize` filter is fine for photos and too
  soft for type.
- 4× is the point of diminishing returns. 8× quadruples the memory for no visible gain.
- Downsample **once**, at the end. Two reduction passes soften strokes noticeably.
- If the result is now slightly soft rather than jagged, a single `-unsharp 0x0.6+0.6+0.01`
  after the resize is enough. More than that and the edges start ringing along the curve.

## Text that vanishes on dark areas

The `multiply` default in `composite_place()` is what makes the text pick up existing shadow —
and multiply cannot lighten. Dark text on the shadowed side of an object goes to near-black
and disappears; light text does nothing at all under multiply.

Three knobs, all per-item, all passed through to `composite_place`:

| Field | Default | What it does |
|-------|---------|--------------|
| `blend` | guessed from `fill` | blend mode: `multiply`, `screen`, `overlay`, `over` |
| `opacity` | `0.92` | scales the label's alpha; below 1.0 reads as printed ink, not a decal |
| `level_floor` | `18` | black-point lift %, the clamp that stops multiply crushing the ink |

`level_floor` solves the vanishing text, and it is worth understanding: the label's
RGB is levelled to `level_floor%,100%` before blending, so its darkest value is bounded and the
multiply result cannot reach black. Raise it on dark products, lower it on white ones where
the ink should read as genuinely black. Above about 35 the text starts looking washed out.

Pick `blend` from the target region, not the whole mockup. Sample its mean luminance:

```bash
magick mockups/mug.png \
       -crop "${label_width}x120+$((center_x - label_width / 2))+${center_y}" +repage \
       -colorspace Gray -format 'mean=%[fx:mean]\n' info:
```

- `mean > 0.55`: dark ink on a light surface, `multiply`. The normal case.
- `mean < 0.45`: light ink on a dark surface. `screen`, or multiply erases it.
- In between, or a band spanning both: `overlay` keeps mid-tones readable in both directions
  and holds the highlights, at the cost of a slightly flatter look.

`composite_pick_blend()` guesses this from the fill colour alone, which is a decent default
and wrong whenever the product is dark. Set `blend` explicitly on those items.

If the text has to cross a hard shadow edge and stay readable, do not fight the blend mode.
Either move the label, or give it a thin contrasting outline at render time:

```bash
-stroke '#ffffff' -strokewidth 2 -fill "$fill"
```

Keep the stroke under about 3% of cap height. Above that it reads as an outline font rather
than as separation, and the arc distortion exaggerates it further at the ends of the curve.

## Iterating quickly

Use `--only N` and `--verbose` together. `--only` renders a single item; `--verbose` echoes
each ImageMagick command with `%q` quoting, so a line can be pasted straight into a shell and
tweaked by hand before the value goes back into `items.json`.

```bash
./curve-text.sh items.json out/ --only 0 --verbose
```

The per-run `out/manifest.tsv` records the parameters actually used for every item, so a
render that looked right two weeks ago can be reproduced from the row rather than from memory.
