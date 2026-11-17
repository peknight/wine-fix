#!/usr/bin/env bash
# 从 wine 源码重建 wine-fix 的三份产物。wine 升版后跑一遍，然后把 PKGBUILD 的
# pkgver 和 sha256sums 一起改掉。
#
#   ./build.sh [输出目录]        默认输出到当前目录
#
# 环境变量:
#   WINE_TARBALL      本地源码包路径，默认 ./wine-11.22.tar.xz
#   WINE_TARBALL_URL  下载地址，默认 dl.winehq.org（国内慢的话指到镜像）
#
# 依赖：gcc、flex、bison、x86_64-w64-mingw32-gcc，以及 libx11 / libxext 头文件
# （configure 能认出来的 X 扩展会一并编进去，缺哪个就自动关掉哪个）。
set -euo pipefail

readonly WINE_VERSION='11.22'
readonly WINE_TARBALL="${WINE_TARBALL:-wine-${WINE_VERSION}.tar.xz}"
readonly WINE_URL="${WINE_TARBALL_URL:-https://dl.winehq.org/wine/source/11.x/${WINE_TARBALL}}"
readonly HERE=$(cd "$(dirname "$0")" && pwd)
readonly OUTPUT=$(mkdir -p "${1:-$PWD}" && cd "${1:-$PWD}" && pwd)

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
cd "${workdir}"

if [[ ! -f ${WINE_TARBALL} ]]; then
	curl -fL -o "${WINE_TARBALL}" "${WINE_URL}"
fi
tar xf "${WINE_TARBALL}"

cd "wine-${WINE_VERSION}"
patch -p1 <"${HERE}/wine-xim-spot-callbacks.patch"
patch -p1 <"${HERE}/wine-xim-query-caret.patch"
patch -p1 <"${HERE}/wine-xim-point-line-bottom.patch"
patch -p1 <"${HERE}/wine-imm32-no-ime-ui-window.patch"
patch -p1 <"${HERE}/explorer-systray-foreground.patch"

mkdir -p build
cd build
../configure --enable-archs=x86_64 --disable-tests

make -j"$(nproc)" dlls/winex11.drv/all dlls/imm32/all

# 顶层 Makefile 给 explorer 的链接命令带了 -Wl,--wine-builtin（给 wine 自己的
# 安装目录用）。带这个标记的 PE 被 explorer.exe=n 按 native 加载时会以
# c0000135 起不来。只改 explorer 这一条链接规则，去掉标记重链一次。
make -j"$(nproc)" programs/explorer/x86_64-windows/explorer.exe
sed -i '/-mwindows -municode programs\/explorer\// s/ -Wl,--wine-builtin//' Makefile
rm -f programs/explorer/x86_64-windows/explorer.exe
if make -n programs/explorer/x86_64-windows/explorer.exe | grep -q -- '--wine-builtin'; then
	echo 'explorer link rule still carries --wine-builtin' >&2
	exit 1
fi
make -j"$(nproc)" programs/explorer/x86_64-windows/explorer.exe

build_version=$(./wine --version 2>/dev/null || true)

install -Dm755 dlls/winex11.drv/winex11.so "${OUTPUT}/winex11-xim-spot.so"
strip -s "${OUTPUT}/winex11-xim-spot.so"

install -Dm755 dlls/imm32/x86_64-windows/imm32.dll \
	"${OUTPUT}/imm32-no-ime-ui-window.dll"
x86_64-w64-mingw32-strip -s "${OUTPUT}/imm32-no-ime-ui-window.dll"

install -Dm755 programs/explorer/x86_64-windows/explorer.exe \
	"${OUTPUT}/explorer-systray-foreground.exe"
x86_64-w64-mingw32-strip -s "${OUTPUT}/explorer-systray-foreground.exe"

printf 'built wine-fix artifacts for %s into %s\n' \
	"${build_version:-wine-${WINE_VERSION}}" "${OUTPUT}"
