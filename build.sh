#!/bin/bash
# Builds libass and its dependencies into one static Libass.xcframework
# for tvOS device and simulator. Meson flags follow mpvkit/libass-build
# (MIT), which ships the same versions.
set -euo pipefail

LIBASS=0.17.5
FREETYPE=VER-2-14-3
HARFBUZZ=14.2.0
FRIBIDI=v1.0.16
UNIBREAK=libunibreak_6_1
MIN_TVOS=26.0

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/.build"
SRC="$WORK/src"
DIST="$ROOT/dist"

fetch() { # name url tag
    [ -d "$SRC/$1" ] || git clone --quiet --depth 1 --branch "$3" "$2" "$SRC/$1"
}

cross_file() { # sdk triple subsystem
    local sdk=$1 triple=$2 subsystem=$3
    local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    local flags="['-target', '$triple', '-isysroot', '$sysroot']"
    cat > "$WORK/$sdk.cross" <<EOF
[binaries]
c = ['xcrun', '--sdk', '$sdk', 'clang']
cpp = ['xcrun', '--sdk', '$sdk', 'clang++']
objc = ['xcrun', '--sdk', '$sdk', 'clang']
objcpp = ['xcrun', '--sdk', '$sdk', 'clang++']
ar = ['xcrun', '--sdk', '$sdk', 'ar']
strip = ['xcrun', '--sdk', '$sdk', 'strip']
pkg-config = 'pkg-config'

[built-in options]
c_args = $flags
cpp_args = $flags
objc_args = $flags
c_link_args = $flags
cpp_link_args = $flags
objc_link_args = $flags
objcpp_args = $flags
objcpp_link_args = $flags

[host_machine]
system = 'darwin'
subsystem = '$subsystem'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
    echo "$WORK/$sdk.cross"
}

meson_build() { # name prefix crossfile [meson options...]
    local name=$1 prefix=$2 cross=$3; shift 3
    local build="$prefix.build/$name"
    rm -rf "$build"
    PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" PKG_CONFIG_PATH="" \
        meson setup "$build" "$SRC/$name" --cross-file "$cross" --prefix "$prefix" \
        --libdir lib --default-library=static --buildtype=release -Db_ndebug=true \
        -Dpkg_config_path="$prefix/lib/pkgconfig" "$@"
    meson install -C "$build" --quiet
}

build_unibreak() { # sdk triple prefix
    local sdk=$1 triple=$2 prefix=$3 obj="$3.build/unibreak"
    local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    mkdir -p "$obj" "$prefix/lib/pkgconfig" "$prefix/include"
    for f in unibreakbase unibreakdef linebreak linebreakdata linebreakdef \
             eastasianwidthdef emojidef graphemebreak wordbreak; do
        xcrun --sdk "$sdk" clang -target "$triple" -isysroot "$sysroot" -O2 \
            -c "$SRC/libunibreak/src/$f.c" -o "$obj/$f.o"
    done
    xcrun --sdk "$sdk" ar rcs "$prefix/lib/libunibreak.a" "$obj"/*.o
    cp "$SRC"/libunibreak/src/{unibreakbase,unibreakdef,linebreak,linebreakdef,eastasianwidthdef,graphemebreak,wordbreak}.h "$prefix/include/"
    cat > "$prefix/lib/pkgconfig/libunibreak.pc" <<EOF
prefix=$prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libunibreak
Description: Unicode line and word breaking
Version: 6.1
Libs: -L\${libdir} -lunibreak
Cflags: -I\${includedir}
EOF
}

build_platform() { # sdk triple subsystem slice
    local sdk=$1 triple=$2 subsystem=$3 slice=$4
    local prefix="$WORK/prefix/$slice"
    rm -rf "$prefix" "$prefix.build"
    local cross; cross="$(cross_file "$sdk" "$triple" "$subsystem")"

    build_unibreak "$sdk" "$triple" "$prefix"
    meson_build freetype "$prefix" "$cross" \
        -Dzlib=enabled -Dharfbuzz=disabled -Dbzip2=disabled -Dmmap=disabled \
        -Dpng=disabled -Dbrotli=disabled
    meson_build fribidi "$prefix" "$cross" \
        -Ddeprecated=false -Ddocs=false -Dbin=false -Dtests=false
    meson_build harfbuzz "$prefix" "$cross" \
        -Dglib=disabled -Dfreetype=disabled -Ddocs=disabled -Dtests=disabled \
        -Dutilities=disabled
    meson_build libass "$prefix" "$cross" \
        -Dlibunibreak=enabled -Dcoretext=enabled -Dfontconfig=disabled \
        -Ddirectwrite=disabled -Dasm=disabled -Dcheckasm=disabled -Dtest=disabled \
        -Dprofile=disabled -Dcompare=disabled -Dfuzz=disabled

    # One archive, so Rivulet links a single binary target.
    # Headers nest under Headers/Libass: Xcode copies every static
    # xcframework's Headers into one shared include/ directory, so a module
    # map at the Headers root collides with any other package that does the
    # same (LibDovi's Dovi.xcframework does).
    mkdir -p "$WORK/out/$slice/Headers/Libass/ass"
    libtool -static -o "$WORK/out/$slice/libass.a" \
        "$prefix"/lib/lib{ass,freetype,harfbuzz,fribidi,unibreak}.a
    cp "$prefix/include/ass/ass.h" "$prefix/include/ass/ass_types.h" "$WORK/out/$slice/Headers/Libass/ass/"
    cp "$ROOT/Support/module.modulemap" "$WORK/out/$slice/Headers/Libass/"
}

mkdir -p "$SRC"
fetch libunibreak https://github.com/adah1972/libunibreak "$UNIBREAK"
fetch freetype https://github.com/freetype/freetype "$FREETYPE"
fetch fribidi https://github.com/fribidi/fribidi "$FRIBIDI"
fetch harfbuzz https://github.com/harfbuzz/harfbuzz "$HARFBUZZ"
fetch libass https://github.com/libass/libass "$LIBASS"

rm -rf "$WORK/out"
build_platform appletvos "arm64-apple-tvos$MIN_TVOS" tvos tvos
build_platform appletvsimulator "arm64-apple-tvos$MIN_TVOS-simulator" tvos-simulator tvsimulator
# ponytail: arm64 simulator only; add x86_64 to the simulator slice if an Intel Mac ever builds Rivulet.

rm -rf "$DIST" && mkdir -p "$DIST"
xcodebuild -create-xcframework \
    -library "$WORK/out/tvos/libass.a" -headers "$WORK/out/tvos/Headers" \
    -library "$WORK/out/tvsimulator/libass.a" -headers "$WORK/out/tvsimulator/Headers" \
    -output "$DIST/Libass.xcframework"
(cd "$DIST" && ditto -c -k --norsrc --keepParent Libass.xcframework Libass.xcframework.zip)

mkdir -p "$ROOT/LICENSES"
cp "$SRC/libass/COPYING" "$ROOT/LICENSES/libass.txt"
cp "$SRC/freetype/docs/FTL.TXT" "$ROOT/LICENSES/freetype-FTL.txt"
cp "$SRC/harfbuzz/COPYING" "$ROOT/LICENSES/harfbuzz.txt"
cp "$SRC/fribidi/COPYING" "$ROOT/LICENSES/fribidi-LGPL-2.1.txt"
cp "$SRC/libunibreak/LICENCE" "$ROOT/LICENSES/libunibreak.txt"
echo "Built $DIST/Libass.xcframework.zip"
