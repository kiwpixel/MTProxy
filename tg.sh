#!/bin/bash
# MTProto 一键安装脚本 (增强版)
# Author: HgTrojan (Enhanced Version)

# 颜色定义
RED="\033[31m"      # 错误信息
GREEN="\033[32m"    # 成功信息
YELLOW="\033[33m"   # 警告信息
BLUE="\033[36m"     # 提示信息
PURPLE="\033[35m"   # 紫色信息
PLAIN='\033[0m'

# 图标符号
CHECK="✔"
CROSS="✗"
INFO="ℹ"
ARROW="→"

# 环境变量
export MTG_CONFIG="${MTG_CONFIG:-$HOME/.config/mtg}"
export MTG_ENV="$MTG_CONFIG/env"
export MTG_SECRET="$MTG_CONFIG/secret"
export MTG_CONTAINER="${MTG_CONTAINER:-mtg}"
export MTG_IMAGENAME="${MTG_IMAGENAME:-nineseconds/mtg}"

# 全局变量
DOCKER_CMD="$(command -v docker)"
OSNAME=$(hostnamectl | grep -i system | cut -d: -f2 | sed 's/ //g')
IP=$(curl -sL -4 ip.sb || curl -sL -4 icanhazip.com || curl -sL -4 ifconfig.me)
OS=""
PMT=""
CMD_INSTALL=""
CMD_REMOVE=""

# 彩色输出函数
colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

# 检查命令是否存在
commandExists() {
    command -v "$1" >/dev/null 2>&1
}

# 系统检查与初始化
checkSystem() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        colorEcho $RED " ${CROSS} 请以 root 身份执行该脚本 (sudo -i)"
        exit 1
    fi

    # 检查操作系统
    if commandExists yum; then
        if grep -qi centos /etc/os-release; then
            OS="centos"
        elif grep -qi almalinux /etc/os-release; then
            OS="almalinux"
        elif grep -qi rocky /etc/os-release; then
            OS="rocky"
        else
            OS="rhel"
        fi
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
    elif commandExists apt; then
        if grep -qi ubuntu /etc/os-release; then
            OS="ubuntu"
        elif grep -qi debian /etc/os-release; then
            OS="debian"
        else
            OS="debian-based"
        fi
        PMT="apt"
        CMD_INSTALL="apt update -qq && apt install -y -qq "
        CMD_REMOVE="apt remove -y -qq "
    else
        colorEcho $RED " ${CROSS} 不支持的Linux系统，仅支持Debian/Ubuntu/CentOS系列"
        exit 1
    fi

    # 检查systemd
    if ! commandExists systemctl; then
        colorEcho $RED " ${CROSS} 系统不支持systemd，请使用较新的操作系统版本"
        exit 1
    fi

    # 检查curl
    if ! commandExists curl; then
        colorEcho $BLUE " ${INFO} 安装curl工具..."
        $CMD_INSTALL curl >/dev/null 2>&1 || {
            colorEcho $RED " ${CROSS} curl安装失败"
            exit 1
        }
    fi
}

# 获取服务状态代码
status() {
    if [[ -z "$DOCKER_CMD" ]]; then
        echo 0  # Docker未安装
        return
    elif [[ ! -f "$MTG_ENV" ]]; then
        echo 1  # 配置文件不存在
        return
    fi
    
    # 加载配置
    source "$MTG_ENV" 2>/dev/null
    
    if [[ -z "$MTG_PORT" ]]; then
        echo 2  # 端口配置错误
        return
    fi
    
    # 检查容器状态
    if docker ps -f "name=^/${MTG_CONTAINER}$" --format "{{.Status}}" | grep -qi "up"; then
        echo 4  # 运行中
    else
        echo 3  # 已安装但未运行
    fi
}

