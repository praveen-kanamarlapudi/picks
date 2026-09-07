# Keep — Requirements

Status: **Locked**  
Date: 2026-08-12  
Reference dump: a nested wedding photographer dump (~19k files, ~526 GB, Google Drive File Stream)

This file is the product source of truth. The clickable spec in `design/keep-screens.html` illustrates it. If they disagree, this file wins.

---

## 1. Product

Keep is a native Mac app for a **couple / family**, not a photographer.

You point it at a photographer’s dump. You walk stills. You build **one shortlist**. You export **camera IDs** the photographer can search (`M3F03442`, `AKHI0355`, `_S9A7954`).

It is not an editor, not a gallery, not Photo Mechanic, not Pixieset.

**Done:** a list of ~80–200 IDs you would pay to have processed.  
**Not done:** a pretty mosaic, a zip of RAWs, or a 10k-image scroll.

---

## 2. Locked decisions

| Decision | Lock |
|---|---|
| User | Couple / family, one Mac, one person at a time |
| v1 media | Stills only. Videos and video thumbs are ignored |
| Lists | **All** and **Shortlist**. Nothing else |
| Marks | Shortlisted (boolean) + Passed (work flag, not exported) |
| Iteration | Flip All ↔ Shortlist. No named rounds. No Maybe pile |
| Default original | **RAW if it exists. JPEG only when RAW is completely missing** |
| Formats | `.jpg` / `.jpeg`, `.arw`, `.cr2` (same RAW rule). Other RAW later if it appears |
| Pairing | Same camera stem in sibling `JPG/` + `RAW/` (or same folder) = **one photo** |
| Viewer quality | Same as macOS Preview. Never an upscaled thumbnail in the loupe |
| Layout | Photo owns the window. Chrome and shortcuts overlay the photo |
| Persistence | Local SQLite in Application Support. Survive quit. Never write into the photo tree except Trash |
| Export | One list: `photo-ids.txt` + `shortlist.csv`. Copy IDs. Optional contact sheet |
| Files on disk | **Delete** moves that photo’s files (RAW + JPEG) to Trash. **⌘Z** restores from Trash if it is still there. No rename, XMP, or ratings |
| Platform | Native Swift / SwiftUI Mac app |

---

## 3. Photo model

A **photo** is one camera capture, not one file.

### Identity

- **Photo ID** (user-visible, exported) = camera filename stem, stripped of `__dup2` / `_1` / `__ALT` suffixes, case-preserved as on disk for display, compared case-insensitively.  
  Examples: `M3F03442`, `AKHI0355`, `_MG_6420`, `DMB04998`, `_S9A7954`.
- Internal key = `(event_id, photo_id)` so the same basename in a different ceremony never collapses (video basenames collide; stills in this dump do not across events).

### Canonical file (RAW default)

```
if any RAW sibling exists (.arw, .cr2, later .cr3/.nef/.dng):
    canonical = RAW
    jpeg_sidecar = JPEG if present
else:
    canonical = JPEG
```

- The loupe always displays **canonical**.
- The `RAW` badge means a RAW file exists (canonical is RAW).
- If only JPEG is present, there is no RAW badge. That photo is JPEG-only. That is the exception, not the default.
- JPEG is never shown as a second tile when RAW exists.
- Variants (`FOO_1.jpg`, `Alternate Exports/FOO.jpg`) attach to `FOO`. They are not separate photos.

### Display quality

- Loupe uses the same path Preview uses: **ImageIO / Quick Look** on the canonical file.
- For ARW/CR2 that means the camera-embedded preview Preview shows, not a slow LibRaw demosaic.
- Grid and filmstrip may use small thumbs.
- The loupe may show a thumb for one frame, then **must** replace it with Preview-resolution. The user must not decide on a soft image.
- No extra sharpen, blur, or color grade on the photo. A blurred copy may fill letterbox only. It must never cover the photo.

---

## 4. Indexer

Given an event root folder (example: `Wedding`):

### Include as stills

- `.jpg`, `.jpeg`
- `.arw`, `.cr2` (and later other camera RAW)

### Exclude

- Video: `.mp4`, `.mov`, `.mxf`, `.mts`, `.m4v`
- Paths matching `**/Thumbnails/**`, `**/Proxies*/**`
- `_duplicate_report/**`
- `.DS_Store` and other junk
- `Alternate Exports/**` as independent photos (attach as variants)

### Pairing

- Prefer sibling folders named `JPG` and `RAW`.
- Also pair same-stem JPEG+RAW in the same directory.
- Stem match is case-insensitive. `M3F03442.jpg` + `M3F03442.ARW` = one photo, canonical = ARW.

### Duplicates

- If `_duplicate_report/true_content_duplicates.csv` exists, ingest it.
- Hide extra exact copies. Keep one (prefer Candid over Traditional when both exist).
- Same basename in different events is **not** a duplicate.

### Cloud / Drive

- Do not copy the dump.
- Do not prefetch RAW files that are File Provider placeholders unless the user is viewing that photo.
- Hydrate **canonical** on demand (RAW if present, else JPEG).
- If Drive is offline, catalog and marks still open; unresolved files show a missing/cloud state. Marks stay.

### Scan sheet (user-visible)

Report:

- Stills (unique photos)
- RAW canonical
- JPEG-only (no RAW)
- Exact duplicates hidden
- Video thumbs skipped
- Videos ignored

Review is enabled before every thumb exists.

---

## 5. Interaction

### Views

Always-visible control:

```
[ All  <n> ]   [ Shortlist  <n> ]
```

- **All** — stills in the current ceremony (and current All-filter). Shortlisted photos show a gold bookmark on the tile and in the loupe.
- **Shortlist** — only shortlisted photos. Same loupe / grid / keys. Space removes.

