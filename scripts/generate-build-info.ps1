$ErrorActionPreference = "Stop"

# Writes what is being built into Sources/CBuildInfo, for the game to show:
# the source's version, the Swift compiler's, and the target triple, the
# host's. Builds run it first. It leaves the file as it is when nothing
# changed, so that nothing is compiled again.

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Version = git -C $RepositoryRoot describe --tags --always --dirty 2>$null
if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = "unknown" }
$SwiftVersion = "unknown"
$Triple = "unknown"
try {
    $TargetInfo = (& swiftc -print-target-info 2>$null | Out-String) | ConvertFrom-Json
    if ($TargetInfo.compilerVersion -match "Swift version ([^ ]+)") { $SwiftVersion = $Matches[1] }
    if ($TargetInfo.target.unversionedTriple) { $Triple = $TargetInfo.target.unversionedTriple }
} catch {}
$Header = Join-Path $RepositoryRoot "Sources/CBuildInfo/BuildInfo.generated.h"
$Contents = "#define BUILD_INFO_VERSION `"$Version`"`n" +
    "#define BUILD_INFO_SWIFT_VERSION `"$SwiftVersion`"`n" +
    "#define BUILD_INFO_TRIPLE `"$Triple`"`n"

if (-not (Test-Path $Header) -or [IO.File]::ReadAllText($Header) -ne $Contents) {
    [IO.File]::WriteAllText($Header, $Contents)
}
$global:LASTEXITCODE = 0
