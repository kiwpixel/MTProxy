#!/bin/bash
# MTProxy 自动化部署脚本（带自动连接生成）
# 适用于 Debian/Ubuntu 系统

# 配置参数（可自定义）
TAG="7159cec8d4423fa860e5a0c2990510f3"  # 你的 proxy tag
PORT=8443                                # 客户端端口
WORKERS=2                                # 4核推荐2个进程
STATS_PORT=8888                          # 统计端口

# 生成随机密钥
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
echo -e "\033[32m生成的连接密钥：$SECRET\033[0m"  # 绿色显示

# 安装依赖
echo -e "\n\033[34m=== 安装依赖 ===\033[0m"
sudo apt update -y >/dev/null 2>&1
sudo apt install -y git curl build-essential libssl-dev zlib1g-dev vim >/dev/null 2>&1

# 克隆代码
echo -e "\n\033[34m=== 克隆代码 ===\033[0m"
rm -rf ~/MTProxy  # 清除旧版本
git clone https://github.com/TelegramMessenger/MTProxy.git ~/MTProxy >/dev/null 2>&1
cd ~/MTProxy || { echo -e "\033[31m克隆失败\033[0m"; exit 1; }

# 下载配置文件
echo -e "\n\033[34m=== 下载配置文件 ===\033[0m"
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf

# 编译程序
echo -e "\n\033[34m=== 编译程序 ===\033[0m"
make >/dev/null 2>&1 || { echo -e "\033[31m编译失败\033[0m"; exit 1; }
cd objs/bin || { echo -e "\033[31m目录不存在\033[0m"; exit 1; }

# 创建系统服务
echo -e "\n\033[34m=== 配置自启动 ===\033[0m"
sudo tee /etc/systemd/system/mtproxy.service <<EOF >/dev/null
[Unit]
Description=MTProxy
After=network.target

[Service]
User=root
WorkingDirectory=/root/MTProxy/objs/bin
ExecStart=/root/MTProxy/objs/bin/mtproto-proxy \
  -u nobody \
  -p $STATS_PORT \
  -H $PORT \
  -S $SECRET \
  -P $TAG \
  --aes-pwd ../../proxy-secret ../../proxy-multi.conf \
  -M $WORKERS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reload >/dev/null 2>&1
sudo systemctl start mtproxy >/dev/null 2>&1
sudo systemctl enable mtproxy >/dev/null 2>&1

# 获取公网IP
SERVER_IP=$(curl -s icanhazip.com || curl -s ifconfig.me)

# 生成连接链接
PROXY_LINK="tg://proxy?server=$SERVER_IP&port=$PORT&secret=$SECRET"

# 部署结果
echo -e "\n\033[32m=== 部署完成 ===\033[0m"
echo -e "服务状态：\033[32m$(sudo systemctl is-active mtproxy)\033[0m"
echo -e "\n\033[33m===== 点击以下链接使用代理 =====\033[0m"
echo -e "\033[1;36m$PROXY_LINK\033[0m"  # 高亮显示链接
echo -e "\033[33m===============================\033[0m"
echo -e "\n查看日志：sudo journalctl -u mtproxy -f"

# 尝试自动复制到剪贴板（需系统支持 xclip 或 xsel）
if command -v xclip &>/dev/null; then
  echo -e "\n已自动复制链接到剪贴板（可直接粘贴到 Telegram）"
  echo -n "$PROXY_LINK" | xclip -selection clipboard
elif command -v xsel &>/dev/null; then
  echo -e "\n已自动复制链接到剪贴板（可直接粘贴到 Telegram）"
  echo -n "$PROXY_LINK" | xsel -b
else
  echo -e "\n提示：可手动复制上方链接到 Telegram 打开"
fi