# 显示状态文本
statusText() {
    res=$(status)
    case $res in
        0) echo -e "${RED}${CROSS} Docker未安装${PLAIN}" ;;
        1) echo -e "${RED}${CROSS} 未安装配置${PLAIN}" ;;
        2) echo -e "${YELLOW}${INFO} 配置错误${PLAIN}" ;;
        3) echo -e "${GREEN}${CHECK} 已安装${PLAIN} ${RED}${CROSS} 未运行${PLAIN}" ;;
        4) echo -e "${GREEN}${CHECK} 已安装${PLAIN} ${GREEN}${CHECK} 运行中${PLAIN}" ;;
        *) echo -e "${RED}${CROSS} 未知状态${PLAIN}" ;;
    esac
}

# 获取用户配置
getData() {
    mkdir -p "$MTG_CONFIG" || {
        colorEcho $RED " ${CROSS} 无法创建配置目录 $MTG_CONFIG"
        exit 1
    }

    # 端口设置
    while true; do
        read -p " 请输入MTProto端口 [100-65535，默认443]: " PORT
        PORT=${PORT:-443}
        if [[ "$PORT" =~ ^[0-9]+$ ]] && [[ "$PORT" -ge 100 ]] && [[ "$PORT" -le 65535 ]]; then
            # 检查端口是否被占用
            if ss -tuln | grep -q ":$PORT"; then
                colorEcho $YELLOW " ${INFO} 端口 $PORT 已被占用，请更换其他端口"
            else
                break
            fi
        else
            colorEcho $RED " ${CROSS} 端口必须是100-65535之间的数字"
        fi
    done

    # 域名设置
    while true; do
        read -p " 请输入TLS伪装域名 (默认: cloudflare.com): " DOMAIN
        DOMAIN=${DOMAIN:-cloudflare.com}
        if [[ -n "$DOMAIN" ]]; then
            break
        else
            colorEcho $RED " ${CROSS} 域名不能为空"
        fi
    done

    # 保存配置
    cat > "$MTG_ENV" <<EOF
MTG_IMAGENAME=$MTG_IMAGENAME
MTG_PORT=$PORT
MTG_CONTAINER=$MTG_CONTAINER
MTG_DOMAIN=$DOMAIN
EOF
}

# 安装Docker
installDocker() {
    if commandExists docker; then
        colorEcho $BLUE " ${INFO} Docker已安装，检查服务状态..."
        systemctl enable --now docker >/dev/null 2>&1
        selinux
        return
    fi

    colorEcho $BLUE " ${INFO} 开始安装Docker..."
    
    # 安装依赖
    if [[ $OS == "centos" || $OS == "almalinux" || $OS == "rocky" || $OS == "rhel" ]]; then
        $CMD_INSTALL yum-utils device-mapper-persistent-data lvm2 >/dev/null 2>&1
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
    else
        $CMD_INSTALL apt-transport-https ca-certificates curl software-properties-common >/dev/null 2>&1
        curl -fsSL https://download.docker.com/linux/$OS/gpg | apt-key add - >/dev/null 2>&1
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" >/dev/null 2>&1
    fi

    # 安装Docker
    $CMD_INSTALL docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || {
        colorEcho $RED " ${CROSS} Docker安装失败，请检查网络"
        exit 1
    }

    # 启动并设置开机自启
    systemctl enable --now docker >/dev/null 2>&1
    sleep 2

    # 检查Docker状态
    if ! systemctl is-active --quiet docker; then
        colorEcho $RED " ${CROSS} Docker服务启动失败"
        exit 1
    fi

    selinux
    colorEcho $GREEN " ${CHECK} Docker安装成功"
}