Filter on **All only** (not a third list):

- Everything
- Left to review (not shortlisted, not passed) — **default**
- Already passed

### Marks

| Key | All | Shortlist |
|---|---|---|
| `←` `→` | Previous / next photo. **When zoomed:** pan | Same |
| `↑` `↓` | Unused at fit. **When zoomed:** pan | Same |
| `Space` | Add to shortlist, advance | Remove from shortlist, advance |
| `X` | Pass + advance (not shortlisted; hidden from “Left”) | Remove + advance |
| `U` | Unmark (clear shortlist + passed) | Unmark |
| `Delete` | Move this photo’s files to Trash (RAW + JPEG) | Same |
| `⌘Z` | Undo last mark **or** restore last Trash | Same |
| `Z` | Zoom in one step (1 → 1.5 → 2 → 3 → 4 → 6 → 8), around pointer | Same |
| `O` | Zoom out one step | Same |
| `F` | Fit (zoom 100%, centered) | Same |
| `G` | Toggle grid | Same |
| `I` | Toggle extra info | Same |
| `N` | One-line note | Same |
| `/` | Jump to ID | Same |
| `⌘⇧E` | Export | Export |
| `?` | Cheatsheet | Cheatsheet |

If someone only learns arrows + Space + X, they can finish the wedding.

Passed is **not** exported. It only stops All from replaying photos already judged “no.”

### Layout

- Review is full-bleed. No dedicated sidebar column, no dedicated filmstrip pane.
- Photo fills the content area (Preview-sharp).
- Top overlay: ceremony picker, All / Shortlist, All-filters, ID, shortlist control, Saved.
- Bottom overlay: thin filmstrip + shortcut legend (`←` `→` · `space` · `X` · `G` · `Z`).
- Event Home is ceremony cards (not a 10k grid). Progress = reviewed (shortlisted + passed), not only shortlisted.
- Empty shortlist and “ceremony finished” are explicit states, not blank windows.

### Session

Restore: last event, ceremony, photo ID, view (All/Shortlist), All-filter.  
Quit is always safe. Marks flush on every Space / X.

---

## 6. Persistence

```
~/Library/Application Support/Keep/<event-id>/
  catalog.sqlite
  thumbs/                  # generated, disposable
  folder.bookmark          # security-scoped bookmark
```

Schema (logical):

- `photos` — id, event, ceremony, style (Candid/Traditional/…), camera, photo_id, canonical_path, canonical_kind (`raw`\|`jpeg`), jpeg_path, raw_path, file_id/hash if known
- `marks` — photo key, shortlisted, passed, note, updated_at
- `session` — last_photo_id, view, filter, ceremony
- `scan_meta` — counts, last_indexed_at

Never write into the photographer’s tree.

---

## 7. Export

Working set = current Shortlist.

Default artifacts:

1. **`photo-ids.txt`** — one ID per line. WhatsApp / paste path.
2. **`shortlist.csv`** — `id,event,ceremony,style,camera,canonical_kind,jpeg,raw,note`
3. **Copy IDs** — same as the txt, on the clipboard.

Optional, off by default: contact-sheet PDF (6-up, IDs under each).

Do not copy RAW/JPEG binaries as the primary export. Optional “copy selected JPEGs” may come later.

---

## 8. Grounding in the reference dump

These numbers exist so the indexer can be tested against a real tree.

| Fact | Number |
|---|---|
| Files | ~18,910 |
| Stills (jpg+arw+cr2) | ~16,868 file entries |
| Unique reviewable stills after pair + skip video thumbs | ~10,000 |
| ARW | 4,502 (all have JPEG siblings) |
| CR2 | 550 (all have JPEG siblings) |
| JPEG-only stills | ~5,072 |
| RAW-only in this dump | 0 — **must still work** on a RAW-only folder |
| Exact byte-duplicates | 1,021 extra copies |
| Videos | 2,042 (out of v1) |
| Video thumbs to skip | ~1,530 |

Ceremonies are the first path component: `01 Engagement`, `02 Bride Making`, `03 Wedding [22.08.2021]`, …

---

## 9. Out of scope (v1)

- Video review
- AI culling, blink/blur scoring, face recognition
- Named rounds, Maybe pile, star ratings, color labels
- Writing ratings or XMP into files
- Moving / renaming / deleting photographer files
- Multi-Mac or couple realtime sync
- Accounts, upload, share links
- Full RAW develop (exposure, WB). Preview display only
- Hard selection caps

---

## 10. Acceptance

A build is acceptable when all of the following are true against the wedding dump (or a sliver of it):

1. Opening the root does not copy 526 GB and does not write into that tree.
2. `M3F03442.jpg` + `M3F03442.ARW` appear as **one** photo. Loupe uses the **ARW**. Badge is RAW.
3. `AKHI0355.JPG` (no RAW) appears as one photo. Loupe uses the JPEG.
4. A folder of only `.ARW` files is fully reviewable.
5. Video thumbs and videos do not appear.
6. Exact dups are not shown twice.
7. All / Shortlist switch works. Gold mark is visible on All tiles.
8. Space / X / arrows work. State survives quit and relaunch.
9. Loupe looks like Preview on the same file, not like a smeared Finder thumb.
10. Export writes `photo-ids.txt` whose lines the photographer can search.
11. Engagement can be finished in one evening without flattening 10k photos into one grid.

---

## 11. Implementation plan

How to build this, phase by phase, lives in [`plan.md`](plan.md).

First slice: Phases 0–3 (project, indexer, loupe, marks). Home, export, and grid come after that loop is right.

---

## 12. Spec artifact

`design/keep-screens.html` — clickable UX. Persistence in the HTML is `localStorage` (demo only). The app uses SQLite as specified above.
