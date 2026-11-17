# 补丁说明

三份产物都来自 Wine 11.22 源码，各自只改一处。重建方法统一见
[`build.sh`](build.sh)。

## 1. 输入法候选框跟随光标（winex11）

**产物**：`winex11-xim-spot.so`（来自 `dlls/winex11.drv`，替换
`<wine>/x86_64-unix/winex11.so`）

**现象**：中文能打，但 ibus 的候选窗总出现在窗口左下角（`x` 等于窗口左边，
`y` 等于窗口底边），光标移到哪都一样。

**原因**：两段，缺一段都不行。

一是 wine 建 XIC 时默认选 `XIMPreeditCallbacks | XIMStatusCallbacks` 风格
（组字串交给应用自己画，最接近 Windows 的 IMM 语义）。而
`X11DRV_SetIMECompositionRect()` 只在 `XIMPreeditPosition` 风格下才把光标
位置转成 `XNSpotLocation` 发给输入法，callbacks 风格直接 `return FALSE`。
ibus 的 XIM 前端收不到 spot 时退回 `XTranslateCoordinates(w, root, 0,
w.height)`，也就是窗口左下角。

二是这条链路上根本没人给 wine 光标位置。Chromium 138（Electron 37）里
`ui/base/ime/win/imm32_manager.cc` 已经删了，也不再调
`ImmSetCompositionWindow`；真正的位置出口只剩
`WM_IME_REQUEST / IMR_QUERYCHARPOSITION`——应用收到这个请求时才用
`TextInputClient::GetCaretBounds()` 现算一个屏幕矩形回过去。wine 从来不问，
位置就一直是空的。

**改法**：

- `wine-xim-query-caret.patch`：`post_ime_update()` 在下发组字串前后各问一次
  应用要 `IMECHARPOSITION`（组字开始 `xic_preedit_start` 时再问一次），拿到
  屏幕坐标后交给 `X11DRV_SetIMECompositionRect()`。只在当前线程的窗口上
  `SendMessage`，避免跨线程阻塞输入线程。
- `wine-xim-spot-callbacks.patch`：把上面那个风格判断放宽成
  `XIMPreeditPosition | XIMPreeditCallbacks`，两种风格都发 `XNSpotLocation`，
  组字方式仍是 callbacks。

**spot 的纵向位置**：ibus 的 XIM 前端把 `XNSpotLocation` 直接当成候选窗位置，
callbacks 模式下它拿不到预编辑高度。spot 取光标行上沿（`pos.pt.y`）时候选窗
压住正在输入的那行；取行底（`pos.pt.y + pos.cLineHeight`）后落到下一行，和
GTK 应用一致。

**验证**：CDP 读输入框光标矩形，和日志里的 `app caret rect`、`xdotool
getwindowgeometry` 量到的 `ibus-ui-gtk3` 候选窗位置对齐；切换光标所在行时
候选窗跟着走。

**注意**：`InputStyle=overthespot` 不是解法——它换来 `XIMPreeditPosition`
风格，但组字串不再回传给应用，候选窗位置照样不对。

## 2. 不再重复画组字串（imm32）

**产物**：`imm32-no-ime-ui-window.dll`（来自 `dlls/imm32`，替换
`<wine>/x86_64-windows/imm32.dll` 和 prefix 里的
`drive_c/windows/system32/imm32.dll`）

**现象**：输入法工作正常，候选框位置也对，但焦点窗口左下角（窗口外、紧贴
窗口下面）额外画着正在输入的那几个字，和输入框里内联的那份重复。

**原因**：`dlls/imm32/ime.c` 的 `ime_ui_update_window()` 在
`CFS_DEFAULT` 时会把组字串画进一个自己的 IME UI 小窗，按 Windows 的老规矩
摆在焦点窗口左下角。Chromium/Electron 自己已经在页面里内联画了同一串字，
于是出现两份。实测那个窗口是 42x36、`WM_CLASS=workbuddy.exe`、
`WM_TRANSIENT_FOR` 指向应用主窗口，里面就是两个 8x13 字形。

**改法**：`wine-imm32-no-ime-ui-window.patch` 让
`ime_ui_update_window()` 始终 `ShowWindow( hwnd, SW_HIDE )`。组字串仍然照常
经 `WM_IME_COMPOSITION` 送进应用，只是不再画那份回退 UI。

**验证**：`xwininfo -root -tree` 里不再出现 42x36 的 IME UI 窗，左下角也没有
多出来的字；中文输入、候选框位置都不受影响。

**注意**：这个改动假定应用自己画组字串。真给不画 preedit 的老 Win32 程序用，
会把回退显示一起关掉——用 `WINE_FIX_DISABLE=imm32` 跳过。

## 3. 托盘右键菜单弹不出来（explorer）

**产物**：`explorer-systray-foreground.exe`（来自 `programs/explorer`，替换
`<wine>/x86_64-windows/explorer.exe` 和 prefix 里的
`drive_c/windows/system32/explorer.exe`）

**现象**：托盘图标单击、双击都正常，右键毫无反应，`xwininfo` 里看不到新的
菜单窗口。

**原因**：explorer 收到 `WM_RBUTTONUP` 后先把点击 `SendMessageW(TTM_RELAYEVENT)`
转发，再 `notify_owner()` 给应用。这条消息走 explorer 自己的输入队列，`user_time`
比应用队列里的新；Electron 的托盘实现随后调用 `SetForegroundWindow()`，而
wineserver 的 `set_foreground_window()` 会拿调用方 input 的 `user_time` 跟
当前前台比较，小的一方直接返回 `STATUS_ACCESS_DENIED`。Electron 收到失败就
放弃 `NotifyIcon::PopUpContextMenu()`，菜单窗口根本不会创建。

**改法**：`explorer-systray-foreground.patch` 在转发前替应用抢一次前台
（`SetForegroundWindow( icon->owner )`，只在 `WM_RBUTTONDOWN`）。explorer
是桌面窗口的所属进程，这一步不会被时间检查拒掉；应用成了前台之后自己再抢
就通过了。只对 button down 生效，否则松开时会把刚弹出的菜单顶得失活，
Esc 和点外面都关不掉它。

**注意**：wine 顶层 Makefile 给 explorer 的链接命令带 `-Wl,--wine-builtin`，
产物带 `Wine builtin DLL` 标记，被 `explorer.exe=n` 按 native 加载时会以
`c0000135` 起不来。`build.sh` 去掉这个标记重链一次。

## 三份产物的落地路径

```
/usr/lib/wine-fix/winex11-xim-spot.so
/usr/lib/wine-fix/imm32-no-ime-ui-window.dll
/usr/lib/wine-fix/explorer-systray-foreground.exe
/usr/lib/wine-fix/wine-version          # 形如 wine-11.22
```

`wine-fix-run` 在运行时把它们挂到真实路径上，见 [README.md](README.md)。
