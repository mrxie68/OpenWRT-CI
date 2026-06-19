#!/bin/bash
set -euo pipefail

### =========================
### ImmortalWrt 编译前自定义脚本
### 支持修改：主题 / IP / WiFi / 主机名 / root 密码
### 通过环境变量传入：
### WRT_THEME, WRT_IP, WRT_MARK, WRT_DATE, WRT_SSID, WRT_WORD,
### WRT_NAME, WRT_PACKAGE, WRT_TARGET, WRT_CONFIG, WRT_PW
### =========================

# 修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +

# 修改 immortalwrt.lan 关联 IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +

# 添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

# WiFi 配置文件路径
WIFI_SH=$(find ./target/linux/qualcommax/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" -print -quit 2>/dev/null || true)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -f "$WIFI_SH" ]; then
    # 修改 WiFi 名称
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
    # 修改 WiFi 密码
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"
    sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
    sed -i "s/country='.*'/country='CN'/g" "$WIFI_UC"
    sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" "$WIFI_UC"
fi

# 修改默认 IP 和主机名
CFG_FILE="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"

# 配置 luci 主题及语言
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

# 额外插件
if [ -n "$WRT_PACKAGE" ]; then
    echo -e "$WRT_PACKAGE" >> ./.config
fi

# 高通平台调整
IS_WIFI_NO=0
WRT_CONFIG_LC="${WRT_CONFIG,,}"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "CONFIG_FEED_nss_packages=n" >> ./.config
    echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
    # echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
    # echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
    echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
    if [[ "$WRT_CONFIG_LC" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
    if [[ "$WRT_CONFIG_LC" == *"nonss"* ]]; then
        cat <<'EOF' >> ./.config
# CONFIG_ATH11K_NSS_SUPPORT is not set
# CONFIG_ATH11K_NSS_MESH_SUPPORT is not set
# CONFIG_PACKAGE_MAC80211_NSS_SUPPORT is not set
# CONFIG_NSS_DRV_WIFIOFFLOAD_ENABLE is not set
# CONFIG_NSS_DRV_WIFI_EXT_VDEV_ENABLE is not set
# CONFIG_NSS_DRV_WIFI_MESH_ENABLE is not set
EOF
        echo "qualcommax WiFi NSS offload disabled, WiFi drivers kept."
    fi
    if [[ "$WRT_CONFIG_LC" == *"wifi-no"* ]]; then
        IS_WIFI_NO=1
        cat <<'EOF' >> ./.config
# CONFIG_ATH11K_NSS_SUPPORT is not set
# CONFIG_ATH11K_NSS_MESH_SUPPORT is not set
# CONFIG_PACKAGE_MAC80211_NSS_SUPPORT is not set
# CONFIG_NSS_DRV_WIFIOFFLOAD_ENABLE is not set
# CONFIG_NSS_DRV_WIFI_EXT_VDEV_ENABLE is not set
# CONFIG_NSS_DRV_WIFI_MESH_ENABLE is not set
# CONFIG_PACKAGE_kmod-ath is not set
# CONFIG_PACKAGE_kmod-ath11k is not set
# CONFIG_PACKAGE_kmod-ath11k-ahb is not set
# CONFIG_PACKAGE_kmod-ath11k-pci is not set
# CONFIG_PACKAGE_kmod-cfg80211 is not set
# CONFIG_PACKAGE_kmod-mac80211 is not set
# CONFIG_PACKAGE_kmod-qca-nss-drv-wifi-meshmgr is not set
# CONFIG_PACKAGE_ipq-wifi-jdcloud_re-ss-01 is not set
# CONFIG_PACKAGE_wireless-regdb is not set
# CONFIG_PACKAGE_ath11k-firmware-ipq6018 is not set
# CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt is not set
# CONFIG_PACKAGE_ath11k-firmware-qcn9074 is not set
# CONFIG_PACKAGE_ath11k-firmware-qcn9074-ddwrt is not set
# CONFIG_PACKAGE_wpad is not set
# CONFIG_PACKAGE_wpad-basic-mbedtls is not set
# CONFIG_PACKAGE_wpad-openssl is not set
# CONFIG_PACKAGE_hostapd-common is not set
EOF
        find ./target/linux/qualcommax/ -type f \( -iname "*.dts" -o -iname "*.dtsi" \) ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
        IPQ60XX_IMAGE_MK="./target/linux/qualcommax/image/ipq60xx.mk"
        if [ -f "$IPQ60XX_IMAGE_MK" ]; then
            sed -i '/^define Device\/jdcloud_re-ss-01$/,/^endef$/ s/^[[:space:]]*DEVICE_PACKAGES[[:space:]]*[:+]\?=.*/        DEVICE_PACKAGES := -kmod-ath -kmod-ath11k -kmod-ath11k-ahb -kmod-ath11k-pci -kmod-cfg80211 -kmod-mac80211 -ath11k-firmware-ipq6018 -ath11k-firmware-ipq6018-ddwrt -ath11k-firmware-qcn9074 -ath11k-firmware-qcn9074-ddwrt -ipq-wifi-jdcloud_re-ss-01 -wireless-regdb -wpad -wpad-basic-mbedtls -wpad-openssl -hostapd-common -kmod-qca-nss-drv-wifi-meshmgr/' "$IPQ60XX_IMAGE_MK"
            if awk '/^define Device\/jdcloud_re-ss-01$/ { in_device=1 } in_device && /^[[:space:]]*DEVICE_PACKAGES[[:space:]]*[:+]?=[[:space:]]*ipq-wifi-jdcloud_re-ss-01/ { bad=1 } in_device && /^endef$/ { in_device=0 } END { exit bad ? 0 : 1 }' "$IPQ60XX_IMAGE_MK"; then
                echo "ERROR: jdcloud_re-ss-01 still has positive WiFi device packages in WIFI-NO build."
                exit 1
            fi
            echo "jdcloud_re-ss-01 device WiFi packages removed for WIFI-NO."
        fi
        echo "qualcommax WiFi packages and DTS references disabled."
    fi
fi

# =========================
# 修改 root 登录密码
# =========================

if [ -n "$WRT_PW" ] && [ "$WRT_PW" != "无" ]; then
    PASSWD_HASH=$(openssl passwd -1 "$WRT_PW")
    SHADOW_FILE="./package/base-files/files/etc/shadow"

    # 如果 etc/shadow 不存在，先创建
    if [ ! -f "$SHADOW_FILE" ]; then
        mkdir -p "$(dirname "$SHADOW_FILE")"
        echo "root:*:0:0:99999:7:::" > "$SHADOW_FILE"
    fi

    sed -i "s|^root:[^:]*:|root:${PASSWD_HASH}:|" "$SHADOW_FILE"
    echo "已设置 root 密码。"
fi

# =========================
# 强制开启 Wifi (通用方法)
# =========================
mkdir -p ./package/base-files/files/etc/uci-defaults/
if [ "$IS_WIFI_NO" -eq 0 ]; then
cat <<EOF > ./package/base-files/files/etc/uci-defaults/99-open-wifi
#!/bin/sh
# 开启所有无线接口
uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci set wireless.radio2.disabled=0
uci commit wireless
exit 0
EOF
chmod +x ./package/base-files/files/etc/uci-defaults/99-open-wifi
fi

# =========================
# 轻量性能优化
# =========================
mkdir -p ./package/base-files/files/etc/sysctl.d/
cat <<EOF > ./package/base-files/files/etc/sysctl.d/99-performance.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
vm.swappiness=60
EOF

cat <<EOF > ./package/base-files/files/etc/uci-defaults/98-performance-tuning
#!/bin/sh
# 多核设备开启 packet steering，提升高并发转发时的 CPU 利用率。
uci -q set network.globals.packet_steering='1'
uci -q commit network

# 保持系统日志缓冲适中，减少常驻内存占用。
uci -q set system.@system[0].log_size='64'
uci -q commit system
exit 0
EOF
chmod +x ./package/base-files/files/etc/uci-defaults/98-performance-tuning
