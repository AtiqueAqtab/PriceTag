# How signs are drawn

One view, sized for print, used everywhere.

## Overview

``SignFaceView`` is laid out at 540 × 171 points, which is 7.5 × 2.375 inches at 72 dpi. On screen it is scaled to fit its container. In the PDF it is drawn at 1:1.

A US Letter page is 612 points wide. Half-inch margins take 72, leaving exactly 540 for the sign.

## Sign types

Every sign uses the same ``Sign`` struct. ``SignType`` decides which fields the editor shows and which ones get drawn:

| Type | Adds |
|---|---|
| Regular | Price |
| Sale | Was price, now price, % off |
| End of season | END OF SEASON banner |
| Part with fitment | Part number, compatible bikes, optional PRE-OWNED banner |
| Boots & apparel | Sizes |

## Text sizing

Font sizes step down based on text length, so a long model name shrinks rather than overflowing its column.

## Logos and banners

Each logo prints at its own size, as large as its box allows (brands 190 × 42 pt, feature logos 100 × 28 pt, or 100 × 36 pt for near-square marks such as Gore-Tex), with no empty space around the artwork. Long banners such as END OF SEASON break over two lines.

The left column is 262 pt wide. The brand logo and the feature logos always print together in the header row. By default the banner (SALE, END OF SEASON) joins them there, and the brand logo shrinks to make room, down to 62% of its size. Only when that is not enough does the banner move to the right column, where it joins the % OFF flag as one two-colour tag, or sits beside the WAS price if there is no flag. A banner prints on one line where it fits; END OF SEASON is too wide for the space beside the flag, so it breaks over two lines there, the same height as the flag. The feature logos never move: if the brand logo still has to shrink further to fit them, it does, but never below 40%.

The editor has a Banner picker set to Auto, By brand, or Right. Auto follows the rules above. The choice is stored on the sign as `bannerSpot`, and a sign saved without it decodes as Auto.

Marks in the header row are 16 pt apart. The brand logo shrinks to keep that gap, and the gap only tightens (to a minimum of 6 pt) when the brand is already at its smallest. A banner beside the WAS price is centered in its space. The % OFF flag never wraps or truncates. Marks beside the WAS price can be taller than the price row, in which case the price gives back that much height.

## Vertical placement

Every sign starts its content at the same height: 10 pt below the usual padding and 12 pt of space under the header row, with the header row at least 36 pt tall so the product name sits at the same height whatever the brand logo's shape. A note stays at the bottom. The right column starts level with the header row whenever the sign has a % OFF flag or a WAS price, so the flag lines up with the brand logo and banner. A bare price is centered in its column instead.

## Prices

Prices are stored as `String`, which keeps `1178.95` from becoming `1178.9499999`. The only arithmetic is the editor's suggestion for the third of Was, % off and Price, which ``PriceSuggestion`` does in `Decimal` and hands back as text.

## Fitment tags

A Parts sign lists what it fits as tags in a full-width strip along the bottom, under a rule. Each row of the fitment editor is one tag: the models in bold, then the years, so a row holding "R 1250 GS" and "R 1250 GS Adventure" (short name "GSA") for 2019–2024 prints as "R 1250 GS / GSA 2019–2024". `FitmentLayout` wraps the tags into the rows the sign has room for, steps the type from 11 to 9 pt, and only then replaces the rest with "+N more". The editor asks the same layout whether anything overflows, so its warning always matches the print. The note line sits above the strip, under the part number.

Signs saved with plain fitment lines still print them, one tag per line. Opening one in the editor turns each line into a row.

## Landscape sheets

Any sheet of a page can be switched to Landscape while all its signs are Parts signs, so one page can mix standard sheets with landscape ones. A landscape sheet is sideways (792 × 612 points) and holds two signs, each 720 × 264 points. The layout is the standard sign made 27 points taller (540 × 198) and drawn at 4/3, which gives the fitment strip an extra row. Each sign remembers whether it sits on a landscape sheet, and `sheetChunks` walks a page's signs in order, giving a run of landscape signs sheets of two and a run of standard signs sheets of four. Standard and landscape sheets can go into one PDF; each gets its own page size.
