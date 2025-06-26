<!-- repo path: mockups/README.md -->

# mockups/

Product images the labels get rendered onto, plus the greyscale shading maps that drive
`mode: "displace"`. **No binaries are committed here.** This file describes what to drop in
and how to make it; the directory ships with only a `.gitkeep`.

Keep everything generic (mug, bottle, tin). Nothing tied to a real brand or product line.

## Naming

```
mockups/mug.png            the product image            -> item field "mockup"
mockups/mug-shading.png    its greyscale displacement map -> item field "displace_map"
mockups/mug-mask.png       optional: white where the label may sit, black elsewhere
```

One stem per product, suffixed by role. `items.json` points at these paths directly, so the
stem is the only thing that has to stay stable.

## The product image

- PNG, 8-bit, sRGB.
- At least 1600px on the long edge. Distortion resamples, and downsampling a big render is
  the cheapest way to kill aliasing (see `docs/tuning.md`).
- Either opaque (product on a backdrop) or transparent background. Both work. Transparent is
  easier to drop onto another scene later; opaque keeps the original shadow, which the
  multiply composite in `lib/composite.sh` relies on to sell the result.
- Shoot or source it straight-on unless you intend to use `mode: "perspective"`. An
  unintentional tilt is the usual reason an arc looks slightly wrong and nobody can say why.
- Leave the label area clear of specular blowouts. Text cannot be composited into a region
  that is already at 100% white.

## The shading map

A displacement map is a control image, not a picture. Requirements:

- **Cropped to the area the label will cover**, not the whole product. `lib/displace.sh`
  stretches the map onto the label's box with `-resize WxH!`, so a full-frame map puts the
  handle and the backdrop inside the text's footprint. See `docs/displacement-maps.md`.
- **Greyscale.** ImageMagick reads red for horizontal offset and green for vertical; in a
  grey image they are equal, so `compose:args` is what separates the two axes.
- **Fully opaque.** Alpha in the map attenuates the displacement. Transparent corners produce
  a map that quietly stops working at the edges.
- **Mid-grey means no displacement.** `#808080` is the zero point. Darker pixels push one way,
  lighter the other, in proportion to the distance from mid.

### Deriving one from the product photo

The point of using the product's own shading is that the surface already tells you where it
curves: the falloff towards each side of a cylinder *is* the curvature.

```bash
# 1. luminance only, blurred so surface texture and print noise do not become displacement
magick mockups/mug.png -alpha off -colorspace Gray -blur 0x8 tmp.png

# 2. stretch to full range, then compress back around mid-grey so #808080 is the neutral
#    point and nothing pushes further than ~half the configured amount
magick tmp.png -auto-level +level 25%,75% mockups/mug-shading.png
```

`+level 25%,75%` is the step people skip. Without it the darkest pixel displaces by the full
`compose:args` value and the text tears at the edge of the mug.

Flatten anything that is not the curved surface, or the handle and backdrop will drag the
text sideways:

```bash
# force everything outside the mask to neutral
magick mockups/mug-shading.png mockups/mug-mask.png \
       -alpha off -compose CopyOpacity -composite \
       -background '#808080' -alpha remove -alpha off \
       mockups/mug-shading.png
```

### Synthetic maps

If the product photo is lit too flatly to derive anything useful, a horizontal cosine is a
fair model of a cylinder seen side-on:

```bash
magick -size 1600x1 xc: -sparse-color barycentric '0,0 black 1599,0 white' \
       -function sinusoid '0.5,-90,0.5,0.5' \
       -scale 1600x1600! mockups/cylinder-shading.png
```

Check any map before trusting it:

```bash
magick mockups/mug-shading.png -format 'mean=%[fx:mean] w=%w h=%h alpha=%A\n' info:
```

`mean` should sit near `0.5`, `w`/`h` should match the product image, `alpha` should be
`False`.

## What not to commit

Renders, `.tmp.png` intermediates, and anything from `out/`. See `.gitignore`.
