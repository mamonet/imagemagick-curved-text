<!-- repo path: docs/modes.md -->

# Modes

Four ways to get a flat label onto a curved surface. They are not ranked; they solve
different problems, and the common mistake is reaching for the most elaborate one first.

Every mode shares the same three steps: `label_render` lays out the type flat and
transparent, the mode bends it, `composite_place` puts it back under the product's lighting.
Only the middle step differs.

## At a glance

| | `arc` | `perspective` | `displace` | `cylinderize` |
|---|---|---|---|---|
| Bends the baseline | yes | no | yes | yes |
| Foreshortens the ends | no | yes, linearly | yes, from the map | yes, geometrically |
| Follows local shading | no | no | **yes** | no |
| Needs an extra asset | no | no | a shading map | no |
| Needs an external tool | no | no | no | **yes** |
| Cost | trivial | trivial | one extra pass | slowest |

## `arc`

`-distort Arc`, via `arc_apply`. Bends the label along a circle in the image plane.

**Fields:** `arc_degrees` (required), `arc_rotate` (optional).

**Use it when** the shot is straight on, the text band covers well under half the object's
visible width, and the surface is a plain cylinder. This is the default answer for a mug
band, a lid rim, or a line of type curving over the shoulder of a bottle.

**Trade-off:** Arc bends but does not foreshorten. Letters at the ends of the curve stay full
width even though the real surface there is turning away from the camera. Under about 140° of
wrap nobody notices; past that the ends look stretched and no amount of tuning fixes it,
because the operator is not modelling depth at all.

Arc opens **downwards** by default. `arc_rotate: 180` (or `arc_apply_below`) flips it for text
on the lower half of an object. Getting this backwards is the most common first-run surprise.

## `perspective`

`-distort Perspective`, via `perspective_apply`. Maps the label's four corners onto four
destination points measured off the mockup.

**Fields:** `corners.tl`, `corners.tr`, `corners.br`, `corners.bl`, each an `[x, y]` pair. All
four required, all eight numbers required.

**Use it when** the camera is off-axis: a box lid seen at an angle, a flat panel on a tilted
product, a label on a face that recedes. It is the only mode that handles the *camera* rather
than the *surface*.

**Trade-off:** it is a plane-to-plane transform, so the result is perfectly flat. There is no
curvature in it at all. A tilted cylinder needs perspective *and* a curve, which means running
the label through `arc` or `displace` first and this second, not choosing between them.

Note the placement difference: the destination corners are absolute mockup coordinates, so
this mode composites at the origin via `composite_place_absolute` and ignores
`center_x`/`center_y`. Supplying those as well is harmless but does nothing.

## `displace`

`-compose displace` with a greyscale map, via `displace_apply`. The map says how far to push
each pixel; the product's own shading supplies the map.

**Fields:** `displace_map` (required), `displace_x` (default 10), `displace_y` (default 4).

**Use it when** the surface is not a clean cylinder, when the text spans enough of the object
that the ends genuinely need to compress, or when it has to cross a highlight, a seam, or a
dent and still look printed. This is the mode that makes the result read as physical, because
local brightness deviations become local offsets: the text kinks over a rolled tin rim the way
real ink does.

**Trade-off:** it needs an asset you have to produce and keep in sync with the mockup, and it
fails quietly rather than loudly. A map that is not cropped to the label's footprint, not
centred on mid-grey, or not blurred enough produces text that is bent along the wrong curve
and looks *almost* right, which is harder to diagnose than an obvious error.

Full treatment in `docs/displacement-maps.md`.

## `cylinderize`

Hands the prepared label to Fred Weinhaus' `cylinderize.sh`, via `cylinderize_apply`.

**Fields:** `cyl_radius`, `cyl_length`, `cyl_wrap` (all required); `cyl_pitch`, `cyl_roll`,
`cyl_yaw`, `cyl_offset_x`, `cyl_offset_y` (optional, default 0).

**Use it when** the label wraps far enough round that both edges foreshorten and you want
actual 3D geometry rather than an approximation — a tin, a can, a wide wrap on a jar. It is the
only mode that models the cylinder as a solid, so the parameters are physical (radius, length,
wrap angle, camera attitude) rather than tuned by eye.

**Trade-off:** an external dependency this repo does not and must not bundle.
`cylinderize.sh` ships under Fred Weinhaus' own licence (free for non-commercial use,
permission required otherwise) from https://www.fmwconcepts.com/imagemagick/ . You download
it, read the licence in its header, and put it on `PATH` yourself, or point at it with
`CYLINDERIZE_BIN`.

`cylinderize_require` fails with that instruction if it is absent. The other three modes do
not depend on it, so a repo without it is fully usable — you just cannot select this mode.
Its flag names have also changed between releases; if it errors on an option, adjust the args
array in `lib/cylinderize.sh` rather than reshaping the JSON.

## Choosing

- Straight-on shot, modest curve → **arc**. Try this first; it is right more often than it
  looks like it should be.
- Off-axis flat panel → **perspective**.
- Real surface, hard lighting, or anything that is not a textbook cylinder → **displace**.
- Wide wrap on a can or tin, and you are willing to install one script → **cylinderize**.

`--mode` overrides every item for a run, which is the cheap way to compare two of these on the
same item before committing a value to `items.json`:

```bash
./curve-text.sh items.json out-arc/      --mode arc --only 1
./curve-text.sh items.json out-displace/ --mode displace --only 1
```

Note that an override still has to satisfy that mode's required fields, so overriding to
`displace` fails on an item with no `displace_map`.
