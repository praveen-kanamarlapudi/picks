# Keep

A native macOS app for a couple or family to shortlist stills from a photographer’s dump and export camera IDs.

Point it at a folder. Walk stills. Build **one shortlist**. Export IDs the photographer can search (`M3F03442`, `AKHI0355`, `_S9A7954`).

It is not an editor, not a gallery, and not Photo Mechanic.

## Requirements

- macOS 14+
- Xcode 16+ (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```sh
make build      # Release .app under .build/
make test
make install    # copy to /Applications
make dmg        # dist/Keep.dmg
```

Or generate the Xcode project and open it:

```sh
xcodegen generate
open Keep.xcodeproj
```

## Product locks

- Stills only. Videos and video thumbs are ignored.
- Two lists: **All** and **Shortlist**.
- Same camera stem in sibling `JPG/` + `RAW/` (or the same folder) is **one photo**.
- Canonical file is **RAW when it exists**; JPEG only if there is no RAW.
- Loupe quality matches macOS Preview (ImageIO / Quick Look on the canonical file).
- Marks live in local SQLite. Keep does not write into the photo tree except when you explicitly move a photo to Trash.
- Export: `photo-ids.txt` + `shortlist.csv`, plus Copy IDs.

Locked spec: [`docs/requirements.md`](docs/requirements.md).  
Clickable UX mockup: [`design/keep-screens.html`](design/keep-screens.html) (placeholder tiles; family photos are not in this repo).

## Privacy

This repository is **source only**. It does not include photographer dumps, catalogs, shortlists, or design stills from a real event.

Local catalogs stay on the Mac:

```
~/Library/Containers/app.keep.mac/Data/Library/Application Support/Keep/<event-id>/
```

`make backup` writes snapshots to `backups/`, which is gitignored. Do not add dumps, `.sqlite` catalogs, or `folder.bookmark` files to git.
