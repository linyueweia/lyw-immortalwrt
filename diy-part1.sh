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
# Apply hardware enablement DTS patch
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
# ---------------------------------------------------------------------
# 官方 kmods 目录 hash 锚点（硬兜底）
#   ImmortalWrt 25.12.1 rockchip/armv8 官方软件源的内核模块版本 hash，
#   已实测 https://downloads.immortalwrt.org/releases/25.12.1/targets/rockchip/armv8/kmods/
#   下 6.12.94-1-<此hash>/packages.adb 返回 HTTP 200。
#   运行时 wget 抓取可能因网络/超时失败（CI 里表现为无输出），故一旦抓不到
#   立即回退到该已核实的官方 hash，绝不让 vermagic 静默降级。
# ---------------------------------------------------------------------
OFFICIAL_KMOD_HASH="9695dbb0de913313770c73e57b594a48"

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

# 优先在线抓取官方 hash（限时，避免长时间卡住无输出）
if [ -n "$Releases_version" ]; then
    for base in \
        "https://downloads.immortalwrt.org/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.cernet.edu.cn/immortalwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" \
        "https://mirrors.ustc.edu.cn/immortalwrt/releases/${Releases_version}/targets/rockchip/armv8/kmods/" ; do
        # 用 curl 而非 wget: 实测 wget 在该官方源上会异常卡死(超时不生效), curl 约1s稳定抓到
        http_value=$(curl -fsSL --connect-timeout 15 --max-time 25 "$base" 2>/dev/null || true)
        hash_value=$(echo "$http_value" | sed -n 's/.*-\([0-9a-f]\{32\}\)\/*.*/\1/p' | head -1)
        if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[0-9a-f]{32}$ ]]; then
            echo ">>> diy-part1: 从 $base 抓到官方 kmod hash = $hash_value"
            break
        fi
        hash_value=""
    done
fi

# 兜底: 在线抓不到(超时/无网/结构变化)则用已核实的官方 hash
if [ -z "$hash_value" ]; then
    hash_value="$OFFICIAL_KMOD_HASH"
    echo ">>> diy-part1: 在线未抓到官方 hash, 使用已核实兜底 = $hash_value (IP 受限/超时仍可编译)"
fi

if [ -n "$hash_value" ] && [[ "$hash_value" =~ ^[0-9a-f]{32}$ ]] && [ -f include/version.mk ]; then
    echo "$hash_value" > .vermagic
    echo ">>> diy-part1: 已写入源码根 .vermagic = $hash_value (官方源 kmod 可装)"

    # =================================================================
    # 增强1: patch include/kernel-defaults.mk 的 vermagic 生成行
    #   25.12.x 的 kernel-defaults.mk 在内核 configure 时用 .config.set
    #   强制重算 $(LINUX_DIR)/.vermagic (源码根 .vermagic 根本不被读取),
    #   导致 diy 写入的 hash 不生效。这里把该行改为:
    #   "若源码根 $(TOPDIR)/.vermagic 存在且非空则直接采用, 否则回退原计算"
    #   (用纯 shell 逐行重写, 避免 sed 对 $( )/[ ]/& 的转义兼容问题)
    # =================================================================
    KD=include/kernel-defaults.mk
    if [ -f "$KD" ]; then
        TMPF=$(mktemp)
        KD_NEW_LINE='{ [ -s $(TOPDIR)/.vermagic ] && cat $(TOPDIR)/.vermagic > $(LINUX_DIR)/.vermagic; } || { grep '\''=[ym]'\'' $(LINUX_DIR)/.config.set | LC_ALL=C sort | $(MKHASH) md5 > $(LINUX_DIR)/.vermagic; }'
        while IFS= read -r line; do
            case "$line" in
                *"grep '=[ym]' \$(LINUX_DIR)/.config.set"*)
                    # 注意: Makefile recipe 行必须以 TAB 开头, 这里用 printf '\t%s\n' 补回
                    printf '\t%s\n' "$KD_NEW_LINE" ;;
                *)
                    printf '%s\n' "$line" ;;
            esac
        done < "$KD" > "$TMPF" && mv "$TMPF" "$KD"
        echo ">>> diy-part1: [增强1] kernel-defaults.mk 已 patch:"
        grep -n 'vermagic' "$KD" | grep -q 'TOPDIR' && grep -n 'TOPDIR)/.vermagic' "$KD" || echo "!!! diy-part1: 未在 kernel-defaults.mk 找到 patch 结果"
    else
        echo "!!! diy-part1: $KD 不存在, 跳过增强1"
    fi

    # =================================================================
    # 增强2(patch include/kernel.mk): 把 LINUX_VERMAGIC 直接写死为官方 hash
    #   双保险: 即使 .vermagic 文件被某步流程覆盖/重算,
    #   kmod 包的版本 hash 仍取官方值。
    #   同时覆盖两种赋值形式:
    #     官方 25.12.x:  L26 "LINUX_VERMAGIC?=<占位>" 与 L49 "LINUX_VERMAGIC:=$(shell cat ...)"
    #     hanwckf 分支:  单独 "LINUX_VERMAGIC:=..." 行
    #   统一改写为 "LINUX_VERMAGIC:=<官方hash>", 使最终 make 取值无歧义。
    # =================================================================
    KM=include/kernel.mk
    if [ -f "$KM" ]; then
        TMPF=$(mktemp)
        while IFS= read -r line; do
            case "$line" in
                *LINUX_VERMAGIC?=*)  printf '  LINUX_VERMAGIC:=%s\n' "$hash_value" ;;
                *LINUX_VERMAGIC:=*)  printf '  LINUX_VERMAGIC:=%s\n' "$hash_value" ;;
                *)
                    printf '%s\n' "$line" ;;
            esac
        done < "$KM" > "$TMPF" && mv "$TMPF" "$KM"
        echo ">>> diy-part1: [增强2] kernel.mk 的 LINUX_VERMAGIC 已写死为 $hash_value:"
        grep -n 'LINUX_VERMAGIC' "$KM" || echo "!!! diy-part1: 未在 kernel.mk 找到 LINUX_VERMAGIC"
    else
        echo "!!! diy-part1: $KM 不存在, 跳过增强2"
    fi
