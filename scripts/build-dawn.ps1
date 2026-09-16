$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$DependencyDirectory = Join-Path $RepositoryRoot ".build/dependencies/dawn"
$BuildDirectory = Join-Path $DependencyDirectory "cmake-build"
$InstallDirectory = Join-Path $DependencyDirectory "install"
$SwiftBinDirectory = Split-Path -Parent (Get-Command swiftc).Source
$ClangCL = Join-Path $SwiftBinDirectory "clang-cl.exe"

cmake `
    --fresh `
    -G Ninja `
    -S (Join-Path $RepositoryRoot "cmake/Dawn") `
    -B $BuildDirectory `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DCMAKE_INSTALL_PREFIX=$InstallDirectory" `
    "-DDAWN_METADATA_DIRECTORY=$DependencyDirectory" `
    "-DCMAKE_C_COMPILER=$ClangCL" `
    "-DCMAKE_CXX_COMPILER=$ClangCL"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --build $BuildDirectory --config Release --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --install $BuildDirectory --config Release
exit $LASTEXITCODE
