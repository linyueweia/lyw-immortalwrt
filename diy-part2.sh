#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 修改 openwrt 登陆地址(取消注释修改)
#sed -i 's/192.168.100.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# 修改主机名(取消注释修改)
# sed -i 's/OpenWrt/ImmortalWrt/g' package/base-files/files/bin/config_generate

# ============================================================================
# luci-app-store (iStore) ImmortalWrt 25.12 集成
#
# 真正根因(本地 defconfig 决定性复现, 2026-08-31):
#   在本地搭 ubuntu+ImmortalWrt v25.12.1 源码复现发现: luci-app-store 之所以
#   在 make defconfig 后被「静默剔除」(固件里没有 iStore), 不是 APK/opkg 体系
#   差异, 而是其 Makefile 的依赖:
#       LUCI_DEPENDS:=+curl +tar +libuci-lua +mount-utils +luci-lib-taskd
#   其中的 `+tar`(GNU tar) 在 v25.12.1 里依赖
#       +PACKAGE_TAR_XZ:xz +PACKAGE_TAR_ZSTD:libzstd +PACKAGE_TAR_BZIP2:bzip2
#       +PACKAGE_TAR_POSIX_ACL:libacl
#   而 xz/libzstd/bzip2/libacl 在该 target 默认全部 not set -> tar 被剔除
#   -> luci-app-store 依赖不满足被整体剔除, 且 defconfig 不报任何 warning。
#   修复: 去掉不可满足的 `+tar` 依赖(打破剔除链)。busybox 内置 tar(供 sysupgrade
#   用), store 运行时走 PATH 调 busybox tar 足够; curl/libuci-lua/mount-utils/
#   luci-lib-taskd 依赖均自洽可满足。
#   本地验证: 仅去掉 +tar 后 make defconfig, CONFIG_PACKAGE_luci-app-store=y
#   成功保留(curl=y 亦保留)。
# ============================================================================
echo ">>> diy-part2: luci-app-store store feed integration"
# feed install -a 已在 workflow 中做过(diy-part2 在 feeds install -a 之后执行),
# 这里确保 store 的包链接就位, 再对末尾的 Makefile 去掉不可满足的 +tar 依赖。
./scripts/feeds install -p store luci-app-store 2>&1 | tail -1 || true
STORE_MK=package/feeds/store/luci-app-store/Makefile
if [ -f "$STORE_MK" ]; then
    echo ">>> diy-part2: before -> $(grep '^LUCI_DEPENDS' "$STORE_MK")"
    # 去掉 +tar (GNU tar 依赖 xz/libzstd/bzip2/libacl 均不可满足 -> 剔除 store)
    # 最稳做法: 精确匹配 " +tar " 词/前后空格, 去掉 -tar 依赖词
    sed -i 's/ +tar / /; s/+tar / /; s/ +tar//' "$STORE_MK"
    echo ">>> diy-part2: after  -> $(grep '^LUCI_DEPENDS' "$STORE_MK")"
    grep -q '^CONFIG_PACKAGE_luci-app-store=y' .config \
        && echo ">>> diy-part2: CONFIG_PACKAGE_luci-app-store=y already in .config" \
        || echo ">>> diy-part2: ensure later (make defconfig will pull it via DIFF/DEPENDS once +tar removed)"
else
    echo "!!! diy-part2: store Makefile NOT FOUND at $STORE_MK (store feed not linked)"
fi
