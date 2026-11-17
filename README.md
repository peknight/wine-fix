# wine-fix

给发行版 Wine 打的一小组补丁，按进程挂载、用完即走：系统的
`/usr/lib/wine` 和用户的 `WINEPREFIX` 都不会被改写，也不需要自己编译整份
wine。

目前包含三处修复，细节见 [PATCHES.md](PATCHES.md)：

| 补丁 | 治的现象 |
|------|----------|
| `winex11-xim-spot` | 中文能打，但输入法候选框贴在窗口左下角，不跟随光标 |
| `imm32-no-ime-ui-window` | Chromium/Electron 已经内联画了组字串，Wine 又在窗口左下角多画一份 |
| `explorer-systray-foreground` | 托盘图标右键没反应，或者右键菜单弹不出来 |

## 用法

凡是原本 `wine xxx` 的地方，换成 `wine-fix-run xxx`，参数和退出码原样透传：

```bash
wine-fix-run winecfg
wine-fix-run /usr/lib/myapp/app/MyApp.exe
```

应用启动器里把 wine 的路径换掉就行：

```bash
readonly WINE_BIN='/usr/bin/wine-fix-run'
exec "${WINE_BIN}" MyApp.exe "$@"
```

看本机实际生效情况：

```bash
wine-fix-status
```

它会打印补丁版本、系统 wine 版本是否匹配、准备挂哪些文件、以及当前
`wineserver` 是不是从 `wine-fix-run` 起来的。

## 怎么做的

Wine 的 unix 库只按「发行版库目录 → `WINEDLLPATH`」的顺序找，`WINEDLLPATH`
覆盖不了系统目录；PE 内置库在建 prefix 时会被复制进
`drive_c/windows/system32`，之后一直从那里加载。所以 `wine-fix-run` 用
`bwrap` 起一个只属于本次启动的挂载命名空间，把补丁产物单点挂到这两处：

```bash
bwrap --dev-bind / / \
    --ro-bind winex11-xim-spot.so  <wine>/x86_64-unix/winex11.so \
    --ro-bind imm32-...dll         <wine>/x86_64-windows/imm32.dll \
    --ro-bind imm32-...dll         <prefix>/drive_c/windows/system32/imm32.dll \
    wine ...
```

`wineserver` 是第一次启动时由这套命名空间里的 wine 拉起来的，它 fork 出来的
进程都在同一套挂载里，所以 Electron 的多进程也看得到补丁。反过来说，装完
或升级完 `wine-fix` 之后，**要把应用完全退出再启动**（连同它的 `wineserver`），
否则新进程仍然挂在旧的命名空间上。`wine-fix-status` 会把这种情况指出来。

## 版本绑定

`winex11` 是 unix 库，ABI 与 wine 版本绑定，所以包里的产物是按某个具体
wine 版本编的，`/usr/lib/wine-fix/wine-version` 记着这个版本。运行时
`wine-fix-run` 拿 `wine --version` 跟它比对，不一致就不挂 `winex11`（`imm32`
和 `explorer` 是 PE 镜像，照挂）；`bwrap` 不可用、或者一份都挂不上时，打一行
原因，然后**退回原版 wine**。功能不会坏，只是补丁不生效（候选框回到左下角
之类）。

所以 wine 升版后要先重编产物：

```bash
./build.sh                     # 需要 wine-11.22.tar.xz，或用 WINE_TARBALL_URL 指镜像
```

然后把 PKGBUILD 里的 `pkgver` 和 `sha256sums` 一起改掉。

## 环境变量

| 变量 | 作用 |
|------|------|
| `WINE_FIX_WINE` | 要包装的 wine，默认 `/usr/bin/wine` |
| `WINE_FIX_DISABLE` | 逗号分隔，跳过某项：`winex11`、`imm32`、`explorer` |
| `WINEPREFIX` | 照旧；用来定位 prefix 里被复制的那份 dll |

## 边界

这个包只替换 wine 自己的二进制。下面这些属于应用侧、留在应用包里：

- 托盘图标的 X11 shape 修正（`LD_PRELOAD` 小库，和具体桌面环境、合成器有关）
- 托盘菜单“点外面不消失”的 X11 + Win32 一对 helper（要认具体应用的窗口类）
- 字体替换、协议转发器、图标、desktop 文件这类打包事项
