<!-- repo path: docs/displacement-maps.md -->

# Displacement maps

This is the mode that makes text look like it is on the object rather than over it. It is
also the one with the most ways to go quietly wrong, so this document is longer than the
others.

## What a displacement map is

A displacement map is not an image you look at. It is a per-pixel lookup table: for each
output pixel, it says *which nearby pixel of the source to fetch instead*. ImageMagick's
`displace` compose method reads the map's channel values and turns them into an offset.

- **Red channel drives the horizontal offset. Green drives the vertical.**
- Values are read normalised to `0.0 .. 1.0`.
- `0.5` (mid-grey, `#808080`) means **no displacement**. That is the whole convention.
- Offset in pixels is `scale * (2 * value - 1)`. So with a scale of 20: black pulls 20px one
  way, white 20px the other, mid-grey nothing.

The map is the *overlay* image and the image being bent is the *destination*:

```bash
magick label.png mockups/mug-shading.png \
       -compose displace -define compose:args="20x0" -composite wrapped.png
```

`label.png` is what gets pushed around. `mug-shading.png` is the instruction sheet.

## Why greyscale

Because in a grey image red equals green, so a single map can drive both axes and you choose
which axes actually move with `compose:args`.

`lib/displace.sh` builds that string from the item's `displace_x` and `displace_y`:

| `compose:args` | `displace_x` / `displace_y` | Effect |
|----------------|------------------------------|--------|
| `20x0` | 20 / 0 | horizontal only — this is what a vertical cylinder wants |
| `0x20` | 0 / 20 | vertical only — a horizontal roll, a curved lid |
| `20x20` | 20 / 20 | both, from the same grey values, so everything shifts diagonally |
| `20x0%` | — | trailing `%` makes the scale a percentage of image size, not pixels |

Using a colour map is legal and lets the two axes disagree, but then you are hand-authoring
two independent gradients and you have lost the reason to derive the map from the photo. Keep
it grey and let `compose:args` do the separation. `20x20` is almost always a mistake: it is
the default-looking value that produces a diagonal smear nobody asked for.

## Why the dimensions must match

Raw ImageMagick composites the map onto the destination like any other overlay: at `+0+0`,
with **no automatic scaling and no error on mismatch.**

- Map smaller than the label: only the top-left region is displaced. The rest of the text
  stays perfectly flat, and the boundary between the two is a visible vertical step.
- Map larger: only its top-left corner is ever sampled, so the offsets come from the wrong
  part of the curve. The text still bends, just along a curve that is not the product's. It
  looks almost right, which is the worse failure.

`displace_prepare_map()` in `lib/displace.sh` removes that trap by forcing the map to the
label's exact dimensions with `-resize WxH!` before compositing. That fixes the alignment but
it cannot fix the framing, and this is the part that catches people:

> **The map is stretched as a whole onto the label's box.** Hand it the full mockup shading
> and the entire product — handle, backdrop, rim — gets squashed into the area the text
> occupies. The offsets are then derived from the wrong part of the curve.

So supply a map cropped to the label's footprint on the product, not the whole photo:

```bash
# the region the label will actually cover
magick mockups/mug-shading.png \
       -crop "${label_width}x${label_height}+$((center_x - label_width / 2))+$((center_y - label_height / 2))" \
       +repage mockups/mug-shading-band.png
```

`-resize WxH!` also ignores aspect ratio, so a band cropped at a very different aspect to the
label will have its gradient horizontally scaled. Crop close to the label's proportions.

Two more things that silently change the result:

- **Alpha in the map.** Transparent pixels attenuate the displacement. A map saved with an
  alpha channel from an editor will fade out at exactly the edges you cared about. Strip it:
  `magick map.png -alpha off map.png`.
- **`-virtual-pixel`.** Displacement fetches pixels from outside the source near the edges.
  The default `edge` smears the border colour inward. For a transparent label use
  `-virtual-pixel transparent`; you want nothing there, not a stretched pixel.

```bash
magick label-full.png mockups/mug-shading.png \
       -virtual-pixel transparent \
       -compose displace -define compose:args="20x0" -composite wrapped.png
```

## Deriving the map from the product's own shading

The reason to use the photo instead of a synthetic gradient: the surface already encodes its
own curvature. On a diffusely lit cylinder, brightness falls off towards each side because
the surface is turning away — and that turn is exactly the foreshortening the text needs.

