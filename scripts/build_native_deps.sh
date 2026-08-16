#!/bin/bash
#
# build_native_deps.sh — 交叉编译 libass 及其依赖（freetype/fribidi/harfbuzz）
#
# 用法:
#   ./build_native_deps.sh [arm64-v8a|armeabi-v7a|x86_64]
#
# 前置条件:
#   1. 已安装 Android NDK（通过 ANDROID_NDK_HOME 或默认路径检测）
#   2. 已安装 meson + ninja（用于 fribidi 编译）
#   3. 已安装 automake + libtool + pkg-config
#
# 编译产物:
#   android/app/src/main/cpp/libs/<ABI>/libass.a
#   android/app/src/main/cpp/libs/<ABI>/libfreetype.a
#   android/app/src/main/cpp/libs/<ABI>/libfribidi.a
#   android/app/src/main/cpp/libs/<ABI>/libharfbuzz.a
#   android/app/src/main/cpp/libs/<ABI>/include/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/android/app/src/main/cpp/libs"
BUILD_DIR="/tmp/lanplayer_native_build"
ABI="${1:-arm64-v8a}"

# 检测 NDK
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
    NDK_DIR="$ANDROID_NDK_HOME"
elif [ -n "${ANDROID_HOME:-}" ]; then
    NDK_DIR="$ANDROID_HOME/ndk/$(ls -1 $ANDROID_HOME/ndk/ | sort -V | tail -1)"
elif [ -d "/d/androidsdk/ndk" ]; then
    NDK_DIR="/d/androidsdk/ndk/$(ls -1 /d/androidsdk/ndk/ | sort -V | tail -1)"
else
    echo "ERROR: Cannot find Android NDK. Set ANDROID_NDK_HOME."
    exit 1
fi

echo "=== NDK: $NDK_DIR"
echo "=== ABI: $ABI"
echo "=== Output: $OUTPUT_DIR/$ABI"

# 设置 NDK 工具链
TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$TOOLCHAIN" ]; then
    TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/windows-x86_64"
fi

case "$ABI" in
    arm64-v8a)
        TARGET="aarch64-linux-android"
        ARCH_FLAGS="-march=armv8-a"
        ;;
    armeabi-v7a)
        TARGET="armv7a-linux-androideabi"
        ARCH_FLAGS="-march=armv7-a -mthumb -mfpu=neon"
        ;;
    x86_64)
        TARGET="x86_64-linux-android"
        ARCH_FLAGS="-march=x86-64"
        ;;
    *)
        echo "ERROR: Unsupported ABI: $ABI"
        exit 1
        ;;
esac

API_LEVEL=24
CC="$TOOLCHAIN/bin/${TARGET}${API_LEVEL}-clang"
CXX="$TOOLCHAIN/bin/${TARGET}${API_LEVEL}-clang++"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
STRIP="$TOOLCHAIN/bin/llvm-strip"

export CC CXX AR RANLIB STRIP
export CFLAGS="-fPIC $ARCH_FLAGS -O2 --sysroot=$TOOLCHAIN/sysroot"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="--sysroot=$TOOLCHAIN/sysroot"
export PKG_CONFIG_PATH="$OUTPUT_DIR/$ABI/lib/pkgconfig"

PREFIX="$OUTPUT_DIR/$ABI"
mkdir -p "$PREFIX/lib" "$PREFIX/include" "$PREFIX/lib/pkgconfig"
mkdir -p "$BUILD_DIR"

# ===== 1. FreeType =====
echo "=== Building FreeType ==="
FREETYPE_VERSION="2.13.3"
cd "$BUILD_DIR"
if [ ! -d "freetype-$FREETYPE_VERSION" ]; then
    curl -L -o "freetype-$FREETYPE_VERSION.tar.gz" "https://sourceforge.net/projects/freetype/files/freetype2/$FREETYPE_VERSION/freetype-$FREETYPE_VERSION.tar.gz/download"
    tar xf "freetype-$FREETYPE_VERSION.tar.gz"
fi
cd "freetype-$FREETYPE_VERSION"
./configure --host="$TARGET" --prefix="$PREFIX" \
    --without-harfbuzz --without-brotli --without-bzip2 \
    --without-png --enable-static --disable-shared
make -j$(nproc) && make install

# ===== 2. HarfBuzz =====
echo "=== Building HarfBuzz ==="
HARFBUZZ_VERSION="9.0.0"
cd "$BUILD_DIR"
if [ ! -d "harfbuzz-$HARFBUZZ_VERSION" ]; then
    curl -L -o "harfbuzz-$HARFBUZZ_VERSION.tar.xz" "https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz"
    tar xf "harfbuzz-$HARFBUZZ_VERSION.tar.xz"
fi
cd "harfbuzz-$HARFBUZZ_VERSION"
./configure --host="$TARGET" --prefix="$PREFIX" \
    --with-freetype=yes --with-glib=no --with-gobject=no \
    --enable-static --disable-shared
make -j$(nproc) && make install

# ===== 3. FriBidi =====
echo "=== Building FriBidi ==="
FRIBIDI_VERSION="1.0.16"
cd "$BUILD_DIR"
if [ ! -d "fribidi-$FRIBIDI_VERSION" ]; then
    curl -L -o "fribidi-$FRIBIDI_VERSION.tar.xz" "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
    tar xf "fribidi-$FRIBIDI_VERSION.tar.xz"
fi
cd "fribidi-$FRIBIDI_VERSION"
./configure --host="$TARGET" --prefix="$PREFIX" \
    --enable-static --disable-shared
make -j$(nproc) && make install

# ===== 4. libass =====
echo "=== Building libass ==="
LIBASS_VERSION="0.17.3"
cd "$BUILD_DIR"
if [ ! -d "libass-$LIBASS_VERSION" ]; then
    curl -L -o "libass-$LIBASS_VERSION.tar.gz" "https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
    tar xf "libass-$LIBASS_VERSION.tar.gz"
fi
cd "libass-$LIBASS_VERSION"
./configure --host="$TARGET" --prefix="$PREFIX" \
    --enable-static --disable-shared \
    --disable-asm  # 禁用汇编优化以确保兼容性
make -j$(nproc) && make install

echo ""
echo "=== Build complete ==="
echo "Libraries installed to: $PREFIX/lib/"
ls -la "$PREFIX"/lib/*.a
echo "Headers installed to: $PREFIX/include/"
ls -d "$PREFIX"/include/*/
