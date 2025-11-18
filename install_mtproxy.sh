#!/usr/bin/env bash
set -euo pipefail

# MTProxy 一键部署脚本
# 使用: sudo bash install_mtproxy.sh

# 配置参数（可根据需求修改）
REPO_URL="https://github.com/TelegramMessenger/MTProxy"
PROXY_DIR="MTProxy"
PORT=443
LOCAL_STATS_PORT=8888
WORKERS=1
RUN_USER="nobody"

# 彩色输出函数
info() { echo -e "\033[1;34m[*] $*\033[0m"; }
success() { echo -e "\033[1;32m[+] $*\033[0m"; }
error() { echo -e "\033[1;31m[-] $*\033[0m" >&2; exit 1; }

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请以 root 或 sudo 权限运行此脚本"
    fi
}

install_dependencies() {
    info "安装依赖包..."
    if command -v apt &>/dev/null; then
        apt update -qq
        apt install -y -qq git curl build-essential libssl-dev zlib1g-dev xxd
    elif command -v yum &>/dev/null; then
        yum install -y -q git curl openssl-devel zlib-devel xxd
        yum groupinstall -y -q "Development Tools"
    else
        error "不支持的操作系统（需 apt 或 yum 包管理器）"
    fi
}

clone_or_update_repo() {
    if [ -d "$PROXY_DIR" ]; then
        info "仓库已存在，尝试更新..."
        cd "$PROXY_DIR" && git pull --quiet || info "pull 失败，保留现有代码"
        cd - >/dev/null
    else
        info "克隆 MTProxy 仓库..."
        git clone --quiet "$REPO_URL" "$PROXY_DIR" || error "克隆仓库失败"
    fi
}

fetch_proxy_configs() {
    info "下载 proxy-secret 和 proxy-multi.conf..."
    cd "$PROXY_DIR" || error "进入仓库目录失败"
    curl -sSf https://core.telegram.org/getProxySecret -o proxy-secret || error "下载 proxy-secret 失败"
    curl -sSf https://core.telegram.org/getProxyConfig -o proxy-multi.conf || error "下载 proxy-multi.conf 失败"
    cd - >/dev/null
}

generate_secret() {
    info "生成用户连接密钥..."
    # 使用 openssl 生成 16 字节的 hex 密钥
    if command -v openssl &>/dev/null; then
        SECRET=$(openssl rand -hex 16)
    else
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    fi
    success "生成的连接密钥：$SECRET"
}

build_proxy() {
    info "编译 MTProxy（可能需要几分钟）..."
    cd "$PROXY_DIR" || error "进入仓库目录失败"
    make clean >/dev/null 2>&1 || true
    make -j"$(nproc)" >/dev/null 2>&1 || error "编译失败，查看 $PROXY_DIR/objs/bin 是否存在可执行文件"
    cd - >/dev/null
}

start_proxy() {
    info "准备启动 MTProxy..."
    if [ ! -x "$PROXY_DIR/objs/bin/mtproto-proxy" ]; then
        error "找不到可执行文件：$PROXY_DIR/objs/bin/mtproto-proxy，编译可能失败"
    fi

    # 提示用户可选的 TAG
    read -r -p "请输入从 @MTProxybot 获取的 TAG（如无则留空）： " TAG

    CMD=("$PROXY_DIR/objs/bin/mtproto-proxy"
         "-u" "$RUN_USER"
         "-p" "$LOCAL_STATS_PORT"
         "-H" "$PORT"
         "-S" "$SECRET"
         "--aes-pwd" "$PROXY_DIR/proxy-secret" "$PROXY_DIR/proxy-multi.conf"
         "-M" "$WORKERS")

    if [ -n "$TAG" ]; then
        CMD+=("-P" "$TAG")
    fi

    info "使用 nohup 在后台启动代理（日志：mtproxy.log）"
    nohup "${CMD[@]}" >> mtproxy.log 2>&1 &
    sleep 1
    if ps aux | grep -v grep | grep -q mtproto-proxy; then
        success "MTProxy 已启动，日志保存在 $(pwd)/mtproxy.log"
    else
        error "启动失败，请查看 $(pwd)/mtproxy.log"
    fi
}

