#!/bin/bash
set -euo pipefail

PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

#预置HomeProxy数据
if [ -d "./homeproxy" ]; then
	echo " "

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	rm -rf ./"$HP_PATH"/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/
	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*" | head -n 1 || true)

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../"$HP_PATH"/resources/

	cd .. && rm -rf ./$HP_RULE/

	cd "$PKG_PATH" && echo "homeproxy date has been updated!"
fi

#修改argon主题字体和颜色
if [ -d "./luci-theme-argon" ]; then
	echo " "

	cd ./luci-theme-argon/

	find ./luci-theme-argon -type f -iname "*.css" -exec sed -i "/font-weight:/ { /important/! { /\/\*/! s/:.*/: var(--font-weight);/ } }" {} +
	sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" ./luci-app-argon-config/root/etc/config/argon

	cd "$PKG_PATH" && echo "theme-argon has been fixed!"
fi

#修改qca-nss-drv启动顺序
NSS_DRV="../feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
	echo " "

	sed -i 's/START=.*/START=85/g' "$NSS_DRV"

	cd "$PKG_PATH" && echo "qca-nss-drv has been fixed!"
fi

#修改qca-nss-pbuf启动顺序
NSS_PBUF="./kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
	echo " "

	sed -i 's/START=.*/START=86/g' "$NSS_PBUF"

	cd "$PKG_PATH" && echo "qca-nss-pbuf has been fixed!"
fi

#修复TailScale配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile" -print -quit 2>/dev/null || true)
if [ -f "$TS_FILE" ]; then
	echo " "

	sed -i '/\/files/d' "$TS_FILE"

	cd "$PKG_PATH" && echo "tailscale has been fixed!"
fi

#修复Rust编译失败
RUST_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile" -print -quit 2>/dev/null || true)
if [ -f "$RUST_FILE" ]; then
	echo " "

	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"

	cd "$PKG_PATH" && echo "rust has been fixed!"
fi

#修复DiskMan编译失败
DM_FILE="./luci-app-diskman/applications/luci-app-diskman/Makefile"
if [ -f "$DM_FILE" ]; then
	echo " "

	sed -i 's/fs-ntfs/fs-ntfs3/g' "$DM_FILE"
	sed -i 's/fs-ntfs33/fs-ntfs3/g' "$DM_FILE"
	sed -i '/ntfs-3g-utils /d' "$DM_FILE"

	cd "$PKG_PATH" && echo "diskman has been fixed!"
fi

#移除sb内核回溯移植补丁
SB_PATCH="../feeds/packages/net/sing-box/patches"
if [ -d "$SB_PATCH" ]; then
	echo " "

	rm -rf "$SB_PATCH"

	cd "$PKG_PATH" && echo "sing-box patches has been fixed!"
fi
# =========================
# 彻底隐藏不需要的菜单
# =========================

REMOVE_LUCI_MENU_ENTRY() {
	local ROUTE=$1
	local VIEW=${2:-}

	if [ ! -d "../feeds/luci" ]; then
		return
	fi

	find ../feeds/luci ./ -type f -path "*/root/usr/share/luci/menu.d/*.json" -print0 2>/dev/null | while IFS= read -r -d '' MENU_FILE; do
		if ! grep -q "\"$ROUTE\"\|\"$VIEW\"" "$MENU_FILE"; then
			continue
		fi

		local OLD_COUNT
		local NEW_COUNT
		local TMP_FILE

		OLD_COUNT=$(jq 'length' "$MENU_FILE")
		TMP_FILE=$(mktemp)

		jq --arg route "$ROUTE" --arg view "$VIEW" '
			with_entries(
				select(
					.key != $route
					and ((.value.action.path? // "") != $view)
					and ((.value.path? // "") != $view)
				)
			)
		' "$MENU_FILE" > "$TMP_FILE"

		NEW_COUNT=$(jq 'length' "$TMP_FILE")
		if [ "$NEW_COUNT" != "$OLD_COUNT" ]; then
			mv -f "$TMP_FILE" "$MENU_FILE"
			echo "remove luci menu entry: $ROUTE ($MENU_FILE)"
		else
			rm -f "$TMP_FILE"
		fi
	done
}

# 1. 隐藏“状态”栏中的“信道分析”: /cgi-bin/luci/admin/status/channel_analysis
REMOVE_LUCI_MENU_ENTRY "admin/status/channel_analysis" "status/channel_analysis"

# 2. 隐藏“系统”栏中的“LED 配置”：/cgi-bin/luci/admin/system/leds
REMOVE_LUCI_MENU_ENTRY "admin/system/leds" "system/leds"

# 3. 隐藏“系统”栏中的“Plugins”：/cgi-bin/luci/admin/system/plugins
REMOVE_LUCI_MENU_ENTRY "admin/system/plugins" "system/plugins"

# 4. 隐藏“网络”栏中的“网络诊断”
REMOVE_LUCI_MENU_ENTRY "admin/network/diagnostics" "network/diagnostics"

# Hide wireless menu only for no-WiFi builds: /cgi-bin/luci/admin/network/wireless
if [[ "${WRT_CONFIG,,}" == *"wifi-no"* ]]; then
	REMOVE_LUCI_MENU_ENTRY "admin/network/wireless" "network/wireless"
fi
