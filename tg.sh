#!/bin/bash
set -euo pipefail

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用root用户运行此脚本"
    exit 1
fi

# 定义安装路径
INSTALL_DIR="/opt/MTProxy"
BINARY_PATH="${INSTALL_DIR}/objs/bin/mtproto-proxy"

# 安装依赖
echo "=== 安装系统依赖 ==="
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu系统
    apt update -y
    apt install -y git curl build-essential libssl-dev zlib1g-dev
elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL系统
    yum install -y openssl-devel zlib-devel
    yum groupinstall -y "Development Tools"
else
    echo "错误：不支持的操作系统"
    exit 1
fi

# 克隆仓库
echo -e "\n=== 克隆MTProxy仓库 ==="
if [ -d "${INSTALL_DIR}" ]; then
    rm -rf "${INSTALL_DIR}"
fi
git clone https://github.com/TelegramMessenger/MTProxy "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# 编译程序
echo -e "\n=== 编译MTProxy ==="
make clean
make
if [ ! -f "${BINARY_PATH}" ]; then
    echo "错误：编译失败，未找到可执行文件"
    exit 1
fi

# 获取配置文件
echo -e "\n=== 获取必要配置文件 ==="
curl -s https://core.telegram.org/getProxySecret -o "${INSTALL_DIR}/proxy-secret"
curl -s https://core.telegram.org/getProxyConfig -o "${INSTALL_DIR}/proxy-multi.conf"

# 生成用户连接密钥
echo -e "\n=== 生成用户连接密钥 ==="
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
echo "你的连接密钥: ${SECRET}"

# 引导用户注册代理
echo -e "\n=== 注册代理到Telegram ==="
echo "1. 打开Telegram，搜索并向 @MTProxybot 发送 /newproxy 命令"
echo "2. 按照机器人提示提供服务器IP和端口（默认443）"
echo "3. 完成注册后获取proxy tag"
read -p "请输入@MTProxybot提供的proxy tag: " PROXY_TAG

# 创建systemd服务
echo -e "\n=== 配置系统服务 ==="
cat > /etc/systemd/system/MTProxy.service << EOF
[Unit]
Description=MTProto Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BINARY_PATH} -u nobody -p 8888 -H 443 -S ${SECRET} -P ${PROXY_TAG} --aes-pwd proxy-secret proxy-multi.conf -M 1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl start MTProxy
systemctl enable MTProxy

# 获取服务器IP
SERVER_IP=$(curl -s icanhazip.com)

# 显示结果
echo -e "\n=== 安装完成 ==="
echo "代理状态: $(systemctl is-active MTProxy)"
echo "连接链接: tg://proxy?server=${SERVER_IP}&port=443&secret=${SECRET}"
echo "查看日志: journalctl -u MTProxy -f"
echo "重启服务: systemctl restart MTProxy"
