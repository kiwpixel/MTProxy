#!/bin/bash

# 一键安装 MTProxy 并注册到 @MTProxybot
set -euo pipefail

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 安装依赖（修复 Debian 仓库问题）
echo "正在安装依赖..."
if [ -f /etc/debian_version ]; then
    # 临时跳过有问题的仓库更新
    apt update -y --allow-insecure-repositories || true
    # 强制安装所需依赖，忽略仓库错误
    apt install -y --no-install-recommends git curl build-essential libssl-dev zlib1g-dev || \
    { echo "尝试强制安装依赖..."; apt install -y --force-yes git curl build-essential libssl-dev zlib1g-dev; }
elif [ -f /etc/redhat-release ]; then
    yum install -y openssl-devel zlib-devel
    yum groupinstall -y "Development Tools"
else
    echo "不支持的操作系统"
    exit 1
fi

# 克隆仓库并编译
echo "正在编译 MTProxy..."
git clone https://github.com/TelegramMessenger/MTProxy /opt/MTProxy
cd /opt/MTProxy
make && cd objs/bin
cp mtproto-proxy /opt/MTProxy/

# 获取配置文件
echo "正在获取配置文件..."
curl -s https://core.telegram.org/getProxySecret -o /opt/MTProxy/proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf

# 生成用户连接密钥
echo "正在生成密钥..."
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
echo "你的连接密钥: $SECRET"

# 提示用户注册代理
echo "请打开 Telegram 并向 @MTProxybot 发送 /newproxy 命令"
echo "按照机器人提示完成注册，需要提供服务器 IP 和端口（默认 443）"
read -p "请输入 @MTProxybot 提供的 proxy tag: " PROXY_TAG

# 创建 systemd 服务
echo "正在配置服务..."
cat > /etc/systemd/system/MTProxy.service << EOF
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
ExecStart=/opt/MTProxy/mtproto-proxy -u nobody -p 8888 -H 443 -S $SECRET -P $PROXY_TAG --aes-pwd proxy-secret proxy-multi.conf -M 1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl start MTProxy.service
systemctl enable MTProxy.service

# 显示连接信息
SERVER_IP=$(curl -s icanhazip.com)
echo "安装完成！"
echo "代理连接链接: tg://proxy?server=$SERVER_IP&port=443&secret=$SECRET"
echo "服务状态: $(systemctl is-active MTProxy.service)"
