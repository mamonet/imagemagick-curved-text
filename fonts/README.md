<!-- repo path: fonts/README.md -->

# fonts/

Drop the font files used by `items.json` here. **No fonts are committed.** The directory
ships with a `.gitkeep`; you fetch what you need.

## Suggested open-licence fonts

All SIL Open Font License 1.1 unless noted, all redistributable, all with the weights you
actually want for product labels.

| Font | Use | Source |
|------|-----|--------|
| DejaVu Sans / Serif | what `items.json` references; already installed on most Linux boxes | https://dejavu-fonts.github.io/ (Bitstream Vera licence, permissive) |
| Inter | neutral UI/label sans, wide weight range | https://github.com/rsms/inter/releases |
| Source Sans 3 | quieter sans, good at small sizes | https://github.com/adobe-fonts/source-sans/releases |
| Libre Baskerville | serif, high contrast, reads well curved | https://github.com/impallari/Libre-Baskerville |
| Oswald | condensed caps, fits a narrow arc | https://github.com/googlefonts/OswaldFont |
| JetBrains Mono | mono, for batch/lot codes on tins | https://github.com/JetBrains/JetBrainsMono/releases |

Fetch static `.ttf` or `.otf` files, not variable fonts. ImageMagick renders variable fonts at
their default instance and ignores the axes, so a `Inter[opsz,wght].ttf` will silently come
out at Regular whatever weight you meant.

```bash
curl -fsSL -o /tmp/inter.zip \
  https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip
unzip -j /tmp/inter.zip 'extras/ttf/Inter-SemiBold.ttf' -d fonts/
```

The shipped `items.json` points at `fonts/DejaVuSans-Bold.ttf`, `fonts/DejaVuSerif.ttf` and
`fonts/DejaVuSans.ttf` because DejaVu is present almost everywhere. Symlink or copy them in:

```bash
cp /usr/share/fonts/truetype/dejavu/DejaVu{Sans-Bold,Sans,Serif}.ttf fonts/
```

## Licence note

The OFL permits redistribution, including bundled inside another project, provided the
licence file travels with the font and the font is not sold on its own. If you commit a font
here, commit its `OFL.txt` next to it:

```
fonts/Inter-SemiBold.ttf
fonts/Inter-OFL.txt
```

The OFL also forbids using the reserved font name for a modified copy. If you subset or
re-hint a font, rename it.

Do not commit anything from a foundry licence, Adobe Fonts, or a system font directory. Those
are licensed to a machine or a person, not to a repository.

## Why the font path is per-item

`font` is a field on each item in `items.json` rather than a global setting, for three
reasons:

1. **One batch, several products.** A mug wordmark and a tin's batch code are not the same
   typeface. Making the font global forces one run per typeface and defeats the batch.
2. **Reproducibility.** A path in the data means the render is pinned to a specific file that
   can be committed or fetched. A family name like `"Inter"` resolves through fontconfig,
   which gives a different result on a different machine, and a *different result on CI*.
   `lib/validate.sh` checks the path exists before any render starts for exactly this reason.
3. **Curvature is font-dependent.** How much `arc_degrees` a string can take before it looks
   bent rather than wrapped depends on its x-height and stroke contrast. Tying the font to
   the item keeps that tuning next to the value it affects.

A bare family name still works if fontconfig can resolve it — ImageMagick accepts either —
but paths are what this repo assumes. `magick -list font` shows what is resolvable locally.
