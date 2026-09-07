# Picks — Implementation Plan

Status: Ready to build  
Source of truth for *what*: [`requirements.md`](requirements.md)  
Source of truth for *how / order*: this file  
UX reference: [`../design/picks-screens.html`](../design/picks-screens.html)

First vertical slice: **Phases 0–3**. Do not start Home / Export / Grid until that loop is right.

---

## Goal

A native Mac app that opens a photographer dump, treats **RAW as the photo whenever it exists**, lets a couple build one shortlist, persists marks locally, and exports camera IDs.

Reference tree: a nested photographer dump (Google Drive File Stream or a local folder), typically `01 Engagement/`, `02 Bride Making/`, `03 Wedding/`, each with `Candid Photos` / `Traditional Photos` and sibling `JPG/` + `RAW/`.

---

## Stack

| Piece | Choice |
|---|---|
| OS | macOS 14+ |
| UI | SwiftUI, AppKit only where required (key monitor, NSOpenPanel, bookmarks) |
| Language | Swift 6 |
| Catalog | SQLite via GRDB |
| Decode | ImageIO + QuickLookThumbnailing (Preview path). Not LibRaw demosaic |
| Types | UniformTypeIdentifiers: JPEG, `com.sony.raw-image`, `com.canon.cr2-raw-image` |
| Sandbox | On. User-selected file read. Security-scoped bookmarks to reopen |
| Not | Electron, Tauri, web wrapper |

---

## Repo layout

Create an Xcode app target at the repo root (or `Picks/`). Leave existing `design/` and `docs/` where they are.

```
docs/requirements.md
docs/plan.md
design/picks-screens.html

Picks.xcodeproj
Picks/
  App/
    PicksApp.swift
    AppModel.swift              # open event, routing: home / scan / review
    SupportPaths.swift          # Application Support / event-id
  Catalog/
    Database.swift              # GRDB migrator
    Photo.swift
    Mark.swift
    Session.swift
    EventBookmark.swift
  Indexer/
    Indexer.swift               # walk, classify, pair, persist
    PathRules.swift             # include / exclude
    Pairing.swift               # stem + RAW-default canonical
    DuplicateIngest.swift       # optional _duplicate_report
  Viewer/
    ReviewView.swift            # full-bleed + overlays
    PhotoCanvas.swift           # ImageIO/QL, thumb → full
    FilmstripView.swift
    OverlayHeader.swift
    OverlayKeys.swift
    ZoomOverlay.swift
  Library/
    EventHomeView.swift         # Phase 4
  Shortlist/
    MarkStore.swift
    UndoStack.swift
    Filters.swift
  Export/
    Exporter.swift              # Phase 5
  Resources/
    Fixtures/MiniDump/          # unit-test tree
PicksTests/
  PathRulesTests.swift
  PairingTests.swift
  IndexerTests.swift
  MarkStoreTests.swift
```

Bundle id: `app.picks.mac` (changeable). Product name: **Picks**.

---

## Data

`~/Library/Application Support/Picks/<event-id>/`

- `catalog.sqlite`
- `thumbs/` (generated, disposable)
- `folder.bookmark`

`event-id` = stable hash of the bookmark’s resolved path, or a UUID stored next to the bookmark. Re-opening the same folder must reopen the same catalog.

### Tables

**photos**

- `id` INTEGER PK
- `photo_id` TEXT           — camera stem (`M3F03442`)
- `ceremony` TEXT           — `01 Engagement`
- `style` TEXT              — Candid / Traditional / …
- `camera` TEXT             — `M3F`, `AKHI`, …
- `canonical_path` TEXT     — relative to event root
- `canonical_kind` TEXT     — `raw` | `jpeg`
- `jpeg_path` TEXT NULL
- `raw_path` TEXT NULL
- `hidden_dup` INTEGER      — 1 if exact extra copy
- `file_size` INTEGER
- UNIQUE `(ceremony, photo_id)`

**marks**

- `photo_pk` INTEGER FK
- `shortlisted` INTEGER
- `passed` INTEGER
- `note` TEXT NULL
- `updated_at` TEXT
- PRIMARY KEY (`photo_pk`)

**session**

- `last_photo_pk` INTEGER NULL
- `view` TEXT               — `all` | `shortlist`
- `filter` TEXT             — `everything` | `left` | `passed`
- `ceremony` TEXT

