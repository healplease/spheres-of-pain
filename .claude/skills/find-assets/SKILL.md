---
name: find-assets
description: Search the internet for free game assets (music, ambience, SFX, textures, models, fonts) for Spheres of Pain, shortlist candidates with licenses, and integrate only user-approved picks into the project.
---

# Find Assets — Spheres of Pain

Workflow for sourcing external assets. The user ALWAYS confirms before anything
enters the project — your job is to find, vet, and shortlist; theirs is to pick.

## Tone brief (what fits this game)

Dark fantasy, grimdark, gothic-ink. The pit is patient. Look for: low drones,
ritual percussion, distant choirs, bone/stone/obsidian textures, ember and ash,
muted violet/teal/rust palettes. Avoid: heroic orchestral, bright cartoon, sci-fi.

## Trusted sources (license-first)

| Source | What | License notes |
|---|---|---|
| kenney.nl | SFX, UI, simple models | CC0, no attribution |
| ambientcg.com | PBR textures/materials | CC0 |
| polyhaven.com | Textures, HDRIs, models | CC0 |
| opengameart.org | Everything | MIXED — check each item (prefer CC0; CC-BY ok with credit) |
| freesound.org | SFX, ambience | MIXED — filter to CC0; CC-BY ok with credit |
| pixabay.com | Music, SFX | Pixabay license (free, no attribution). **Blocks automated downloads (403)** — shortlist URLs and ask the user to download manually (their downloads keep the `author-title-id` filename, which preserves provenance) |
| incompetech.com | Music | CC-BY (credit Kevin MacLeod) |
| itch.io free packs | Art packs | MIXED — read each pack's license page |

Rules: commercial use must be allowed; **no NC (non-commercial) and no ND
licenses; nothing GPL for assets**. When in doubt about a license, drop the
candidate. Never hotlink or commit anything whose license you didn't verify.

## Procedure

1. **Clarify the slot.** What's needed (e.g. "pop SFX", "menu drone", "sphere
   normal map"), target format, and where it'll be used.
2. **Search** with WebSearch/WebFetch across 2–3 sources above.
3. **Shortlist 3–5 candidates** to the user: name, direct URL, license, format/
   size, and one line on why it fits the tone. **Stop and wait for their pick.**
4. **Download approved picks into `temp/`** (PowerShell `Invoke-WebRequest` or
   `curl`). Verify the file (size > 0, correct format; listen/look is the user's
   job — ask them to preview anything you can't judge).
5. **Convert if needed**: audio → `.ogg` (music/ambience) or `.wav` (short SFX),
   images → `.png`/`.webp`, models → `.glb`. Use ffmpeg if available.
6. **Move into place**: `audio/music/`, `audio/sfx/`, `art/textures/`,
   `art/models/`, `themes/fonts/`. Then reimport headless:
   `& "C:\Program Files\Godot\Godot.exe" --headless --path . --import`
7. **Log in `CREDITS.md`** (create at repo root if missing): asset name, author,
   source URL, license, date added. Required even for CC0 — it's the provenance
   record. CC-BY entries are mandatory and must also reach any future in-game
   credits screen.
8. Clean the `temp/` download copies.

## Hard rules

- No integration without explicit user approval of the specific file.
- Every asset gets a CREDITS.md line in the same change that adds it.
- Keep originals' filenames reasonably intact (kebab/snake-cased) so they can
  be traced back to the source.
