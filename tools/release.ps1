#!/usr/bin/env pwsh
# Cut a release. Tags the current commit `v<Version>` and pushes it; the GitHub
# Actions "Release" workflow then builds the Windows .exe and publishes the
# GitHub Release. The tag is the single source of truth for the version.
#
#   ./tools/release.ps1 1.2.3
#
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.\-]+)?$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$tag = "v$Version"

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'master') {
    throw "Releases are cut from 'master' (currently on '$branch')."
}
if ((git status --porcelain).Trim().Length -ne 0) {
    throw "Working tree is dirty — commit or stash before releasing."
}

git rev-parse -q --verify "refs/tags/$tag" *> $null
if ($LASTEXITCODE -eq 0) {
    throw "Tag $tag already exists."
}

git pull --ff-only
git tag -a $tag -m "Spheres of Pain $tag"
git push origin $tag

Write-Host ""
Write-Host "Pushed $tag. Track the build at:" -ForegroundColor Green
Write-Host "  https://github.com/healplease/spheres-of-pain/actions" -ForegroundColor Green
