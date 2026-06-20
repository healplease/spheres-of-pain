# Releasing Spheres of Pain

Releases are **tag-driven**. Pushing a semver tag (`vMAJOR.MINOR.PATCH`) triggers
the [`Release`](.github/workflows/release.yml) GitHub Actions workflow, which builds
a Windows `.exe` and publishes it as a GitHub Release. The tag is the single source
of truth for the version — it is stamped into the build and shown on the main menu.

## Cut a release

From a clean `master`:

```powershell
./tools/release.ps1 1.2.3
```

That validates the tree, creates an annotated tag `v1.2.3`, and pushes it. Or do it
by hand:

```powershell
git tag -a v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

Watch the build at <https://github.com/healplease/spheres-of-pain/actions>. When it
finishes, the release with `spheres-of-pain-1.2.3-windows.exe` attached appears under
<https://github.com/healplease/spheres-of-pain/releases>.

## How versioning works

- `project.godot` holds `application/config/version` (`0.0.0-dev` locally).
- CI rewrites that line to the tag value before exporting, so the running game shows
  the real version (bottom-right of the main menu).
- No version is committed by hand — bump only by choosing the next tag.

Use semver: `MAJOR` for breaking saves/levels, `MINOR` for features, `PATCH` for
fixes. Pre-releases like `v1.2.3-rc1` are allowed (still published as a normal release).

## What the build does (and notable choices)

- Builds on `ubuntu-latest`, cross-compiling the Windows binary with the official
  Godot 4.7 export templates (no local templates needed).
- Ships a **single self-contained `.exe`** (`binary_format/embed_pck=true`).
- `tests/` and the editor addons (GUT, MCP server — both gitignored, dev-only) are
  stripped before export so the headless build doesn't depend on them.

### Known follow-ups (optional polish)

- **Custom `.exe` icon / file metadata in Explorer:** currently off
  (`application/modify_resources=false`). To enable, add an `.ico`, set
  `application/icon`, flip `modify_resources=true`, and install `rcedit` (+ `wine`)
  in the workflow.
- **D3D12 on end-user machines:** the game requests the D3D12 driver and the single
  `.exe` does not bundle the D3D12 Agility SDK (it relies on the system runtime, with
  Godot's automatic Vulkan fallback). If a clean Windows machine fails to launch,
  bundle the SDK (`application/export_d3d12=1`) — note that adds DLLs alongside the
  `.exe`, so the release would become a zip rather than a lone file.
