#!/usr/bin/env pwsh
# Cut a release. Tags the current commit `v<Version>` and pushes it; the GitHub
# Actions "Release" workflow then builds the Windows .exe and publishes the
# GitHub Release. The tag is the single source of truth for the version.
#
#   ./tools/release.ps1 1.2.3            # tag + push
#   ./tools/release.ps1 1.2.3 -DryRun    # run all checks, but don't tag or push
#
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.\-]+)?$')]
    [string]$Version,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$tag = "v$Version"

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'master') {
    throw "Releases are cut from 'master' (currently on '$branch')."
}

# git status --porcelain prints nothing (-> $null) when the tree is clean, so test
# truthiness rather than calling string methods on a possibly-null value.
$dirty = git status --porcelain
if ($dirty) {
    throw "Working tree is dirty - commit or stash before releasing."
}

# git tag -l prints the tag name if it exists, nothing otherwise.
if (git tag -l $tag) {
    throw "Tag $tag already exists."
}

git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw "git pull --ff-only failed." }

if ($DryRun) {
    Write-Host ""
    Write-Host "[DryRun] All checks passed. Would tag and push: $tag" -ForegroundColor Yellow
    return
}

git tag -a $tag -m "Spheres of Pain $tag"
if ($LASTEXITCODE -ne 0) { throw "git tag failed." }

git push origin $tag
if ($LASTEXITCODE -ne 0) { throw "git push failed (tag created locally - 'git tag -d $tag' to undo)." }

Write-Host ""
Write-Host "Pushed $tag. Track the build at:" -ForegroundColor Green
Write-Host "  https://github.com/healplease/spheres-of-pain/actions" -ForegroundColor Green