**scan_meta**

- `stills`, `canonical_raw`, `jpeg_only`, `dups_hidden`, `video_thumbs_skipped`, `videos_ignored`
- `last_indexed_at`

Marks flush on every Space / X. Never write into the photo tree.

---

## Phase 0 — Project

**Files:** `PicksApp.swift`, `SupportPaths.swift`, `EventBookmark.swift`

- New macOS App sandbox, User Selected File (read).
- Window: drop zone / “Choose folder…” (`NSOpenPanel`, directories only).
- Save security-scoped bookmark. On launch, `startAccessingSecurityScopedResource()`.
- Create `Application Support/Picks/<event-id>/`.

**Exit**

- Choose the wedding folder.
- Quit.
- Reopen: bookmark resolves, no second picker.

**Tests**

- Bookmark round-trip in a temp directory (if sandbox allows in unit tests; otherwise a manual check).

---

## Phase 1 — Indexer + catalog

**Files:** `PathRules.swift`, `Pairing.swift`, `DuplicateIngest.swift`, `Indexer.swift`, `Database.swift`, scan UI in `AppModel` / a `ScanView`.

### Path rules

Include: `.jpg` `.jpeg` `.arw` `.cr2`  
Exclude: `.mp4` `.mov` `.mxf` `.mts` `.m4v`, `**/Thumbnails/**`, `**/Proxies*/**`, `_duplicate_report/**`, `.DS_Store`  
`Alternate Exports/**` → variant of stem, not its own photo.

### Pairing (RAW default)

```
group files by (ceremony, casefold(stem without __dup2 / _1 / __ALT))
if any RAW in group:
    canonical = that RAW
    jpeg_sidecar = JPEG if present
    canonical_kind = raw
else:
    canonical = JPEG
    canonical_kind = jpeg
```

Prefer sibling folders `JPG/` + `RAW/` when both exist.

### Duplicates

If `_duplicate_report/true_content_duplicates.csv` exists, mark extra copies `hidden_dup = 1`. Prefer keeping the Candid path.

### Scan UI

Live counts matching requirements §4. “Start reviewing” enabled once the first ceremony has rows (thumbs can still be building).

### Fixture (`Picks/Resources/Fixtures/MiniDump/`)

```
01 Engagement/Candid Photos/JPG/AKHI0001.JPG          # jpeg-only
03 Wedding/Candid Photos/JPG/M3F0001.jpg
03 Wedding/Candid Photos/RAW/M3F0001.ARW              # pair → canonical RAW
03 Wedding/Candid Photos/RAW/M3F0002.ARW              # raw-only
03 Wedding/Traditional Photos/RAW/M3F0001.ARW         # optional dup of candid
03 Wedding/Traditional Video/Thumbnails/C0001T01.JPG  # must skip
03 Wedding/Candid Video/C0001.MP4                     # must skip
```

Tiny dummy files are enough for pairing tests (empty or 1×1 JPEG). ARW pairing tests can use filename only.

**Exit**

- Fixture tests green.
- On the real dump (or Engagement + Wedding sliver): ~10k unique stills, 0 thumbs, every row with a RAW path has `canonical_kind = raw`.
- Debug “skipped” list available.

Maps to acceptance 1, 2, 3, 4, 5, 6.

---

## Phase 2 — Loupe

**Files:** `ReviewView.swift`, `PhotoCanvas.swift`, `FilmstripView.swift`, overlays.

- Full-bleed canvas. Photo fills the content view.
- Decode **canonical** URL via ImageIO / Quick Look at display scale (backingScaleFactor).
- Show cached thumb immediately; replace with Preview-resolution. Never leave the user on a smeared thumb.
- No filter / sharpen / grade on the photo. Optional blurred letterbox behind, never over the image.
- Header overlay: ceremony picker, All / Shortlist (Shortlist empty until Phase 3), ID, RAW badge if `canonical_kind == raw`.
- Bottom overlay: thin filmstrip (thumbs) + keys `←` `→` · `space` · `X` · `G` · `Z`.
- `Z` zooms in a step (1.5×, 2×, 3×…). `O` zooms out. `F` fits. Arrows pan when zoomed; drag pans.
- Arrows change `session` current photo (even before marks exist).

**Exit**

