#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Apply the LYT T68M daughterboard DTS patch (SATA2 + SDIO WiFi AIC8800)
# for ImmortalWrt (DTS path/name differs from iStoreOS)

set -e

echo ">>> diy-part1: pwd=$(pwd)"
echo ">>> diy-part1: GITHUB_WORKSPACE=$GITHUB_WORKSPACE"

# =====================================================================
# 修复内核 md5 校验码(vermagic)：采用 OpenWrt 官方源内核模块 hash
#   内核模块能否安装取决于 kernel 包版本里的 vermagic 是否与官方软件源
#   一致。自编固件内核 .config 与官方不同 → vermagic 不同 → opkg 判定
#   不匹配而装不上。kernel-defaults.mk 会优先使用源码根 .vermagic(若存在),
#   否则才按本机 .config 计算。这里直接写入官方 hash 强制一致。
#   (与 lyw/lyw-istoreos 仓库 fe29a88/c77e553 同法)
# =====================================================================
hash_value=""
# 解析官方 ImmortalWrt release 版本: 优先取 version.mk 的 VERSION_REPO 行(如 .../releases/25.12.1),
# 否则回退 requests 行/package/base-files
Releases_version=""
if [ -f include/version.mk ]; then
    Releases_version=$(sed -n 's|.*immortalwrt.org/releases/\([0-9.]*\).*|\1|p' include/version.mk | head -1)
fi
if [ -z "$Releases_version" ]; then
    Releases_version=$(cat package/base-files/image-config.in 2>/dev/null | sed -n 's|.*releases/\([^"]*\)".*|\1|p')
fi
echo ">>> diy-part1: OpenWrt releases 版本 = ${Releases_version:-未知}"

if [ -n "$Releases_version" ]; then
    for base in \
        "https://downloads.immortalwrt.org/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.cernet.edu.cn/immortalwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.ustc.edu.cn/immortalwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" ; do
        http_value=$(wget -qO- --timeout=20 "$base" 2>/dev/null || true)
        hash_value=$(echo "$http_value" | sed -n 's/.*-\([0-9a-f]\{32\}\)\/*.*/\1/p' | head -1)
        if [ -n "$hash_value" ]; then
            echo ">>> diy-part1: 从 $base 抓到官方 kmod hash = $hash_value"
            break
        fi
    done
fi

if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[0-9a-f]{32}$ ]] && [ -f include/version.mk ]; then
    echo "$hash_value" > .vermagic
    echo ">>> diy-part1: 已写入源码根 .vermagic = $hash_value (官方源 kmod 可装)"
else
    echo ">>> diy-part1: 未抓到官方 kmod hash, 将按本机 .config 计算 vermagic(官方源 kmod 可能装不上)"
fi
echo ">>> diy-part1: --------------------------------------------------"

PATCH="$GITHUB_WORKSPACE/custom/0001-rockchip-lyt-t68m-enable-sata2-sdio-wifi.patch"
DTS=target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-lyt-t68m.dts

if [ ! -f "$PATCH" ]; then
    echo "!!! diy-part1: patch file missing: $PATCH"
    exit 1
fi

if [ ! -f "$DTS" ]; then
    echo "!!! diy-part1: target dts not found at $DTS (in $(pwd))"
    exit 1
fi

echo ">>> diy-part1: normalizing patch (literal \\t -> real TAB, strip CR)"
sed -i 's/\\t/\t/g' "$PATCH"
sed -i 's/\r$//' "$PATCH"
LIT=$(grep -c '\\t' "$PATCH" || true)
echo ">>> diy-part1: literal backslash-t remaining: ${LIT:-0}"

echo ">>> diy-part1: applying DTS patch ($PATCH) => $DTS"
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
    echo ">>> diy-part1: trying git apply"
    if git apply --check --verbose "$PATCH" 2>&1; then
        git apply "$PATCH"
        echo ">>> diy-part1: git apply OK"
    else
        echo "!!! diy-part1: git apply --check failed, falling back to patch -p1"
        patch -p1 --batch --fuzz=0 -i "$PATCH"
        echo ">>> diy-part1: patch -p1 OK (fallback)"
    fi
else
    echo ">>> diy-part1: git not available, using patch -p1"
    patch -p1 --batch --fuzz=0 -i "$PATCH"
    echo ">>> diy-part1: patch -p1 OK"
fi

echo ">>> diy-part1: verifying DTS markers"
for marker in '&sata2 {' 'sdio_pwrseq: sdio-pwrseq {' '&sdmmc2 {' 'wifi_enable_h: wifi-enable-h {'; do
    if grep -qF "$marker" "$DTS"; then
        echo "    marker OK: $marker"
    else
        echo "!!! diy-part1: marker NOT FOUND: $marker"
        exit 1
    fi
done

echo ">>> diy-part1: DTS patch applied and verified OK"

echo ">>> diy-part1: v2 overlay (free combphy2 for SATA2 + keep miniPCIe rail powered)"
cat >> "$DTS" <<'EOF'

&pcie2x1 {
	status = "disabled";
};

&vcc3v3_minipcie {
	regulator-always-on;
	regulator-boot-on;
};
EOF

echo ">>> diy-part1: verifying v2 markers"
for marker in '&pcie2x1 {' 'status = "disabled";' '&vcc3v3_minipcie {' 'regulator-always-on;' 'regulator-boot-on;'; do
    if grep -qF "$marker" "$DTS"; then
        echo "    v2 marker OK: $marker"
    else
        echo "!!! diy-part1: v2 marker NOT FOUND: $marker"
        exit 1
    fi
done

echo ">>> diy-part1: v2 overlay applied and verified OK"

echo ">>> diy-part1: writing customfeeds.list (iStore store run-time source)"
# 让编译出的固件自带正确的 iStore 运行期源 (store 是 linkease 第三方, 官方 distfeeds 无此包,
# 故在官方自定义入口 customfeeds.list 里写入正确的 istoreos 源)。
# 该文件编译进 /etc/apk/repositories.d/customfeeds.list, 且 sysupgrade 保留。
CFEED_LUA=package/system/apk/files/customfeeds.list
if [ -f "$CFEED_LUA" ]; then
    cat > "$CFEED_LUA" <<'EOF'
# add your custom package feeds here
#
# http://www.example.com/path/to/files/packages.adb

# ---- iStore (lyw-immortalwrt) ----
# store 官方第三方运行期源 (其余 diskman/video 包已在官方 packages 源, 无需独立源)
https://istore.istoreos.com/repo-apk/all/store/packages.adb
EOF
    echo ">>> diy-part1: customfeeds.list written:"
    cat "$CFEED_LUA"
else
    echo "!!! diy-part1: customfeeds.list template not found: $CFEED_LUA"
fi
echo ">>> diy-part1: customfeeds.list write done"
