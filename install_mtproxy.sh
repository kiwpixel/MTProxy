#!/bin/bash
# MTProxy 增强版部署脚本
# 特性：进度条显示、交互式Tag设置、自动生成密钥

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 进度条函数
progress_bar() {
    local duration=$1
    local width=50
    local interval=0.2
    local steps=$((duration / interval))
    
    for ((i=0; i<=steps; i++)); do
        local percent=$((i * 100 / steps))
        local filled=$((i * width / steps))
        local empty=$((width - filled))
        
        printf "\r${BLUE}[${NC}"
        printf "%0.s=" $(seq 1 $filled)
        printf "%0.s " $(seq 1 $empty)
        printf "${BLUE}] ${percent}%%${NC}"
        sleep $interval
    done
    echo ""
}

# 欢迎信息
echo -e "\n${YELLOW}===== MTProxy 自动部署工具 =====${NC}\n"

# 生成随机密钥
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
echo -e "${GREEN}已自动生成连接密钥：${YELLOW}$SECRET${NC}\n"

# 询问是否加入Tag
read -p "${BLUE}是否需要加入代理Tag？(y/n，默认n)：${NC}" USE_TAG
USE_TAG=${USE_TAG:-n}

if [[ "$USE_TAG" == "y" || "$USE_TAG" == "Y" ]]; then
    read -p "${BLUE}请输入你的代理Tag：${NC}" TAG
    if [[ -z "$TAG" ]]; then
        echo -e "${RED}Tag不能为空，将使用默认值${NC}"
        TAG="7159cec8d4423fa860e5a0c2990510f3"
    fi
else
    TAG="7159cec8d4423fa860e5a0c2990510f3"
    echo -e "${YELLOW}将使用默认Tag：$TAG${NC}"
fi

# 配置参数
PORT=8443
WORKERS=2
STATS_PORT=8888

# 安装依赖
echo -e "\n${BLUE}=== 1/4 安装依赖包 ==="
progress_bar 10 &
sudo apt update -y >/dev/null 2>&1
sudo apt install -y git curl build-essential libssl-dev zlib1g-dev >/dev/null 2>&1
wait
echo -e "${GREEN}依赖安装完成${NC}"

# 克隆代码
echo -e "\n${BLUE}=== 2/4 克隆代码仓库 ==="
progress_bar 8 &
rm -rf ~/MTProxy
git clone https://github.com/TelegramMessenger/MTProxy.git ~/MTProxy >/dev/null 2>&1
cd ~/MTProxy || { echo -e "${RED}克隆失败${NC}"; exit 1; }
wait
echo -e "${GREEN}代码克隆完成${NC}"

# 下载配置文件
echo -e "\n${BLUE}=== 3/4 下载配置文件 ==="
progress_bar 5 &
curl -s https://core.telegram.org/getProxySecret -o proxy-secret >/dev/null 2>&1
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf >/dev/null 2>&1
wait
echo -e "${GREEN}配置文件下载完成${NC}"

# 编译程序
echo -e "\n${BLUE}=== 4/4 编译程序 ==="
progress_bar 15 &
make >/dev/null 2>&1 || { echo -e "${RED}编译失败${NC}"; exit 1; }
cd objs/bin || { echo -e "${RED}目录不存在${NC}"; exit 1; }
wait
echo -e "${GREEN}程序编译完成${NC}"

# 创建系统服务
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
echo -e "\n${GREEN}===== 部署完成 =====${NC}"
echo -e "服务状态：${GREEN}$(sudo systemctl is-active mtproxy)${NC}"
echo -e "\n${YELLOW}连接信息：${NC}"
echo -e "服务器IP：${YELLOW}$SERVER_IP${NC}"
echo -e "端口：${YELLOW}$PORT${NC}"
echo -e "密钥：${YELLOW}$SECRET${NC}"
echo -e "\n${BLUE}点击链接使用代理：${NC}"
echo -e "${YELLOW}$PROXY_LINK${NC}\n"
echo -e "查看日志：${GREEN}sudo journalctl -u mtproxy -f${NC}"
