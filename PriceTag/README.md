# PriceTag

An iOS app for generating printable retail sign sheets. Four signs per US Letter
page, laid out for laminating and cutting.

Built for a single motorcycle dealership, replacing a Word-document workflow.

## The problem

Price signs for helmets, apparel and parts were made by hand in Word — one
document per batch, manually formatted, four signs to a page. Every new sign
meant duplicating a text box and retyping around it. Type sizes drifted,
layouts diverged, and nothing was reusable.

## The approach

The app is built around one idea: **the sign you see on screen and the sign that
prints are the same view.**

`SignFaceView` is authored once at true print dimensions — 7.5 × 2.375 inches,
or 540 × 171 points at 72 dpi. On screen it is scaled down to fit whatever
container it appears in. In the PDF it is drawn at 1:1. There is no second
layout implementation to keep in sync, so the preview cannot lie.

The sign width was chosen to make the page arithmetic exact: US Letter is
612 points wide, half-inch margins take 72, leaving exactly 540.

### Data model

A single `Sign` struct holds every field any sign type might use. `SignType`
decides which ones get drawn and which the editor asks for. Six sign types,
one struct — adding a type is a switch case, not a new model.

```
SignType: regular · sale · clearance · used · apparel · parts
```

Prices are stored as `String`, not `Double`. The app records what should appear
on the sign; it does no arithmetic, and a string keeps `1178.95` from becoming
`1178.9499999`.

Type sizes are computed from content length rather than hard-coded, so a long
model name steps down a tier instead of overflowing its column.

### PDF generation

`ImageRenderer.render` draws the SwiftUI view directly into a
`UIGraphicsPDFRenderer` context as vectors. Text stays text — it prints sharp
at any size and the files stay small. PDF contexts are y-down while the view
renderer is y-up, so each sign is translated to the bottom of its slot and
drawn with a negative y scale.

`ShareLink` then provides AirDrop, Print, Save to Files and Mail with no
additional code.

## Screens

| Screen | Purpose |
|---|---|
| Pages | Saved sheets, each with a thumbnail of its four slots |
| Page composer | The 4-up sheet; tap a slot to edit, export from the bottom bar |
| Type picker | Bottom sheet — choosing a type determines the editor's fields |
| Sign editor | Live preview pinned above grouped, type-specific fields |
| Print preview | The full Letter sheet with margins, before sharing |
| Library | Saved signs, reusable across pages |
| Templates | Pre-configured starting points per sign type |
| Logos | Per-brand artwork; labelled placeholders until a PNG is supplied |

## Source layout

```
Models.swift          Sign, SignPage, SignType — no UI
Store.swift           ObservableObject, JSON persistence to Documents
SignFaceView.swift    The printed sign; used on screen and in the PDF
PDFExport.swift       Four signs onto a Letter page
Theme.swift           Colours, type scale, shared controls
RootView.swift        App shell and tab bar
PagesScreen.swift     Pages list
PageComposer.swift    The 4-up page
TypePicker.swift      New-sign sheet
SignEditor.swift      Editor with live preview
PrintPreview.swift    Full-sheet preview
OtherTabs.swift       Library, Templates, Logos
```

## Building

Requires Xcode 15+ and iOS 16.0 as the minimum deployment target. No
dependencies, no package manager, no build configuration.

1. Create a new iOS App project — SwiftUI, Swift, Storage: None
2. Delete the template's `ContentView.swift` and `PriceTagApp.swift`
3. Add all twelve source files to the target
4. Set Minimum Deployments to iOS 16.0
5. ⌘R

Type uses the system font at the intended weights and sizes. To use Space
Grotesk, add the `.ttf` files, list them under *Fonts provided by application*
in the target's Info tab, and change the single `pt()` function in
`Theme.swift` — it controls every label in the app.

## Design notes

Persistence is one JSON file in the Documents directory. There is no database,
no sync, and no account, because there is one user on one device. The
`ObservableObject` writes on every mutation via `didSet`.

Formatting rules live on the model rather than inside views. That boundary is
what would make a later Android version a port rather than a rewrite: the
struct, the type rules and the page arithmetic contain no UIKit.

Pages with fewer than four signs repeat what they have to fill the sheet, since
a partially-printed page wastes laminate.

## Status

In use. Built and installed via Xcode with a personal team; not distributed.