# 拉取镜像
pullImage() {
    colorEcho $BLUE " ${INFO} 正在拉取MTProto镜像..."
    
    # 检查网络连接
    if ! curl -s --head https://hub.docker.com >/dev/null; then
        colorEcho $RED " ${CROSS} 无法连接到Docker Hub，请检查网络"
        exit 1
    fi

    if ! docker pull "$MTG_IMAGENAME" >/dev/null; then
        colorEcho $YELLOW " ${INFO} 直接拉取失败，尝试使用国内镜像..."
        # 配置国内镜像加速
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "https://hub-mirror.c.163.com"]
}
EOF
        systemctl daemon-reload
        systemctl restart docker
        sleep 2
        
        if ! docker pull "$MTG_IMAGENAME" >/dev/null; then
            colorEcho $RED " ${CROSS} 镜像拉取失败，请稍后再试"
            exit 1
        fi
    fi
    
    colorEcho $GREEN " ${CHECK} 镜像拉取成功"
}

# SELinux配置
selinux() {
    if [[ -f /etc/selinux/config ]]; then
        if grep -q 'SELINUX=enforcing' /etc/selinux/config; then
            colorEcho $BLUE " ${INFO} 调整SELinux配置..."
            sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
            setenforce 0 >/dev/null 2>&1
        fi
    fi
}

# 防火墙配置
firewall() {
    local port=$1
    colorEcho $BLUE " ${INFO} 配置防火墙开放端口 $port..."
    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif commandExists ufw && ufw status | grep -qw active; then
        ufw allow "$port"/tcp >/dev/null 2>&1
    elif commandExists iptables; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
        # 保存iptables配置
        if commandExists iptables-save; then
            iptables-save >/etc/iptables.rules 2>&1
        fi
    fi
}

# 启动服务
start() {
    local current_status=$(status)
    if [[ $current_status -lt 3 ]]; then
        colorEcho $RED " ${CROSS} 请先完成安装配置"
        return 1
    fi

    # 加载配置
    source "$MTG_ENV" 2>/dev/null || {
        colorEcho $RED " ${CROSS} 配置文件损坏"
        return 1
    }

    # 生成密钥
    if [[ ! -f "$MTG_SECRET" ]]; then
        colorEcho $BLUE " ${INFO} 正在生成安全密钥..."
        if ! docker run --rm "$MTG_IMAGENAME" generate-secret tls -c "$MTG_DOMAIN" > "$MTG_SECRET"; then
            colorEcho $RED " ${CROSS} 密钥生成失败"
            rm -f "$MTG_SECRET"
            return 1
        fi
    fi

    # 停止现有容器
    docker rm -f "$MTG_CONTAINER" >/dev/null 2>&1

    # 启动新容器
    colorEcho $BLUE " ${INFO} 正在启动MTProto服务..."
    if ! docker run -d \
        --name "$MTG_CONTAINER" \
        --restart unless-stopped \
        --ulimit nofile=51200:51200 \
        -p "0.0.0.0:$MTG_PORT:3128" \
        "$MTG_IMAGENAME" run "$(cat "$MTG_SECRET")" >/dev/null; then
        colorEcho $RED " ${CROSS} 服务启动失败"
        return 1
    fi

    # 检查启动状态
    sleep 3
    if docker ps -f "name=^/${MTG_CONTAINER}$" --format "{{.Status}}" | grep -qi "up"; then
        colorEcho $GREEN " ${CHECK} 服务启动成功"
        return 0
    else
        colorEcho $RED " ${CROSS} 服务启动失败，查看日志获取详情"
        docker logs "$MTG_CONTAINER" 2>/dev/null
        return 1
    fi
}

# 生成订阅链接
generateSubscriptionLink() {
    source "$MTG_ENV" 2>/dev/null
    local secret=$(cat "$MTG_SECRET" 2>/dev/null)
    [[ -z "$secret" ]] && secret="未生成"
    echo "https://t.me/proxy?server=$IP&port=$MTG_PORT&secret=$secret"
}

# 生成二维码
generateQRCode() {
    local link=$(generateSubscriptionLink)
    if commandExists qrencode; then
        echo -e "\n${BLUE}● 订阅链接二维码:${PLAIN}"
        qrencode -t ANSIUTF8 "$link"
    else
        colorEcho $YELLOW " ${INFO} 未安装qrencode，无法生成二维码"
        colorEcho $YELLOW " ${ARROW} 安装命令: $CMD_INSTALL qrencode"
    fi
}

