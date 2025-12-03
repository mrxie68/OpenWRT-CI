#!/bin/bash

### =========================
### ImmortalWrt 编译前自定义脚本
### 支持修改：主题 / IP / WiFi / 主机名 / root 密码
### 通过环境变量传入：
### WRT_THEME, WRT_IP, WRT_MARK, WRT_DATE, WRT_SSID, WRT_WORD,
### WRT_NAME, WRT_PACKAGE, WRT_TARGET, WRT_CONFIG, WRT_PASSWD
### =========================

# 修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

# 修改 immortalwrt.lan 关联 IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")

# 添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

# WiFi 配置文件路径
WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -f "$WIFI_SH" ]; then
    # 修改 WiFi 名称
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
    # 修改 WiFi 密码
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
    sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
    sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
    sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
    sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

# 修改默认 IP 和主机名
CFG_FILE="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

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
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
    echo "CONFIG_FEED_nss_packages=n" >> ./.config
    echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
    echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
    echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
    echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
    if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
    else
        echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
    fi
    if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
        find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
        echo "qualcommax set up nowifi successfully!"
    fi
fi

# =========================
# 修改 root 登录密码
# =========================
if [ -n "$WRT_PASSWD" ]; then
    PASSWD_HASH=$(openssl passwd -1 "$WRT_PW")
    SHADOW_FILE="./package/base-files/files/etc/shadow"

    # 如果 etc/shadow 不存在，先创建
    if [ ! -f "$SHADOW_FILE" ]; then
        mkdir -p "$(dirname "$SHADOW_FILE")"
        echo "root:*:0:0:99999:7:::" > "$SHADOW_FILE"
    fi

    sed -i "s|^root:[^:]*:|root:${PASSWD_HASH}:|" "$SHADOW_FILE"
    echo "已将 root 密码设置为: $WRT_PASSWD"
fi
# 强制开启 Wifi (legacy config)
   sed -i 's/disabled=1/disabled=0/g' /etc/config/wireless 2>/dev/null
