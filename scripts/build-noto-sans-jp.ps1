param([Parameter(Mandatory)][string]$Destination)

$ErrorActionPreference = "Stop"

# Downloads Noto Sans JP into the directory given, where the games are built.

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BuildDirectory = Join-Path $RepositoryRoot ".build/dependencies/noto-sans-jp/cmake-build"

cmake `
    -G Ninja `
    -S (Join-Path $RepositoryRoot "cmake/NotoSansJP") `
    -B $BuildDirectory `
    "-DNOTO_SANS_JP_DESTINATION=$Destination"
exit $LASTEXITCODE
