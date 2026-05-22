#!/bin/bash
# ============================================================
# Trojan Panel 部署脚本 (改进版)
# 支持：交互式 / 环境变量 / docker-compose
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -------------------- 颜色 --------------------
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# -------------------- 版本 --------------------
VERSION="${VERSION:-latest}"
BACKEND_IMAGE="ghcr.io/berg-e5/trojan-panel:${VERSION}"
FRONTEND_IMAGE="ghcr.io/berg-e5/trojan-panel-ui:${VERSION}"

# -------------------- 交互输入 --------------------
read_input() {
    local var=$1
    local prompt=$2
    local default=$3
    local val

    read -p "$prompt ${default:+[默认: $default]}: " val
    eval "$var='${val:-$default}'"
}

read_password() {
    local var=$1
    local prompt=$2
    local default=$3
    local val1 val2

    while true; do
        read -s -p "$prompt: " val1
        echo ""
        if [ -z "$val1 ]; then
            if [ -n "$default" ]; then
                eval "$var='$default'"
                return 0
            fi
            log_err "密码不能为空"
            continue
        fi
        read -s -p "请再次输入密码: " val2
        echo ""
        if [ "$val1" != "$val2" ]; then
            log_err "两次密码不一致，请重试"
            continue
        fi
        eval "$var='$val1'"
        return 0
    done
}

# -------------------- 环境变量加载 --------------------
load_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        log_info "从 .env 文件加载配置..."
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    fi
}

# -------------------- 交互模式 --------------------
interactive_config() {
    echo ""
    echo "=========================================="
    echo "       Trojan Panel 交互式部署"
    echo "=========================================="
    echo ""

    read_input MYSQL_ROOT_PASSWORD "MySQL ROOT 密码" "${MYSQL_ROOT_PASSWORD:-TrojanPanel@2024}"
    read_password REDIS_PASSWORD "Redis 密码 (需两次输入)" "${REDIS_PASSWORD:-TrojanPanel@2024}"
    read_input MYSQL_DATABASE "数据库名" "${MYSQL_DATABASE:-trojan_panel}"
    read_input SERVER_PORT "后端端口" "${SERVER_PORT:-8081}"
    read_input VERSION "版本 (latest 或如 v2.3.2)" "${VERSION:-latest}"
    echo ""
}

# -------------------- 配置确认 --------------------
show_config() {
    echo ""
    echo "----------------------------------------"
    echo "  部署配置:"
    echo "    版本:         ${VERSION}"
    echo "    MySQL 密码:   ${MYSQL_ROOT_PASSWORD}"
    echo "    Redis 密码:   ${REDIS_PASSWORD}"
    echo "    数据库名:     ${MYSQL_DATABASE}"
    echo "    后端端口:     ${SERVER_PORT}"
    echo "----------------------------------------"
    echo ""
}

# -------------------- 前置检查 --------------------
check_docker() {
    log_step "检查 Docker..."
    if ! command -v docker &> /dev/null; then
        log_warn "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
    fi

    if ! docker info &> /dev/null; then
        log_err "Docker 无法访问，请用 sudo 运行或检查权限"
        exit 1
    fi

    log_info "Docker: $(docker --version | awk '{print $5}' | tr -d ',')"

    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log_info "使用 docker-compose"
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        log_info "使用 docker compose (插件)"
    else
        log_err "未找到 docker-compose，请先安装"
        exit 1
    fi
}

# -------------------- 拉取镜像 --------------------
pull_images() {
    log_step "拉取镜像 (版本: ${VERSION})..."

    docker pull mysql:8.0 || log_warn "MySQL 镜像拉取失败"
    docker pull redis:7 || log_warn "Redis 镜像拉取失败"
    docker pull ${BACKEND_IMAGE} || log_warn "后端镜像拉取失败"
    docker pull ${FRONTEND_IMAGE} || log_warn "前端镜像拉取失败"

    log_info "镜像拉取完成"
}

# -------------------- 生成 .env 文件 --------------------
generate_env() {
    log_step "生成配置文件..."
    cat > "$SCRIPT_DIR/.env" <<EOF
# Trojan Panel 配置文件
# 直接修改此文件可避免交互式输入

VERSION=${VERSION}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
SERVER_PORT=${SERVER_PORT}
TZ=${TZ:-Asia/Shanghai}
EOF
    log_info "配置已保存到 .env"
}

# -------------------- 启动服务 --------------------
start_services() {
    log_step "启动服务 (docker compose)..."

    # 生成 docker-compose.yml (内联替换)
    envsubst < "$SCRIPT_DIR/docker-compose.yml.template" > "$SCRIPT_DIR/docker-compose.yml"

    ${COMPOSE_CMD} up -d

    log_info "等待服务启动..."
    sleep 10

    # 检查状态
    local failed=0
    for container in mysql redis trojan-panel trojan-panel-ui; do
        if ! ${COMPOSE_CMD} ps | grep -q "$container.*running"; then
            log_warn "容器 $container 可能未正常启动，请检查: ${COMPOSE_CMD} logs $container"
            failed=1
        fi
    done

    if [ $failed -eq 1 ]; then
        log_warn "部分容器启动异常，请查看日志排查"
    fi
}

# -------------------- 查看状态 --------------------
show_status() {
    echo ""
    echo "=========================================="
    echo "              服务状态"
    echo "=========================================="
    ${COMPOSE_CMD} ps
    echo ""
    echo "=========================================="
    echo "              访问地址"
    echo "=========================================="
    echo "  前端面板: http://你的服务器IP:80"
    echo "  后端 API: http://你的服务器IP:${SERVER_PORT}"
    echo "=========================================="
    echo ""
    echo "  日志查看: ${COMPOSE_CMD} logs -f"
    echo "  停止服务: ${COMPOSE_CMD} down"
    echo "  重新部署: bash deploy.sh"
    echo ""
}

# -------------------- 主流程 --------------------
main() {
    load_env

    # 交互式配置
    interactive_config
    show_config

    local confirm
    read -p "确认开始部署？[Y/n]: " confirm
    confirm="${confirm:-y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "已取消部署"
        exit 0
    fi

    check_docker
    pull_images
    generate_env
    start_services
    show_status

    log_info "部署完成!"
    log_info "首次登录请及时修改默认密码 (sysadmin / 123456)"
}

main "$@"
