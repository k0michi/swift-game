$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build-sdl.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

swift build --package-path $RepositoryRoot @args
exit $LASTEXITCODE
