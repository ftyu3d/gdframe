# Pack dist/gdframe.zip. Zip root is addons/.
# Usage (repo root): powershell -File tools/pack_release.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pluginCfg = Join-Path $root "addons\gdframe\plugin.cfg"
$dist = Join-Path $root "dist"
$zipPath = Join-Path $dist "gdframe.zip"

if (-not (Test-Path $pluginCfg)) {
	throw "Missing plugin: $pluginCfg"
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $zipPath) {
	Remove-Item -Force $zipPath
}

Push-Location $root
try {
	Compress-Archive -Path "addons" -DestinationPath $zipPath -CompressionLevel Optimal
} finally {
	Pop-Location
}

Write-Host "Created: $zipPath"