# 显示代理信息
showInfo() {
    if [[ $(status) -lt 3 ]]; then
        colorEcho $RED " ${CROSS} 未检测到有效配置，请先安装"
        return 1
    fi

    source "$MTG_ENV" 2>/dev/null
    local secret=$(cat "$MTG_SECRET" 2>/dev/null || echo "未生成")
    local link=$(generateSubscriptionLink)

    echo -e "\n${PURPLE}=============== MTProto 代理信息 ===============${PLAIN}"
    echo -e " ${BLUE}● 当前状态:${PLAIN} $(statusText)"
    echo -e " ${BLUE}● 服务器IP:${PLAIN} ${GREEN}$IP${PLAIN}"
    echo -e " ${BLUE}● 代理端口:${PLAIN} ${GREEN}$MTG_PORT${PLAIN}"
    echo -e " ${BLUE}● TLS域名:${PLAIN} ${GREEN}$MTG_DOMAIN${PLAIN}"
    echo -e " ${BLUE}● 安全密钥:${PLAIN} ${GREEN}$secret${PLAIN}"
    echo -e " ${BLUE}● 订阅链接:${PLAIN} ${GREEN}$link${PLAIN}"
    generateQRCode
    echo -e "${PURPLE}===============================================${PLAIN}\n"
}

# 系统优化
optimizeSystem() {
    colorEcho $BLUE " ${INFO} 正在优化系统配置..."
    
    # 网络优化
    cat >> /etc/sysctl.conf <<EOF
# MTProto优化配置
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30
EOF
    sysctl -p >/dev/null 2>&1

    # 文件描述符优化
    if ! grep -q "root soft nofile 51200" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf <<EOF
root soft nofile 51200
root hard nofile 51200
EOF
    fi
}

# 安装代理
install() {
    if [[ $(status) -ge 3 ]]; then
        read -p " 检测到已安装配置，是否重新安装? [y/N] " confirm
        if [[ "$confirm" != [Yy] ]]; then
            colorEcho $YELLOW " ${INFO} 已取消安装"
            return 1
        fi
    fi

    getData
    installDocker || return 1
    pullImage || return 1
    optimizeSystem
    start || return 1
    firewall "$(grep MTG_PORT "$MTG_ENV" | cut -d= -f2)"
    showInfo
}

# 升级代理
upgrade() {
    if [[ $(status) -lt 3 ]]; then
        colorEcho $RED " ${CROSS} 未安装代理，请先安装"
        return 1
    fi

    colorEcho $BLUE " ${INFO} 开始升级代理..."
    source "$MTG_ENV" 2>/dev/null
    
    # 备份当前配置
    cp "$MTG_ENV" "$MTG_ENV.bak" 2>/dev/null
    [[ -f "$MTG_SECRET" ]] && cp "$MTG_SECRET" "$MTG_SECRET.bak" 2>/dev/null

    pullImage || return 1
    start || {
        colorEcho $YELLOW " ${INFO} 尝试恢复到之前的配置..."
        mv "$MTG_ENV.bak" "$MTG_ENV" 2>/dev/null
        [[ -f "$MTG_SECRET.bak" ]] && mv "$MTG_SECRET.bak" "$MTG_SECRET" 2>/dev/null
        start
    }
    
    colorEcho $GREEN " ${CHECK} 升级完成"
}