- Engagement `AKHI*` (JPEG-only) and Wedding `M3F*` (ARW) both open.
- Side-by-side with Preview on the same file: same sharpness.
- Window resize does not pixelate (redraw at new display size).

Maps to acceptance 2, 3, 4, 9.

---

## Phase 3 — Marks + persistence

**Files:** `MarkStore.swift`, `UndoStack.swift`, `Filters.swift`

- `Space` / `X` / `U` as in requirements §5. Auto-advance on Space (add) and X.
- Shortlist view = `shortlisted = 1`.
- All filters: Everything / Left (default) / Passed.
- Gold bookmark on strip + header when shortlisted.
- Flush SQLite on every mark.
- Undo last mark (`⌘Z`), session-local.
- Restore last photo, view, filter, ceremony on launch.

**Exit**

- Star 5, quit, reopen: same 5, same photo, same view.
- Left-to-review hides passed and shortlisted.

Maps to acceptance 7, 8.

This is the end of the **first vertical slice**.

---

## Phase 4 — Event Home

**Files:** `EventHomeView.swift`

- Ceremony cards from distinct `photos.ceremony`.
- Counts: stills, shortlisted, passed, left.
- Progress bar = reviewed / stills (passed + shortlisted).
- Continue: last photo if this ceremony is current, else first Left.
- Empty-shortlist and ceremony-finished states as in the HTML spec.

**Exit**

- Home → Engagement → work → Home shows progress.
- Upanayanam at 0 shortlisted is obvious.

Maps to acceptance 11.

---

## Phase 5 — Export

**Files:** `Exporter.swift`

- Sheet: `photo-ids.txt` (on), `shortlist.csv` (on), contact sheet (off), Copy IDs, Save to folder.
- `photo-ids.txt`: one stem per line, current shortlist, ceremony then ID order.
- CSV: `id,event,ceremony,style,camera,canonical_kind,jpeg,raw,note`

**Exit**

- Copy IDs, paste into Notes, Finder-search one ID in the dump.

Maps to acceptance 10.

---

## Phase 6 — Grid + Drive

- `G` toggles a virtualized 6-across grid. Same gold pip.
- File Provider: if canonical is dataless, show cloud badge and hydrate **that file only** (+ optional next 1–2). Never prefetch the dump.
- Missing / offline: tile stays, marks stay.
- Compare (`C`) only if Phases 0–5 are solid; otherwise skip.

**Exit**

- Grid usable at 6-across.
- A placeholder RAW does not freeze the window.

---

## Risks

| Risk | Mitigation | Phase |
|---|---|---|
| ARW loupe softer than Preview | Gate Phase 2 on a visual check vs Preview on `M3F03442.ARW` | 2 |
| JPG+RAW counted twice | Fixture tests before the 10k walk | 1 |
| Drive hydrates 25 MB RAWs in bulk | Current + 1–2 lookahead only | 6 |
| 10k SwiftUI images | Virtualize strip/grid; loupe holds one full decode | 2, 6 |
| Sandbox loses the folder | Bookmark + start/stop access every launch | 0 |
| Indexer slow on Drive | Metadata-only first pass; thumbs async | 1 |

---

## First PR / first slice

**Build Phases 0–3 only.**

Test on:

1. `Picks/Resources/Fixtures/MiniDump`
2. `01 Engagement` (JPEG-only, `AKHI*`, `_MG_*`)
3. A sliver of `03 Wedding/…/RAW` (`M3F*`) so RAW-default is real

Do **not** include in the first slice: contact sheet, compare, notes field, jump-to-ID (`/`), rich Alternate Exports UI (attach-or-ignore is enough), Event Home polish, grid.

---

## Order of work (checklist)

- [x] Phase 0 — project, open folder, bookmark
- [x] Phase 1 — indexer, RAW-default pairing, fixture tests
- [x] Phase 2 — Preview-sharp loupe on canonical file
- [x] Phase 3 — shortlist / passed / keyboard / restore  ← first slice done
- [x] Phase 4 — Event Home
- [x] Phase 5 — export IDs
- [x] Phase 6 — grid + Drive

---

- [x] Notes (`N`) and jump-to-ID (`/`)

## Explicitly later

Video, AI, named rounds, Maybe, stars/XMP, writing into the dump, multi-Mac sync, accounts, RAW develop, hard caps.

See requirements §9.
