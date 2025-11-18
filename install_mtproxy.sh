#!/bin/bash
# MTProxy 配置与管理脚本
# 风格参考：交互式配置、状态查询、信息展示

# 常量定义
WORKDIR="$HOME/MTProxy"
PID_FILE="$WORKDIR/objs/bin/mtproxy.pid"
CONFIG_FILE="$WORKDIR/mtp_config"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# 工具函数：获取公网IP
get_ip_public() {
    local ip=$(curl -s icanhazip.com || curl -s ifconfig.me)
    echo "$ip"
}

# 工具函数：检查进程是否存在
pid_exists() {
    local pid=$1
    if ps -p $pid >/dev/null 2>&1; then
        return 0  # 进程存在
    else
        return 1  # 进程不存在
    fi
}

# 工具函数：打印分隔线
print_line() {
    echo "----------------------------------------"
}

# 配置函数：交互式生成配置文件
config_mtp() {
    mkdir -p $WORKDIR && cd $WORKDIR
    echo -e "检测到配置文件不存在，开始生成配置..." && print_line

    # 客户端连接端口配置
    while true; do
        default_port=443
        echo -e "请输入客户端连接端口 [1-65535]"
        read -p "(默认端口: ${default_port}): " input_port
        [ -z "$input_port" ] && input_port=$default_port
        
        # 验证端口合法性
        if [[ $input_port =~ ^[1-9][0-9]{0,4}$ ]] && [ $input_port -le 65535 ]; then
            echo -e "\n---------------------------"
            echo -e "客户端端口 = ${input_port}"
            echo -e "---------------------------\n"
            break
        else
            echo -e "[${YELLOW}错误${NC}] 请输入有效的端口号 [1-65535]"
        fi
    done

    # 管理端口配置（与客户端端口不同）
    while true; do
        default_manage=8888
        echo -e "请输入管理统计端口 [1-65535]"
        read -p "(默认端口: ${default_manage}): " input_manage
        [ -z "$input_manage" ] && input_manage=$default_manage
        
        # 验证端口合法性且与客户端端口不同
        if [[ $input_manage =~ ^[1-9][0-9]{0,4}$ ]] && [ $input_manage -le 65535 ] && [ $input_manage -ne $input_port ]; then
            echo -e "\n---------------------------"
            echo -e "管理端口 = ${input_manage}"
            echo -e "---------------------------\n"
            break
        else
            echo -e "[${YELLOW}错误${NC}] 请输入有效的端口号（不能与客户端端口相同）"
        fi
    done

    # 伪装域名配置（验证可访问性）
    while true; do
        default_domain="azure.microsoft.com"
        echo -e "请输入伪装域名（用于TLS混淆）"
        read -p "(默认域名: ${default_domain}): " input_domain
        [ -z "$input_domain" ] && input_domain=$default_domain
        
        # 验证域名可访问
        http_code=$(curl -I -m 10 -o /dev/null -s -w "%{http_code}" "https://$input_domain")
        if [[ $http_code -eq 200 || $http_code -eq 301 || $http_code -eq 302 ]]; then
            echo -e "\n---------------------------"
            echo -e "伪装域名 = ${input_domain}"
            echo -e "---------------------------\n"
            break
        else
            echo -e "[${YELLOW}错误${NC}] 域名无法访问（状态码: $http_code），请重新输入"
        fi
    done

    # 生成随机密钥
    secret=$(head -c 16 /dev/urandom | xxd -ps)
    echo -e "已自动生成连接密钥: ${GREEN}$secret${NC}\n"

    # Proxy Tag配置（可选，32位字符）
    while true; do
        echo -e "请输入代理推广TAG（32位字符，留空跳过）"
        echo -e "若无TAG，可联系 @MTProxybot 创建，需提供："
        echo -e "IP: $(get_ip_public)  端口: $input_port  临时密钥: $secret"
        read -p "(留空则不使用TAG): " input_tag
        
        # 验证TAG格式（空或32位字符）
        if [ -z "$input_tag" ] || [[ $input_tag =~ ^[A-Fa-f0-9]{32}$ ]]; then
            echo -e "\n---------------------------"
            echo -e "Proxy TAG = ${input_tag:-未设置}"
            echo -e "---------------------------\n"
            break
        else
            echo -e "[${YELLOW}错误${NC}] TAG必须是32位十六进制字符"
        fi
    done

    # 下载Telegram配置文件
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf

    # 生成配置文件
    cat > $CONFIG_FILE <<EOF
#!/bin/bash
secret="$secret"
port=$input_port
manage_port=$input_manage
domain="$input_domain"
proxy_tag="${input_tag}"
EOF

    echo -e "配置文件已生成: ${GREEN}$CONFIG_FILE${NC}" && print_line
}