# 卸载代理
uninstall() {
    if [[ $(status) -lt 3 ]]; then
        colorEcho $RED " ${CROSS} 未安装代理，无需卸载"
        return 1
    fi

    read -p " 确定要卸载MTProto代理吗? [y/N] " confirm
    if [[ "$confirm" != [Yy] ]]; then
        colorEcho $YELLOW " ${INFO} 已取消卸载"
        return 1
    fi

    source "$MTG_ENV" 2>/dev/null
    
    # 停止并删除容器
    colorEcho $BLUE " ${INFO} 正在卸载..."
    docker rm -f "$MTG_CONTAINER" >/dev/null 2>&1
    
    # 删除镜像（可选）
    read -p " 是否删除MTProto镜像? [y/N] " del_image
    if [[ "$del_image" == [Yy] ]]; then
        docker rmi "$MTG_IMAGENAME" >/dev/null 2>&1
    fi
    
    # 删除配置文件
    rm -rf "$MTG_CONFIG"
    
    colorEcho $GREEN " ${CHECK} 卸载完成"
}

# 查看实时日志
viewLogs() {
    if [[ $(status) -lt 3 ]]; then
        colorEcho $RED " ${CROSS} 未安装代理，请先安装"
        return 1
    fi

    source "$MTG_ENV" 2>/dev/null
    colorEcho $BLUE " ${INFO} 正在显示实时日志 (按Ctrl+C退出)..."
    docker logs -f "$MTG_CONTAINER"
}

# 菜单显示
menu() {
    clear
    echo -e "${PURPLE}#===============================================#"
    echo -e "#              ${GREEN}MTProto 代理管理脚本${PLAIN}             #"
    echo -e "#                 ${YELLOW}增强版 | 支持多系统${PLAIN}              #"
    echo -e "#===============================================#${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 安装代理"
    echo -e "  ${GREEN}2.${PLAIN} 升级代理"
    echo -e "  ${GREEN}3.${PLAIN} 卸载代理"
    echo -e "  ${BLUE}-----------------------------------------------${PLAIN}"
    echo -e "  ${GREEN}4.${PLAIN} 启动服务"
    echo -e "  ${GREEN}5.${PLAIN} 重启服务"
    echo -e "  ${GREEN}6.${PLAIN} 停止服务"
    echo -e "  ${BLUE}-----------------------------------------------${PLAIN}"
    echo -e "  ${GREEN}7.${PLAIN} 查看信息"
    echo -e "  ${GREEN}8.${PLAIN} 修改配置"
    echo -e "  ${GREEN}9.${PLAIN} 实时日志"
    echo -e "  ${BLUE}-----------------------------------------------${PLAIN}"
    echo -e "  ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "\n 当前状态: $(statusText)"
    echo -e " 系统信息: $OSNAME ($OS)"
}

# 主程序
checkSystem

while true; do
    menu
    read -p " 请输入操作编号 [0-9]: " choice
    case $choice in
        1) install ;;
        2) upgrade ;;
        3) uninstall ;;
        4) start ;;
        5) 
            if [[ $(status) -ge 3 ]]; then
                source "$MTG_ENV" 2>/dev/null
                docker restart "$MTG_CONTAINER" >/dev/null 2>&1 && colorEcho $GREEN " ${CHECK} 重启成功" || colorEcho $RED " ${CROSS} 重启失败"
            else
                colorEcho $RED " ${CROSS} 未安装代理，请先安装"
            fi
            ;;
        6) 
            if [[ $(status) -ge 3 ]]; then
                source "$MTG_ENV" 2>/dev/null
                docker stop "$MTG_CONTAINER" >/dev/null 2>&1 && colorEcho $GREEN " ${CHECK} 停止成功" || colorEcho $RED " ${CROSS} 停止失败"
            else
                colorEcho $RED " ${CROSS} 未安装代理，请先安装"
            fi
            ;;
        7) showInfo ;;
        8) 
            if [[ $(status) -ge 3 ]]; then
                getData && start
            else
                colorEcho $RED " ${CROSS} 未安装代理，请先安装"
            fi
            ;;
        9) viewLogs ;;
        0) 
            colorEcho $BLUE " ${INFO} 感谢使用，再见！"
            exit 0 
            ;;
        *) colorEcho $RED " ${CROSS} 无效选择，请输入0-9之间的数字" ;;
    esac
    read -p " 按回车键继续..."
done
