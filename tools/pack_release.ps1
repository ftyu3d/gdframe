# Pack release ZIP with entries: addons/gdframe/...
# Usage (repo root): powershell -File tools/pack_release.ps1
# Output: dist/gdframe.zip

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "gdframe"
$dist = Join-Path $root "dist"
$staging = Join-Path $dist "_staging_gdframe"
$zipPath = Join-Path $dist "gdframe.zip"

if (-not (Test-Path $src)) {
	throw "Missing plugin dir: $src"
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $staging) {
	Remove-Item -Recurse -Force $staging
}
New-Item -ItemType Directory -Force -Path (Join-Path $staging "addons") | Out-Null
Copy-Item -Recurse -Force $src (Join-Path $staging "addons\gdframe")

if (Test-Path $zipPath) {
	Remove-Item -Force $zipPath
}

Push-Location $staging
try {
	Compress-Archive -Path "addons" -DestinationPath $zipPath -CompressionLevel Optimal
} finally {
	Pop-Location
}

Remove-Item -Recurse -Force $staging
Write-Host "Created: $zipPath"
