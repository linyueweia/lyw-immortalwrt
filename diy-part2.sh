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
# luci-app-store (iStore) ImmortalWrt 25.12 (APK 体系) 集成
# 根因(既往排查, 血泪): ImmortalWrt 25.12.1 官方默认 USE_APK=y (APK 包体系,
#       见 config/Config-build.in), 而 linkease/istore main 的 luci-app-store
#       已适配 APK (LUCI_TITLE: "LuCI based ipk/apk store", PKG_VERSION 0.2.1-r1)。
#       以前习惯在 diy-part2 里 sed 掉其依赖 +libuci-lua 是错误方向——
#       那是在破坏官方已做好的 APK 适配, 反而让 luci-app-store 无法被
#       APK 打包纳入 manifest。正确做法: 不动依赖, 让 store 在 APK 体系下
#       通过标准 feeds 流程构建。
# 注意: feeds install 读 feeds/store.index 缓存(由 feeds update 生成),
#       这里显式重刷 index 再 install 仅作保险, 不修改任何依赖。
# ============================================================================
# 显式确认 APK 包管理(诊断用; 实际由 .config 的 CONFIG_USE_APK=y 决定)
grep -q '^CONFIG_USE_APK=y' .config && echo ">>> diy-part2: CONFIG_USE_APK=y (APK 包体系) confirmed" \
    || { echo ">>> diy-part2: WARN: CONFIG_USE_APK not set to y, forcing it"; echo 'CONFIG_USE_APK=y' >> .config; }
./scripts/feeds update -i store 2>&1 | tail -3 || true
./scripts/feeds install -p store luci-app-store 2>&1 | tail -3 || true
echo ">>> diy-part2: install store feed (deps left intact for APK) done"
if [ -d "package/feeds/store/luci-app-store" ]; then
    echo ">>> OK: luci-app-store linked into package/feeds/store/"
    # 复述官方依赖, 确认未被动过
    grep '^LUCI_DEPENDS' package/feeds/store/luci-app-store/Makefile || true
else
    echo "!!! luci-app-store NOT linked; check feeds/store.index deps (APK 体系下 store 依赖须可满足)"
fi
