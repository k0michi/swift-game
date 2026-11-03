$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$DependencyDirectory = Join-Path $RepositoryRoot ".build/dependencies/noto-sans-jp"
$BuildDirectory = Join-Path $DependencyDirectory "cmake-build"

cmake `
    -G Ninja `
    -S (Join-Path $RepositoryRoot "cmake/NotoSansJP") `
    -B $BuildDirectory `
    "-DNOTO_SANS_JP_METADATA_DIRECTORY=$DependencyDirectory"
exit $LASTEXITCODE
