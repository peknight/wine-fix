# shellcheck shell=bash
# wine-fix-run 和 wine-fix-status 共用的只读探测逻辑。

readonly WINE_FIX_LIBDIR='/usr/lib/wine-fix'
readonly WINE_FIX_WINE="${WINE_FIX_WINE:-/usr/bin/wine}"

wf_message() {
	printf 'wine-fix: %s\n' "$*" >&2
}

# 补丁产物是按哪个 wine 版本编的，形如 "wine-11.22"
wf_stamp_version() {
	local file="${WINE_FIX_LIBDIR}/wine-version"

	[[ -r ${file} ]] || return 1
	cat "${file}"
}

wf_wine_version() {
	"${WINE_FIX_WINE}" --version 2>/dev/null
}

# winex11 是 unix 库，ABI 与版本绑定，只有版本完全一致才敢挂。imm32 和
# explorer 是 PE 镜像，跨小版本一般可用，不在这里拦。
wf_version_matches() {
	local stamp version

	stamp=$(wf_stamp_version) || return 1
	version=$(wf_wine_version) || return 1
	[[ ${version} == "${stamp}" ]]
}

# wine 的库目录：unix 库在 <dir>/x86_64-unix，PE 库在 <dir>/x86_64-windows
wf_find_lib_dir() {
	local dir

	for dir in /usr/lib/wine /usr/lib64/wine /usr/lib/x86_64-linux-gnu/wine \
		/opt/wine-stable/lib/wine /opt/wine-devel/lib/wine /opt/wine-staging/lib/wine; do
		if [[ -f "${dir}/x86_64-unix/ntdll.so" ]]; then
			printf '%s\n' "${dir}"
			return 0
		fi
	done

	# 非发行版布局：wine 在 /opt/xxx/bin，库在 /opt/xxx/lib/wine
	dir=$(cd "$(dirname "${WINE_FIX_WINE}")/../lib/wine" 2>/dev/null && pwd) || return 1
	if [[ -f "${dir}/x86_64-unix/ntdll.so" ]]; then
		printf '%s\n' "${dir}"
		return 0
	fi
	return 1
}

wf_prefix() {
	printf '%s\n' "${WINEPREFIX:-${HOME}/.wine}"
}

# 某个 prefix 的 wineserver 进程号。wineserver 的 -p 是 persistent，不是打印
# pid，所以按进程环境里的 WINEPREFIX 认。
wf_find_server_pid() {
	local prefix=$1 pid

	for pid in $(pgrep -x wineserver 2>/dev/null); do
		if tr '\0' '\n' <"/proc/${pid}/environ" 2>/dev/null |
			grep -qxF "WINEPREFIX=${prefix}"; then
			printf '%s\n' "${pid}"
			return 0
		fi
	done
	return 1
}

# WINE_FIX_DISABLE=imm32,explorer 之类，逗号分隔
wf_disabled() {
	local item
	local IFS=','

	[[ -n ${WINE_FIX_DISABLE:-} ]] || return 1
	for item in ${WINE_FIX_DISABLE}; do
		[[ ${item} == "$1" ]] && return 0
	done
	return 1
}

# 输出 "<补丁文件>\t<系统里的目标路径>"，一行一个挂载点。只列真实存在的目标，
# bwrap 的 --ro-bind 要求目标存在。
#
# wine 的 PE 内置库在建 prefix 时会复制进 drive_c/windows/system32，之后一直
# 从那里加载（+module 日志里是 C:\windows\system32\imm32.dll），所以除了系统
# 库目录，prefix 里的那份副本也要一起盖掉。新建 prefix 时还没有副本，那一份
# 由系统库目录挂载后 wineboot 复制进去。
wf_collect_mounts() {
	local lib_dir prefix target

	lib_dir=$(wf_find_lib_dir) || return 1
	prefix=$(wf_prefix)

	if ! wf_disabled winex11 && wf_version_matches &&
		[[ -f "${WINE_FIX_LIBDIR}/winex11-xim-spot.so" ]]; then
		target="${lib_dir}/x86_64-unix/winex11.so"
		if [[ -f ${target} ]]; then
			printf '%s\t%s\n' "${WINE_FIX_LIBDIR}/winex11-xim-spot.so" "${target}"
		fi
	fi

	if ! wf_disabled imm32 && [[ -f "${WINE_FIX_LIBDIR}/imm32-no-ime-ui-window.dll" ]]; then
		target="${lib_dir}/x86_64-windows/imm32.dll"
		if [[ -f ${target} ]]; then
			printf '%s\t%s\n' "${WINE_FIX_LIBDIR}/imm32-no-ime-ui-window.dll" "${target}"
		fi
		target="${prefix}/drive_c/windows/system32/imm32.dll"
		if [[ -f ${target} ]]; then
			printf '%s\t%s\n' "${WINE_FIX_LIBDIR}/imm32-no-ime-ui-window.dll" "${target}"
		fi
	fi

	if ! wf_disabled explorer && [[ -f "${WINE_FIX_LIBDIR}/explorer-systray-foreground.exe" ]]; then
		target="${lib_dir}/x86_64-windows/explorer.exe"
		if [[ -f ${target} ]]; then
			printf '%s\t%s\n' "${WINE_FIX_LIBDIR}/explorer-systray-foreground.exe" "${target}"
		fi
		target="${prefix}/drive_c/windows/system32/explorer.exe"
		if [[ -f ${target} ]]; then
			printf '%s\t%s\n' "${WINE_FIX_LIBDIR}/explorer-systray-foreground.exe" "${target}"
		fi
	fi
}
