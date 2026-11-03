$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$DependencyDirectory = Join-Path $RepositoryRoot ".build/dependencies/freetype"
$BuildDirectory = Join-Path $DependencyDirectory "cmake-build"
$SwiftBinDirectory = Split-Path -Parent (Get-Command swiftc).Source
$ClangCL = Join-Path $SwiftBinDirectory "clang-cl.exe"

cmake `
    -G Ninja `
    -S (Join-Path $RepositoryRoot "cmake/FreeType") `
    -B $BuildDirectory `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DFREETYPE_METADATA_DIRECTORY=$DependencyDirectory" `
    "-DCMAKE_C_COMPILER=$ClangCL"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --build $BuildDirectory --config Release --parallel
exit $LASTEXITCODE
