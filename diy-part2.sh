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
# luci-app-store (iStore) ImmortalWrt 25.12 (LuCI 24) 适配
# 原因: linkease/istore main 的 Makefile 依赖 +libuci-lua (老 LuCI C 库绑定),
#       而 ImmortalWrt 25.12 (LuCI 24) 无此包, 导致 make defconfig 静默把
#       luci-app-store 排除, 固件里没有 iStore。
# 实际 store 运行时用 luci.model.uci (luci-lua-runtime 提供) + luci-compat,
#       并不需要 libuci-lua, 该依赖是冗余残留。故去除并补 luci-compat/luci-lua-runtime。
# 注意: 必须在 feeds update/install 之后做 (此处即 diy-part2), 否则会被
#       feeds update 重新 clone 覆盖。
# ============================================================================
STORE_MK=feeds/store/luci/luci-app-store/Makefile
if [ -f "$STORE_MK" ]; then
    sed -i 's/ +libuci-lua//g; s/^LUCI_DEPENDS:=\(.*\)/LUCI_DEPENDS:=\1 +luci-compat +luci-lua-runtime/' "$STORE_MK"
    echo ">>> diy-part2: patched store Makefile deps:"
    grep '^LUCI_DEPENDS' "$STORE_MK"
    # 重新 install store(及其已启用依赖): feeds install -a 在 diy-part2 之前跑,
    # 若 store 因 +libuci-lua 不可满足被跳过, 这里补链接进 package/feeds/, 否则编不进。
    # 注意: feeds install 读的是 feeds/store.index(纯文本缓存, 由 feeds update 生成),
    # 而非实时 Makefile。只 sed Makefile 不会让依赖检查生效;
    # 必须先 `feeds update -i store` 用已修改的 Makefile 重建 index, 再 install。
    ./scripts/feeds update -i store 2>&1 | tail -5 || true
    ./scripts/feeds install -p store luci-app-store 2>&1 | tail -5 || true
    echo ">>> diy-part2: rebuilt store index + re-installed store feed"
    # 验证链接结果
    if [ -d "package/feeds/store/luci-app-store" ]; then
        echo ">>> OK: luci-app-store linked into package/feeds/store/"
    else
        echo "!!! luci-app-store still NOT linked; check feeds/store.index deps"
    fi
else
    echo "!!! diy-part2: store Makefile NOT FOUND at $STORE_MK (store feed not installed?)"
fi
