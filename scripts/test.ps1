$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build-sdl.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:SDL_VIDEODRIVER = "dummy"
$env:SDL_AUDIODRIVER = "dummy"

swift test --package-path $RepositoryRoot @args
exit $LASTEXITCODE
