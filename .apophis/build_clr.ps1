# Build clr
$ErrorActionPreference = "Stop"

$VenvPath = "H:\ROCm\.venv"

. "$VenvPath\Scripts\activate.ps1"
$ROCmBin = (rocm-sdk path --bin).Replace('\', '/')
$env:PATH = "$ROCmBin;$env:PATH"
$ROCmRoot = (rocm-sdk path --root).Replace('\', '/')
$env:ROCM_PATH = $ROCmRoot

$VsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath
. "$VsPath\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64

$SuperRoot = (Split-Path -Parent $PSScriptRoot).Replace('\', '/')
$BuildDir = "$SuperRoot/build"
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }

# $InstallDir = "$BuildDir/install"
$InstallDir = "$VenvPath\Lib\site-packages\_rocm_sdk_core"

$LLVMPath = "$ROCmRoot/lib/llvm"
$env:HIP_CLANG_PATH = "$LLVMPath/bin"
$env:HIP_DEVICE_LIB_PATH = "$LLVMPath/amdgcn/bitcode"
$env:CMAKE_BUILD_PARALLEL_LEVEL = "12"

if (Get-Command sccache -ErrorAction SilentlyContinue) {
    $env:CMAKE_C_COMPILER_LAUNCHER = "sccache"
    $env:CMAKE_CXX_COMPILER_LAUNCHER = "sccache"
    $SccacheArgs = @(
        "-DCMAKE_C_COMPILER_LAUNCHER=sccache",
        "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
    )
    Write-Host -ForegroundColor Cyan "* sccache detected, using as compiler launcher"
} else {
    $SccacheArgs = @()
}

cmake -GNinja `
    -S $SuperRoot/projects/clr `
    -B $BuildDir `
    -DCMAKE_INSTALL_PREFIX="$InstallDir" `
    -DCMAKE_BUILD_TYPE=Release `
    -DHIP_PLATFORM=amd `
    -DCLR_BUILD_HIP=ON `
    -DHIP_COMMON_DIR="$SuperRoot/projects/hip" `
    -DHIPCC_BIN_DIR="$ROCmBin" `
    -D__HIP_ENABLE_PCH=OFF `
    -DROCCLR_ENABLE_HSA=ON `
    -DROCCLR_ENABLE_PAL=ON `
    -DUSE_PROF_API=OFF `
    -DROCM_KPACK_ENABLED=ON `
    -DAMD_COMPUTE_WIN="$SuperRoot/shared/amdgpu-windows-interop" `
    -DCOMGR_DLL_NAME="amd_comgr0713.dll" `
    -DClang_ROOT="$LLVMPath" `
    -DLLVM_BIN="$env:HIP_CLANG_PATH" `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded `
    -Wno-dev `
    @SccacheArgs
if ($LASTEXITCODE -ne 0) { $env:PATH -split ';'; Write-Host -ForegroundColor Red "* Failed to CMake"; exit $LASTEXITCODE }
Write-Host -ForegroundColor Green "* CMake configuration done"

cmake --build $BuildDir -j $env:CMAKE_BUILD_PARALLEL_LEVEL --target install
