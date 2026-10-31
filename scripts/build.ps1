$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build-sdl.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "build-dawn.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot "build-stb.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The manifest reads the dependencies' flags, which SwiftPM does not know
# about, so neither its cached manifest nor its build plans would see them
# change.
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $RepositoryRoot ".build/debug.yaml"), (Join-Path $RepositoryRoot ".build/release.yaml")
$BinPath = swift build --package-path $RepositoryRoot --manifest-cache none --show-bin-path @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "generate-build-info.ps1") -BinPath ($BinPath | Select-Object -Last 1)
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

swift build --package-path $RepositoryRoot --manifest-cache none @args
exit $LASTEXITCODE
