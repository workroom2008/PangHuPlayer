$ErrorActionPreference = "Stop"

$ndkRoot  = "D:\androidsdk\ndk\28.2.13676358"
$sysroot  = "$ndkRoot\toolchains\llvm\prebuilt\windows-x86_64\sysroot"
$clangDir = "$ndkRoot\toolchains\llvm\prebuilt\windows-x86_64\bin"
$srcDir   = "C:\Users\Administrator.DESKTOP-MLRSCTT\AppData\Local\Pub\Cache\hosted\pub.dev\jni-1.0.0\src"
$outRoot  = "D:\Trae CN\torrent\player\panghuplayer\build\jni_native_prebuilt"

if (-not (Test-Path $outRoot)) { New-Item -ItemType Directory -Path $outRoot -Force | Out-Null }

function Build-Abi {
    param($abiName, $targetTriple, $clangExe)

    $abiOut = Join-Path $outRoot $abiName
    if (-not (Test-Path $abiOut)) { New-Item -ItemType Directory -Path $abiOut -Force | Out-Null }
    $outSo = Join-Path $abiOut "libdartjni.so"

    Write-Host ""
    Write-Host "==> Building libdartjni.so for $abiName ($targetTriple) ..." -ForegroundColor Cyan

    $cflags = @(
        "--target=$targetTriple",
        "--sysroot=$sysroot",
        "-shared",
        "-fPIC",
        "-DDART_SHARED_LIB",
        "-O2",
        "-I$srcDir",
        "-I$srcDir\include",
        "-I$srcDir\include\internal",
        "-I$srcDir\third_party",
        (Join-Path $srcDir "dartjni.c"),
        (Join-Path $srcDir "third_party\global_jni_env.c"),
        (Join-Path $srcDir "include\dart_api_dl.c"),
        "-llog",
        "-Wl,-z,max-page-size=16384",
        "-o", $outSo
    )

    & $clangExe @cflags 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED to build $abiName (exit code $LASTEXITCODE)" -ForegroundColor Red
        return $false
    }

    if (Test-Path $outSo) {
        $size = (Get-Item $outSo).Length
        Write-Host "OK: $outSo ($size bytes)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "FAILED: $outSo not generated" -ForegroundColor Red
        return $false
    }
}

$ok = $true
$ok = $ok -and (Build-Abi "arm64-v8a"   "aarch64-linux-android21"      (Join-Path $clangDir "aarch64-linux-android21-clang.cmd"))
$ok = $ok -and (Build-Abi "armeabi-v7a" "armv7a-linux-androideabi21"  (Join-Path $clangDir "armv7a-linux-androideabi21-clang.cmd"))
$ok = $ok -and (Build-Abi "x86_64"      "x86_64-linux-android21"      (Join-Path $clangDir "x86_64-linux-android21-clang.cmd"))

if (-not $ok) { exit 1 }

Write-Host ""
Write-Host "All ABIs built successfully!" -ForegroundColor Green
