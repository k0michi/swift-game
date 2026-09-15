$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourceDirectory = Join-Path $RepositoryRoot "Dependencies/SDL"
$DependencyDirectory = Join-Path $RepositoryRoot ".build/dependencies/sdl3"
$BuildDirectory = Join-Path $DependencyDirectory "build"
$InstallDirectory = Join-Path $DependencyDirectory "install"

if (-not (Test-Path (Join-Path $SourceDirectory "CMakeLists.txt"))) {
    throw "SDL submodule is missing. Run: git submodule update --init --recursive"
}

cmake `
    -S $SourceDirectory `
    -B $BuildDirectory `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DCMAKE_INSTALL_PREFIX=$InstallDirectory" `
    "-DSDL_SHARED=ON" `
    "-DSDL_STATIC=ON" `
    "-DSDL_DEPS_SHARED=ON" `
    "-DSDL_INSTALL=ON" `
    "-DSDL_TEST_LIBRARY=OFF" `
    "-DSDL_TESTS=OFF" `
    "-DSDL_EXAMPLES=OFF" `
    "-DSDL_INSTALL_DOCS=OFF"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --build $BuildDirectory --config Release --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --install $BuildDirectory --config Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake `
    -S (Join-Path $RepositoryRoot "cmake/ExtractSDLTarget") `
    -B (Join-Path $DependencyDirectory "metadata") `
    "-DSDL3_DIR=$InstallDirectory/cmake" `
    "-DOUTPUT_DIRECTORY=$DependencyDirectory" `
    "-DCMAKE_BUILD_TYPE=Release"
exit $LASTEXITCODE
