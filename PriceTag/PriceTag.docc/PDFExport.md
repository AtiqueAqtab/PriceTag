# PDF export

How four signs end up on a page.

## Overview

`exportPDF(page:signs:)` creates a `UIGraphicsPDFRenderer` at 612 × 792 points and stacks four signs between half-inch margins, spacing them evenly.

Each sign is drawn with `ImageRenderer.render`, which writes vector content into the PDF context. Text stays as text, so it prints sharp and files stay small.

## Coordinate flip

The two coordinate systems are flipped relative to each other. Each sign is translated to the bottom of its slot and drawn with a negative y scale so it comes out upright.

## Sharing

The PDF is written to the temporary directory and handed to `ShareLink`, which provides AirDrop, Print, Save to Files and Mail.

## Landscape sheets

A sheet with two slots is a landscape sheet. `exportPDF` starts that PDF page at 792 × 612 points and draws two 720 × 264 point signs between half-inch margins. Packing keeps landscape and standard signs on sheets of their own.
