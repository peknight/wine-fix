# Maintainer: Peknight <JKpeknight@gmail.com>

pkgname=wine-fix
pkgver=11.22
pkgrel=3
pkgdesc='按进程挂载的 wine 补丁：输入法候选框跟随光标、Electron 不重复画组字串、托盘右键菜单可用 | per-process wine patches for IME and tray behaviour'
arch=('x86_64')
url='https://github.com/peknight/wine-fix'
license=('LGPL-2.1-or-later')
options=(!strip !debug)

depends=(
    'wine>=11.22'
    'bubblewrap'   # 单点挂载补丁库，见 README
)

source=(
    'wine-fix-run'
    'wine-fix-status'
    'wine-fix-common.sh'
    'winex11-xim-spot.so'
    'imm32-no-ime-ui-window.dll'
    'explorer-systray-foreground.exe'
    'wine-xim-spot-callbacks.patch'
    'wine-xim-query-caret.patch'
    'wine-imm32-no-ime-ui-window.patch'
    'explorer-systray-foreground.patch'
    'build.sh'
    'PATCHES.md'
    'LICENSE'
)
sha256sums=(
    'fee98401fb50ae1ab2ce0ac63fcf116a58cda55b894c250fc7c0d8a57fbff0e5'
    'e328fa273cebf9ab668d46e68c025174fe7923285e50239b14aa00e02615cb1e'
    '0017661bb15b2d35ca57f857deef92b454c1333b19bfe2032411f579f3f5cce1'
    'ebf6a69dd66afa1d7ccade34381c104ea2c4480fed5ab309c7d96a5c1ce4b779'
    '4d210dfebff41287ac45fd487802b65b9772e73e1a1913919b33923adf44c8c9'
    '435bb67aa7f5ae618d462a2706ebb1dcb781b039696c98440f38280ad6a6fe5f'
    '1b25cd613ec4eceeb1063fc354203014c9692d17407022904e4f79b0e94281fa'
    '05cf8eeb98161ffcfe6daf1a4bc3565b90f178dc4260a1e9bec7c27007c46a1d'
    '6f4661e9e9d56bf961520b7a522707be91b86f8c12081746c77709323591532f'
    'ee62a44fc8b15607bd62f232f93eb7f9681fb339556745a0002c0a4a93bc1e00'
    'cb167d65d4482c7b9174a1c927e2ea8afa9bc6fb41187ecb816b6986be829ecb'
    'e3718549992a1cdcfe9b342735ccf6bc25292bd38b4a94679459c2c31e9381da'
    'aabb62a6dd8102f966a330d3e0587106fa9dfcdb82ef075c289a745c2aaf7031'
)

package() {
    local lib="$pkgdir/usr/lib/$pkgname"
    local share="$pkgdir/usr/share/$pkgname"

    install -Dm755 "$srcdir/wine-fix-run" "$pkgdir/usr/bin/wine-fix-run"
    install -Dm755 "$srcdir/wine-fix-status" "$pkgdir/usr/bin/wine-fix-status"
    install -Dm644 "$srcdir/wine-fix-common.sh" "$lib/wine-fix-common.sh"

    # 三份补丁产物和它们编译时用的 wine 版本。unix 库的 ABI 与版本绑定，
    # wine-fix-run 拿 wine --version 跟这个文件比对，对不上就退回原版。
    install -Dm755 "$srcdir/winex11-xim-spot.so" "$lib/winex11-xim-spot.so"
    install -Dm644 "$srcdir/imm32-no-ime-ui-window.dll" \
        "$lib/imm32-no-ime-ui-window.dll"
    install -Dm755 "$srcdir/explorer-systray-foreground.exe" \
        "$lib/explorer-systray-foreground.exe"
    printf 'wine-%s\n' "$pkgver" >"$lib/wine-version"
    chmod 644 "$lib/wine-version"

    # 补丁源和重建脚本一起装，wine 升版后可以照着重出产物
    install -Dm644 "$srcdir/wine-xim-spot-callbacks.patch" "$share/wine-xim-spot-callbacks.patch"
    install -Dm644 "$srcdir/wine-xim-query-caret.patch" "$share/wine-xim-query-caret.patch"
    install -Dm644 "$srcdir/wine-imm32-no-ime-ui-window.patch" "$share/wine-imm32-no-ime-ui-window.patch"
    install -Dm644 "$srcdir/explorer-systray-foreground.patch" "$share/explorer-systray-foreground.patch"
    install -Dm755 "$srcdir/build.sh" "$share/build.sh"
    install -Dm644 "$srcdir/PATCHES.md" "$share/PATCHES.md"

    install -Dm644 "$srcdir/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