main() {
    ensure_root
    info "MTProxy 一键部署脚本启动"
    install_dependencies
    clone_or_update_repo
    fetch_proxy_configs
    generate_secret
    build_proxy
    start_proxy
    success "流程完成。请将上面显示的连接密钥保存并在客户端使用。"
}

main "$@"
# MTProxy#!/bin/bash
set -euo pipefail

# 配置参数（可根据需求修改）
REPO_URL="https://github.com/TelegramMessenger/MTProxy"
PROXY_DIR="MTProxy"
PORT=443
LOCAL_STATS_PORT=8888
WORKERS=1
USER="nobody"

# 彩色输出函数
info() { echo -e "\033[1;34m[*] $*\033[0m"; }
success() { echo -e "\033[1;32m[+] $*\033[0m"; }
error() { echo -e "\033[1;31m[-] $*\033[0m" >&2; exit 1; }

# 检查系统包管理器并安装依赖
install_dependencies() {
    info "安装依赖包..."
    if command -v apt &>/dev/null; then
        sudo apt update -qq
        sudo apt install -y -qq git curl build-essential libssl-dev zlib1g-dev
    elif command -v yum &>/dev/null; then
        sudo yum install -y -q openssl-devel zlib-devel
        sudo yum groupinstall -y -q "Development Tools"
    else
        error "不支持的操作系统（需 apt 或 yum 包管理器）"
    fi
}

# 克隆或更新仓库
clone_or_update_repo() {
    if [ -d "$PROXY_DIR" ]; then
        info "仓库已存在，更新代码..."
        cd "$PROXY_DIR" && git pull --quiet
        cd ..
    else
        info "克隆 MTProxy 仓库..."
        git clone --quiet "$REPO_URL" "$PROXY_DIR"
    fi
}

# 获取代理配置文件
fetch_proxy_configs() {
    info "下载最新配置文件..."
    cd "$PROXY_DIR" || error "进入仓库目录失败"
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret || error "下载 proxy-secret 失败"
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf || error "下载 proxy-multi.conf 失败"
    cd ..
}

# 生成用户连接密钥
generate_secret() {
    info "生成用户连接密钥..."
    SECRET=$(cd "$PROXY_DIR" && head -c 16 /dev/urandom | xxd -ps) || error "生成密钥失败"
    success "生成的连接密钥：$SECRET"
    echo "请保存此密钥用于客户端配置"
}

# 编译程序
build_proxy() {
    info "编译 MTProxy 程序..."
    cd "$PROXY_DIR" || error "进入仓库目录失败"
    make clean >/dev/null 2>&1 || true
    make -j"$(nproc)" >/dev/null 2>&1 || error "编译失败"
    cd ..
}

# 启动代理服务
start_proxy() {
    info "请输入从 @MTProxybot 获取的 TAG（如无则留空）："
    read -r TAG

    info "启动 MTProxy 服务..."
    cd "$PROXY_DIR/objs/bin" || error "找不到可执行文件"
    
    # 构建启动命令
    CMD="./mtproto-proxy \
        -u $USER \
        -p $LOCAL_STATS_PORT \
        -H $PORT \
        -S $SECRET \
        --aes-pwd ../../proxy-secret ../../proxy-multi.conf \
        -M $WORKERS"
    
    # 添加 TAG（如果存在）
    [ -n "$TAG" ] && CMD="$CMD -P $TAG"
    
    # 执行启动命令
    eval $CMD || error "服务启动失败"
}

# 主流程
main() {
    info "MTProxy 一键部署脚本启动"
    install_dependencies
    clone_or_update_repo
    fetch_proxy_configs
    generate_secret
    build_proxy
    start_proxy
    success "MTProxy 启动成功！"
}

main
