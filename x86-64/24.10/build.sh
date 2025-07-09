#!/bin/bash

# --- 1. 环境准备和源码下载 ---
echo "==> [Step 1/6] Cloning ImmortalWrt source code..."
git clone https://github.com/immortalwrt/immortalwrt.git /home/build/immortalwrt
cd /home/build/immortalwrt

# --- 2. 添加自定义插件软件源 ---
# 这是一个关键步骤，根据插件文档，我们将 nikki 插件的 git 仓库添加到编译系统的 feeds 配置文件中。
echo "==> [Step 2/6] Adding custom plugin feed for OpenWrt-nikki..."
echo "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main" >> feeds.conf.default

# --- 3. 更新和安装所有软件源 ---
echo "==> [Step 3/6] Updating and installing all feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# --- 4. 定义旁路由网络和密码等预设配置 ---
# 我们将创建一个在首次启动时运行的脚本，来自动完成所有网络设置。
echo "==> [Step 4/6] Creating network and system pre-configuration file..."
# 创建存放自定义配置文件的目录
mkdir -p files/etc/uci-defaults

# 创建名为 99-custom-settings 的首次启动配置文件
# 这个脚本会在第一次开机时自动执行并完成所有设置，然后自我删除。
cat << EOF > files/etc/uci-defaults/99-custom-settings
#!/bin/sh

# a. 设置主机名
uci set system.@system[0].hostname='ImmortalWrt-SideRouter'

# b. 设置 root 用户密码为 '132909'
echo "root:132909" | chpasswd

# c. 配置 LAN 口作为旁路由
uci set network.lan.proto='static'                  # 设置为静态地址
uci set network.lan.ipaddr='192.168.110.5'          # 设置旁路由自己的 IP
uci set network.lan.netmask='255.255.255.0'         # 设置子网掩码
uci set network.lan.gateway='192.168.110.4'         # 设置网关（主路由IP）
uci set network.lan.dns='192.168.110.4'             # 设置DNS（主路由IP）
uci set network.lan.delegate='0'                    # 关闭IPv6 PD
uci delete network.lan.ip6assign                    # 删除IPv6分配长度

# d. 关闭并禁用 DHCP 服务，因为旁路由不需要分配IP
uci set dhcp.lan.ignore='1'
/etc/init.d/dnsmasq disable
/etc/init.d/dnsmasq stop

# e. 提交所有更改
uci commit

# f. 优雅地重启网络以应用设置
/etc/init.d/network restart

exit 0
EOF

# 赋予该脚本可执行权限
chmod +x files/etc/uci-defaults/99-custom-settings

echo "==> Network pre-configuration created successfully."

# --- 5. 定义需要编译进固件的软件包列表 ---
echo "==> [Step 5/6] Defining package list for the image..."
PACKAGES=""
# 基础功能包
PACKAGES="$PACKAGES luci"                                 # LuCI 网页界面核心
PACKAGES="$PACKAGES luci-i18n-base-zh-cn"               # LuCI 基础中文翻译
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"           # 防火墙中文翻译
PACKAGES="$PACKAGES luci-app-argon-config"              # Argon 主题配置
PACKAGES="$PACKAGES luci-theme-argon"                   # Argon 主题本身
PACKAGES="$PACKAGES luci-i18n-opkg-zh-cn"                # 软件包管理器中文（新版中可能叫 luci-i18n-package-manager-zh-cn）

# Nikki 插件及其依赖
# 根据插件文档，这些是必需的依赖包
PACKAGES="$PACKAGES ca-bundle curl yq firewall4 ip-full kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun"
# Nikki 插件本体和 LuCI 界面
PACKAGES="$PACKAGES luci-app-nikki"
PACKAGES="$PACKAGES luci-i18n-nikki-zh-cn"               # Nikki 插件中文翻译

echo "The following packages will be included in the build:"
echo "$PACKAGES"

# --- 6. 开始编译固件 ---
echo "==> [Step 6/6] Starting the image build process..."
# 使用 'make defconfig' 生成默认配置文件
make defconfig

# 开始编译镜像
# PROFILE="generic": 适用于大多数 x86/64 虚拟机的通用配置
# PACKAGES: 我们上面定义的软件包列表
# FILES: 包含我们自定义启动脚本的目录
# ROOTFS_PARTSIZE=2048: 设置根文件系统分区大小为 2048 MB (2G)
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="files" ROOTFS_PARTSIZE="2048"

# 检查编译是否成功
if [ $? -ne 0 ]; then
    echo "Error: Build failed! Please check the logs."
    exit 1
else
    echo "Build completed successfully! Your firmware can be found in the bin/targets/x86/64/ directory."
fi
