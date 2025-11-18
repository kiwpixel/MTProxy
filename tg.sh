#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}检测到Docker未安装，正在安装Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm -f get-docker.sh
        systemctl enable --now docker
    fi
}

# 生成SECURE密钥
generate_secure() {
    echo -e "${YELLOW}正在生成SECURE密钥...${NC}"
    openssl rand -hex 16
}

# 获取TAG
get_tag() {
    echo -e "${YELLOW}请从 @MTProxybot 获取TAG并输入:${NC}"
    read -p "TAG: " tag
    echo "$tag"
}

# 获取DOMAIN
get_domain() {
    echo -e "${YELLOW}请输入一个未被墙的域名(例如: itunes.apple.com):${NC}"
    read -p "DOMAIN: " domain
    echo "$domain"
}

# 主安装流程
main() {
    echo -e "${GREEN}=== MTProxy Docker一键安装脚本 ===${NC}"
    
    # 检查Docker
    check_docker
    
    # 生成/获取必要参数
    SECURE=$(generate_secure)
    DOMAIN=$(get_domain)
    TAG=$(get_tag)
    
    # 创建环境变量文件
    echo -e "${YELLOW}正在配置容器参数...${NC}"
    cat > ./mtproxy.env << EOF
SECURE=$SECURE
DOMAIN=$DOMAIN
TAG=$TAG
EOF
    
    # 启动容器
    echo -e "${YELLOW}正在启动MTProxy容器...${NC}"
    docker run -tid \
      --name mtproxy \
      --restart=always \
      --privileged=true \
      -p 8443:8443 \
      --env-file ./mtproxy.env  \
      ghcr.io/elesssss/mtproxy
    
    # 检查启动状态
    if docker ps | grep -q mtproxy; then
        echo -e "${GREEN}MTProxy容器启动成功!${NC}"
        echo -e "${YELLOW}查看代理链接: ${NC}docker logs mtproxy"
    else
        echo -e "${RED}MTProxy容器启动失败，请检查日志: docker logs mtproxy${NC}"
    fi
}

# 执行主流程
main
