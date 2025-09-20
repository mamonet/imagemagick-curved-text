<!-- repo path: docs/troubleshooting.md -->

# Troubleshooting

Symptom first, then the cause. Run with `--verbose` before anything here: it echoes every
ImageMagick command with `%q` quoting, so you can paste the failing line into a shell and
bisect it by hand.

## `convert: command not found`, or `convert` does something unrelated

IM7 renamed the tool to `magick` and IM6's `convert` is deprecated. `lib/im.sh` prefers
`magick` and falls back to `convert`, so it works on both, but note:

- On Windows, `convert.exe` is the NTFS filesystem conversion tool. If `magick` is missing you
  will invoke that instead and get something alarming rather than an image. Install IM7.
- IM7 still ships a `convert` shim on many distributions, which prints a deprecation warning to
  stderr. Harmless; it is not the cause of your problem.

Check which one was picked:

```bash
magick -version || convert -version
```

## IM6 and IM7 disagree about a command

The differences that actually bite this repo:

| | IM6 | IM7 |
|---|---|---|
| entry point | `convert`, `identify`, `composite` | `magick`, `magick identify` |
| `-compose` before `-composite` | required | required |
| `%[fx:...]` escapes | supported | supported |
| operator order | strictly left-to-right | strictly left-to-right |
| `-define compose:args=` | supported | supported |
| default `-alpha` handling on PNG | more permissive | stricter about `-alpha off/set` |

Most "works on my machine" reports here are the last row: IM7 wants an explicit
`-alpha set` before an operation that needs a transparency channel, where IM6 would create one
for you. If a label comes out with a black rather than transparent background on one machine
only, add `-background none -alpha set` before the distortion.

Never mix them in one pipeline. `lib/im.sh` exports a single `$IM` for the whole run.

## `no decode delegate for this image format` / `not authorized`

Two different problems that look alike.

**Missing delegate** — the build has no support for the format:

```bash
magick -list format | grep -i -E '^ *(png|jpe?g)'
```

Each line should show `rw-` or similar. `png` missing means libpng was not compiled in;
reinstall from your package manager rather than a minimal container image.

**Policy block** — the format is supported but `policy.xml` forbids it. Common in Docker
images and on Debian/Ubuntu after the Ghostscript advisories:

```bash
magick -list policy
```

Look for a `<policy domain="coder" rights="none" pattern="PNG"/>` style line. Fix the policy
file; do not work around it by converting through another format.

## `unable to read font` / the wrong font renders

ImageMagick resolves `-font` in two ways: as a filesystem path, or as a fontconfig family
name. A typo in a path is an error; a typo in a family name silently falls back to a default,
which is worse.

```bash
magick -list font | grep -i inter          # what fontconfig can resolve
magick -list configure | grep -i freetype  # is freetype even compiled in
```

`lib/validate.sh` checks that a `font` value containing a `/` exists on disk before any render
starts. A bare family name cannot be checked that way, which is one reason this repo prefers
paths (see `fonts/README.md`).

Variable fonts are the other trap: ImageMagick renders the default instance and ignores the
weight axis, so `Inter[wght].ttf` comes out Regular no matter what you intended. Use static
instances.

## `-distort Arc` fills the frame with background

Arc expands the canvas and, by default, asks the virtual-pixel setting what lies outside the
source. The default is `edge`, which smears the border pixels across the new area — usually
producing a solid rectangle of colour.

```bash
# wrong
magick label.png -distort Arc 120 out.png
# right
magick label.png -background none -virtual-pixel none -distort Arc 120 out.png
```

`-virtual-pixel none` (or `transparent`) plus `-background none`. Both, and both *before* the
`-distort`. Order matters: settings placed after the operator do not apply to it.

If the output is transparent but enormous, that is correct — Arc grows the canvas to fit the
curve. `+repage` after it, and let `lib/composite.sh` place it.

## The curve goes the wrong way

`-distort Arc` opens downwards by default. For text on the lower half of an object, pass the
rotate argument: `-distort Arc "120 180"`. See `docs/tuning.md`.

## Displacement did nothing, or displaced only part of the text

In order of likelihood:

1. **Framing.** `displace_prepare_map()` resizes the whole map onto the label's box with
   `-resize WxH!`. Hand it the full mockup shading and the entire product is squashed into
   the text's footprint, so the offsets come from the wrong part of the curve. Crop the map to
   the region the label covers. (Raw ImageMagick, without that helper, does something worse:
   it composites at `+0+0` with no scaling and no warning, and only the overlap is displaced.)
2. **Map is not centred on mid-grey.** `#808080` is the zero point; a map whose mean is 0.2
   shifts everything bodily sideways instead of bending it.
3. **Map has an alpha channel.** Transparency attenuates the displacement. `-alpha off`.
4. **`displace_x` is `0` or omitted.** `compose:args` defaults to no displacement, not to a
   sensible value.
5. **The map is colour, not grey.** Red drives X and green drives Y independently; a colour
   map will do something, just not what you meant. `displace_prepare_map()` forces
   `-colorspace Gray`, so this only bites when calling ImageMagick directly.

Check all five at once:

```bash
magick identify -format '%f %wx%h alpha=%A mean=%[fx:mean] grey=%[fx:mean.r==mean.g]\n' \
       label.png mockups/mug-shading.png
```

Dimensions must match on both lines. For the map, `alpha=False`, `mean` near `0.5`, `grey=1`.

Full detail in `docs/displacement-maps.md`.

## `cylinderize.sh: not found`

`cylinderize.sh` is Fred Weinhaus' script. **It is not bundled here and must not be** — it
ships under his own licence, which permits personal/non-commercial use and requires contacting
him otherwise. This repo only calls it if it is already on your `PATH`.

Get it from his site (`https://www.fmwconcepts.com/imagemagick/`), read the licence header in
the file itself, then:

```bash
chmod +x cylinderize.sh
mv cylinderize.sh ~/bin/          # anywhere on PATH
command -v cylinderize.sh         # should print the path
```

If you keep it somewhere off `PATH`, point the wrapper at it instead:

```bash
CYLINDERIZE_BIN=/opt/fmw/cylinderize.sh ./curve-text.sh items.json out/
```

If it is found but errors on an option, his flag names have changed between releases. Run
`cylinderize.sh -h` and adjust the `args` array in `lib/cylinderize.sh`; do not reshape the
JSON to match.

`lib/cylinderize.sh` in this repo is a thin wrapper that locates it and passes the item's
radius, perspective and offset. If it is absent, that mode fails with a clear message and the
other three modes are unaffected — nothing else in the tool depends on it.

Note the name collision: `lib/cylinderize.sh` (this repo, the wrapper) and `cylinderize.sh`
(Fred's, on `PATH`) are different files. The wrapper resolves the external one via
`command -v`, so it will not accidentally call itself.

## Text is jagged along the curve

Rendering at final size and distorting once. Render the label 3–4× oversized, distort, then
downsample with `-filter Lanczos`. See `docs/tuning.md`.

## Text disappears on the dark side of the object

The composite defaults to `multiply`, which cannot lighten. Raise the item's `level_floor`
(the black-point clamp, default 18) or set `blend` to `screen` for light ink on a dark
product. See `docs/tuning.md`.

## `jq: command not found`

Required, not optional. `apt install jq`, `brew install jq`, `dnf install jq`. The tool exits
before touching any image if it is missing.

## A render changed and nobody knows why

Read `out/manifest.tsv` from the run. It records the ImageMagick version, the items file, and
every per-item parameter, one row per output. Compare rows rather than re-deriving values.
