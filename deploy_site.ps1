# ─── Publishes get-scripta.app ───────────────────────────────────────────────
#
# The site is a Cloudflare Pages project called `scripta` with NO git
# integration, so nothing is published by pushing — it has to be uploaded, and
# for a month nobody did, which is how the live privacy policy drifted a version
# behind the repo and the admin console stayed stale while GitHub Pages served a
# newer copy of it. Run this instead of hoping.
#
# The admin console is assembled here rather than living in docs/, for two
# reasons. GitHub Pages serves docs/, so anything in there is published TWICE —
# and this repo is PUBLIC, so a folder named after the console's secret path
# advertises that path to anyone who opens the repository. Its URL now comes
# from .console-slug, which is gitignored.
#
#   pwsh -File deploy_site.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$slugFile = Join-Path $root '.console-slug'
if (-not (Test-Path $slugFile)) {
  throw "Missing .console-slug. It is deliberately not in git - copy it from the Desktop file: Scripta - Console e Credenziali.txt"
}
$slug = (Get-Content $slugFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($slug)) { throw ".console-slug is empty." }

$build = Join-Path $env:TEMP ("scripta-site-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $build -Force | Out-Null

Copy-Item (Join-Path $root 'docs\*') $build -Recurse -Force
$consoleOut = Join-Path $build $slug
New-Item -ItemType Directory -Path $consoleOut -Force | Out-Null
Copy-Item (Join-Path $root 'admin-console\index.html') $consoleOut -Force

Write-Output "Publishing $build  (console at /$slug/)"
Push-Location $root
try {
  & npx wrangler pages deploy $build --project-name=scripta --branch=main --commit-dirty=true
} finally {
  Pop-Location
  Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
}
