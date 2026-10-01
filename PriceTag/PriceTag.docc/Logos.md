# Logos

Where logo artwork lives and how it is placed.

## Folder layout

```
Logos.bundle/
  Brands/
  Features/
```

Filenames carry a version so a brand can have more than one logo.

## Loading

When a logo is first needed it is:

1. Decoded at a reduced size.
2. Cropped to its visible pixels, so padding in the source file doesn't shrink it on the sign.
3. Cached, with an index so redraws don't search the folder again.

## Placement

Wide logos go in the sign's header. Squarer ones go in the side gutter.
