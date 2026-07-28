# Ledge brand

The mark is called **the Step**. One solid form with a single step cut out of it, and one thought resting in the step. It is a rock ledge, a shelf in section, and the letter L, in the same shape.

The rose dot is the whole product in one gesture: a thought set down somewhere safe, at rest, not pending. It is never a badge, never a count, never a state.

Everything here inherits `design/tokens.json`. No colour is introduced that is not already in the product.

---

## Construction

The symbol is drawn on a **96 unit grid**, which divides cleanly by the product's 4pt grid.

| Element | Geometry |
|---|---|
| Step body | Outer corners radius 6, inner corner radius 5 |
| Bounding box | x 22 to 74, y 20 to 76 (52 x 56 units) |
| Optical centre | 48, 48 — the grid centre, so the mark centres by construction |
| Dot | r 7, centred at 59, 41 — tangent to the top face of the shelf |

**The one deliberate inconsistency.** In colour, the dot rests in contact with the shelf. In monochrome (menu bar template, tinted icon, single-colour print) the dot is lifted **3 units** to centre 59, 38. Without the lift the dot merges into the shelf below roughly 24px and the mark loses its counterweight. Contact is the intent; the lift preserves the intent when colour cannot.

---

## Colour

Tokens only. Names match `design/tokens.json` keys.

| Context | Ground | Step body | Dot |
|---|---|---|---|
| Light | `bg` `#F7F5F2` | `text` `#1C1B1D` | `accent` `#BD4753` |
| Dark | `bg` `#1C1B1D` | `text` `#F7F5F2` | `accent` `#E78892` |
| Tinted (iOS) | `#000000` | `#B4B4B4` | `#FFFFFF` |
| Template (menu bar) | transparent | black, alpha only | black, alpha only |

The rose is an accent, never a ground. A full-bleed rose tile reads as an alert, which breaks the product's own "no red states anywhere" rule the moment it lands on a Home Screen.

---

## Clear space and minimum sizes

**Clear space** on all four sides equals the **diameter of the dot** (14 grid units, or 14.6% of the symbol's height). Nothing enters that margin, including the edge of a container.

| Asset | Minimum |
|---|---|
| Symbol, colour | 16 px |
| Symbol, monochrome template | 18 px (drawn for it) |
| Horizontal lockup | 96 px wide |
| Stacked lockup | 64 px wide |

Below 24px the mark should use the monochrome construction with the dot lift, even when colour is available.

---

## Files

```
design/
  logo/
    ledge-symbol.svg                  symbol, light
    ledge-symbol-dark.svg             symbol, dark
    ledge-symbol-tile-light.svg       symbol on a rounded paper tile
    ledge-symbol-tile-dark.svg        symbol on a rounded night tile
    ledge-symbol-mono-black.svg       one colour, dot lifted
    ledge-symbol-mono-white.svg       one colour, dot lifted
    ledge-wordmark.svg                wordmark only, outlined strokes
    ledge-wordmark-dark.svg
    ledge-lockup-horizontal.svg       primary lockup
    ledge-lockup-horizontal-dark.svg
    ledge-lockup-stacked.svg          secondary lockup
    ledge-lockup-stacked-dark.svg
    menubar-template@3x.png           reference render of the 18pt glyph
  web/
    favicon.svg, favicon.ico, favicon-16/32/48.png
    apple-touch-icon.png (180)
    icon-192.png, icon-512.png, icon-512-maskable.png
    og-1200x630.png (1200x630)
  github/
    social-preview-1280x640.png (1280x640)     upload in repo Settings > Social preview
    avatar.png (400x400)
    readme-banner-light-1400x400.png, readme-banner-dark-1400x400.png (1400x400)

apps/mac/Resources/
  Ledge.iconset/                      10 PNGs, compiled to .icns at build time
  MenuBarIconTemplate.png @2x @3x     status item, pure alpha

apps/ios/Sources/Assets.xcassets/AppIcon.appiconset/
  AppIcon-light.png, AppIcon-dark.png, AppIcon-tinted.png (1024 each)

apps/ios/WatchSources/Assets.xcassets/AppIcon.appiconset/
  AppIcon-watch.png (1024, drawn inside the circular safe area)
```

The wordmark is **outlined geometry, not live text**. There is no font dependency and no licence to track.

---

## Do not

1. Do not stretch, rotate, or shear the mark.
2. Do not recolour outside the tokens above.
3. Do not add shadows, gradients, glows, or strokes.
4. Do not drop the dot. Without it the mark is a bare letter and a placeholder.
5. Do not rebuild the wordmark in live type.
6. Do not use the rose as a background.
7. Do not put a count, badge, or state on the mark. Ever.

---

## Rebuilding the assets

Every file above is generated from the same 96 unit geometry. If the mark changes, regenerate rather than hand-editing individual sizes.

The Mac `.icns` is built by `scripts/build-mac.sh` from `apps/mac/Resources/Ledge.iconset` at build time, so the repository holds PNGs and never a binary icon blob.

*Mark designed 2026-07-27. Built by Claude (Anthropic), directed by Shashank Karpal.*
