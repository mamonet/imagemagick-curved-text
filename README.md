# imagemagick-curved-text

A small Bash tool that renders text onto curved and cylindrical product mockups with ImageMagick,
driven from a JSON file. Early scaffold.

One command turns a list of items into a folder of finished images, with each item's text, font,
position, and curvature read from data rather than nudged by hand.

The point is the part that usually looks wrong: making the text read as *wrapped around* the surface,
picking up its curvature and lighting, instead of pasted on flat.

```bash
./curve-text.sh items.json out/
```

Requires ImageMagick 7 (`magick`) or 6 (`convert`), `jq`, and Bash.