else
    echo ">>> diy-part1: 未抓到官方 kmod hash, 将按本机 .config 计算 vermagic(官方源 kmod 可能装不上)"
fi
echo ">>> diy-part1: --------------------------------------------------"

# ============================================================
# 通用 DTS 补丁应用函数: 处理 custom/ 下任意个 rockchip dts 补丁
# 用法: apply_dts_patch <patch路径> <dts相对路径> <后置marker数组以 | 分隔(可空)>
# ============================================================
apply_dts_patch () {
    local PATCH="$1"
    local DTS="$2"
    local MARKERS="${3:-}"

    if [ ! -f "$PATCH" ]; then
        echo "!!! diy-part1: patch file missing: $PATCH"
        exit 1
    fi
    if [ ! -f "$DTS" ]; then
        echo "!!! diy-part1: target dts not found at $DTS (in $(pwd))"
        exit 1
    fi

    echo ">>> diy-part1: normalizing patch $PATCH (literal \\t -> TAB, strip CR)"
    cp "$PATCH" "$PATCH.tmp"
    sed -i 's/\\t/\t/g' "$PATCH.tmp"
    sed -i 's/\r$//' "$PATCH.tmp"
    local LIT
    LIT=$(grep -c '\\t' "$PATCH.tmp" || true)
    echo ">>> diy-part1: literal backslash-t remaining: ${LIT:-0}"

    echo ">>> diy-part1: applying DTS patch ($PATCH) => $DTS"
    if command -v git >/dev/null 2>&1 && [ -d .git ]; then
        echo ">>> diy-part1: trying git apply"
        if git apply --check --verbose "$PATCH.tmp" 2>&1; then
            git apply "$PATCH.tmp"
            echo ">>> diy-part1: git apply OK"
        else
            echo "!!! diy-part1: git apply --check failed, falling back to patch -p1"
            patch -p1 --batch --fuzz=0 -i "$PATCH.tmp"
            echo ">>> diy-part1: patch -p1 OK (fallback)"
        fi
    else
        echo ">>> diy-part1: git not available, using patch -p1"
        patch -p1 --batch --fuzz=0 -i "$PATCH.tmp"
        echo ">>> diy-part1: patch -p1 OK"
    fi
    rm -f "$PATCH.tmp"

    if [ -n "$MARKERS" ]; then
        echo ">>> diy-part1: verifying DTS markers (patch $PATCH)"
        local m
        local oldIFS="$IFS"
        IFS='|'
        for m in $MARKERS; do
            IFS="$oldIFS"
            if grep -qF "$m" "$DTS"; then
                echo "    marker OK: $m"
            else
                echo "!!! diy-part1: marker NOT FOUND: $m"
                exit 1
            fi
            IFS='|'
        done
        IFS="$oldIFS"
        echo ">>> diy-part1: markers verified OK"
    fi
}

DTS=target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-lyt-t68m.dts

# 0001: hardware enablement (已有)
apply_dts_patch \
    "$GITHUB_WORKSPACE/custom/0001-rockchip-lyt-t68m-enable-sata2-sdio-wifi.patch" \
    "$DTS" \
    '&sata2 {|sdio_pwrseq: sdio-pwrseq {|&sdmmc2 {|wifi_enable_h: wifi-enable-h {'

# 0002: 官方 PCIe3.0 修复 (vcc3v3_pi6c 独立供电 + startup-delay-us 等待 PI6C 稳定)
#       来源: istoreos commit 6c402813 "target/rockchip: lyt t68m fix pcie3.0 init"
apply_dts_patch \
    "$GITHUB_WORKSPACE/custom/0002-rockchip-lyt-t68m-fix-pcie3.0-init.patch" \
    "$DTS" \
    'vcc3v3_pi6c: vcc3v3-pi6c-regulator {|startup-delay-us = <50000>;|vin-supply = <&vcc3v3_pi6c>;|pi6c_enable_h: pi6c-enable-h {'

echo ">>> diy-part1: both DTS patches applied and verified OK"

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
