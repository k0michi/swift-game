$ErrorActionPreference = "Stop"

# Writes what is being built into Sources/CBuildInfo, for the game to show.
# Builds run it first. It leaves the file as it is when nothing changed, so
# that nothing is compiled again.

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Version = git -C $RepositoryRoot describe --tags --always --dirty 2>$null
if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = "unknown" }
$Header = Join-Path $RepositoryRoot "Sources/CBuildInfo/BuildInfo.generated.h"
$Contents = "#define BUILD_INFO_VERSION `"$Version`"`n"

if (-not (Test-Path $Header) -or [IO.File]::ReadAllText($Header) -ne $Contents) {
    [IO.File]::WriteAllText($Header, $Contents)
}
$global:LASTEXITCODE = 0