`displace_prepare_map()` already applies `-colorspace Gray`, `-auto-level`, `-blur 0x6` and
the resize at run time, so a committed map does not have to be perfect. Do the work below
anyway when the automatic pass is not enough: a noisy photo needs a harder blur than the
default sigma, and `-auto-level` alone will not re-centre a map whose lighting was off-axis.

```bash
# luminance only; blur hard so print, texture and sensor noise do not become displacement
magick mockups/mug.png -alpha off -colorspace Gray -blur 0x12 \
       -auto-level +level 25%,75% mockups/mug-shading.png
```

Each step earns its place:

- `-alpha off` — see above.
- `-colorspace Gray` — collapse to luminance so R and G agree.
- `-blur 0x12` — a displacement map must be smooth. Any detail left in it becomes a ripple in
  the text. Over-blur rather than under-blur; you are modelling a surface, not copying one.
- `-auto-level` — use the full range, otherwise a flatly lit photo produces a map that barely
  moves anything.
- `+level 25%,75%` — compress back around mid-grey. Without it the darkest pixel takes the
  full `compose:args` offset and the text tears at the edge of the object.

Verify before using it:

```bash
magick mockups/mug-shading.png -format 'mean=%[fx:mean] w=%w h=%h alpha=%A\n' info:
```

`mean` near `0.5` means the map is centred and the text will not drift bodily sideways. If the
light was off-centre, `mean` will be off too; fix it with `-evaluate subtract`/`add` or by
re-levelling, not by nudging `compose:args`.

### Where the photo lies

Brightness is a proxy for the surface normal, not a measurement of it. Two cases to watch:

- **Specular highlights.** A blown-out hotspot is white, so the map reads it as maximum
  displacement, and the text jumps at the brightest part of the object. Clamp before
  levelling, or paint the highlight out to mid-grey.
- **A light that is not side-on.** Falloff then encodes the lighting direction as much as the
  geometry, and the text shears. Blur harder and accept a weaker effect, or go synthetic.

For a clean cylinder the honest map is analytic, since horizontal position on a cylinder is
`R·sin(θ)`:

```bash
magick -size 1600x1 xc: \
       -sparse-color barycentric '0,0 black 1599,0 white' \
       -function sinusoid '0.5,-90,0.5,0.5' \
       -scale 1600x1600! mockups/cylinder-shading.png
```

Use the photo-derived map when the surface is *not* a clean cylinder: a tapered bottle, a tin
with a rolled rim, anything with a seam. That is where the derived map beats the formula.

## Isolating the label area

Anything in the frame that is not the curved surface — handle, backdrop, cap — still has grey
values, and will still displace text that overlaps it. Force it neutral with a mask:

```bash
magick mockups/mug-shading.png mockups/mug-mask.png \
       -alpha off -compose CopyOpacity -composite \
       -background '#808080' -alpha remove -alpha off \
       mockups/mug-shading.png
```

## Picking the amount

`displace_x` and `displace_y` are in pixels at the mockup's resolution, so they do not
transfer between a 1600px and a 3200px mockup. For a vertical cylinder set `displace_y` to 0
and leave the work to `displace_x`; the default `4` for `displace_y` is a small amount of
vertical give for surfaces that are not perfectly upright, and it should be 0 for a clean mug
band. Rough starting point: the horizontal offset needed at the edge of
the label is the difference between the flat label half-width and the foreshortened one, which
for a label spanning angle `θ` of a cylinder of radius `R` px is about
`R·(θ/2 − sin(θ/2))`. For a 120° label on a 400px-radius cylinder that is roughly 19px, so
`20x0`. Then look at it and adjust; the formula gets you the order of magnitude, not the value.

If the text visibly ripples, the map is not blurred enough. If it looks flat, check `mean`
before raising the amount — a map centred at 0.42 clips half its range.

## When arc is enough

`-distort Arc` bends the baseline along a circle in the image plane. It does not foreshorten:
letters at the ends stay full width. That is fine, and cheaper, when:

- the shot is straight on,
- the text band covers well under half the visible width of the object,
- the lighting across that band is fairly even,
- the surface is a plain cylinder with no seam or taper.

Reach for `displace` when the text spans most of the object's width and the ends need to
compress, when it has to cross a highlight or a shadow to stay believable, or when the surface
is not a cylinder at all. The two are not exclusive: arc for the baseline curve, then a small
displace pass for the foreshortening, is a common and good combination.

See `docs/modes.md` for how each mode is selected and `docs/troubleshooting.md` for the
failure modes.