# 状态检查函数
status_mtp() {
    if [ -f $PID_FILE ]; then
        local pid=$(cat $PID_FILE)
        pid_exists $pid
        if [ $? -eq 0 ]; then
            return 0  # 运行中
        fi
    fi
    return 1  # 未运行
}

# 信息展示函数
info_mtp() {
    if [ -f $CONFIG_FILE ]; then
        source $CONFIG_FILE
    else
        echo -e "[${YELLOW}提示${NC}] 未检测到配置文件，请先配置代理"
        return 1
    fi

    status_mtp
    if [ $? -eq 0 ]; then
        local public_ip=$(get_ip_public)
        # 生成带域名混淆的客户端密钥
        local domain_hex=$(echo -n "$domain" | xxd -pu | sed 's/0a//g')
        local client_secret="ee${secret}${domain_hex}"
        
        echo -e "MTProxy 状态: ${GREEN}运行中${NC}" && print_line
        echo -e "服务器IP: ${RED}$public_ip${NC}"
        echo -e "连接端口: ${RED}$port${NC}"
        echo -e "管理端口: ${RED}$manage_port${NC}"
        echo -e "伪装域名: ${RED}$domain${NC}"
        echo -e "原始密钥: ${RED}$secret${NC}"
        echo -e "客户端密钥: ${RED}$client_secret${NC}" && print_line
        echo -e "TG一键链接: https://t.me/proxy?server=$public_ip&port=$port&secret=$client_secret"
        echo -e "TG一键链接: tg://proxy?server=$public_ip&port=$port&secret=$client_secret"
    else
        echo -e "MTProxy 状态: ${YELLOW}已停止${NC}"
    fi
}

# 安装依赖与编译
install_mtp() {
    echo -e "开始安装依赖与编译程序..." && print_line
    sudo apt update -y
    sudo apt install -y git curl build-essential libssl-dev zlib1g-dev
    
    # 克隆代码
    if [ ! -d $WORKDIR ]; then
        git clone https://github.com/TelegramMessenger/MTProxy.git $WORKDIR
    fi
    cd $WORKDIR && make clean && make
    
    echo -e "${GREEN}依赖安装与编译完成${NC}" && print_line
}

# 启动代理
start_mtp() {
    if [ ! -f $CONFIG_FILE ]; then
        echo -e "[${YELLOW}提示${NC}] 未检测到配置文件，正在进入配置..."
        config_mtp
    fi
    source $CONFIG_FILE
    
    status_mtp
    if [ $? -eq 0 ]; then
        echo -e "[${YELLOW}提示${NC}] 代理已在运行中"
        return 0
    fi
    
    # 启动命令（后台运行并记录PID）
    cd $WORKDIR/objs/bin
    ./mtproto-proxy \
        -u nobody \
        -p $manage_port \
        -H $port \
        -S $secret \
        ${proxy_tag:+-P $proxy_tag} \
        --aes-pwd ../../proxy-secret ../../proxy-multi.conf \
        -M 2 \
        --domain $domain \
        > /dev/null 2>&1 &
    echo $! > $PID_FILE
    
    sleep 2
    status_mtp
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}代理启动成功${NC}"
    else
        echo -e "${YELLOW}代理启动失败，请检查日志${NC}"
    fi
}

# 停止代理
stop_mtp() {
    status_mtp
    if [ $? -eq 1 ]; then
        echo -e "[${YELLOW}提示${NC}] 代理未在运行中"
        return 0
    fi
    
    local pid=$(cat $PID_FILE)
    kill $pid > /dev/null 2>&1
    rm -f $PID_FILE
    echo -e "${RED}代理已停止${NC}"
}

# 主菜单
main() {
    clear
    echo -e "===== MTProxy 管理工具 ====="
    echo -e "1. 安装依赖与编译程序"
    echo -e "2. 配置代理参数"
    echo -e "3. 启动代理"
    echo -e "4. 停止代理"
    echo -e "5. 查看代理信息"
    echo -e "6. 退出"
    print_line
    read -p "请选择操作 [1-6]: " choice
    
    case $choice in
        1) install_mtp ;;
        2) config_mtp ;;
        3) start_mtp ;;
        4) stop_mtp ;;
        5) info_mtp ;;
        6) exit 0 ;;
        *) echo -e "[${YELLOW}错误${NC}] 无效选择"; sleep 2; main ;;
    esac
    
    echo -e "\n按任意键返回菜单..."
    read -n 1
    main
}

# 启动主菜单
main
