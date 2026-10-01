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
| Clearance | CLEARANCE banner |
| Part with fitment | Part number, compatible bikes, optional PRE-OWNED banner |
| Boots & apparel | Sizes |

## Text sizing

Font sizes step down based on text length, so a long model name shrinks rather than overflowing its column.

## Prices

Prices are stored as `String`. The app never does arithmetic on them, and storing text keeps `1178.95` from becoming `1178.9499999`.
