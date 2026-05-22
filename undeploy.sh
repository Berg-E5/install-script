#!/bin/bash
# ============================================================
# Trojan Panel 卸载脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }

# 加载 .env (用于获取卷名)
load_env() {
    [ -f "$SCRIPT_DIR/.env" ] && set -a && source "$SCRIPT_DIR/.env" && set +a
}

echo ""
echo "=========================================="
echo "       Trojan Panel 卸载"
echo "=========================================="
echo ""

read -p "确定要卸载 Trojan Panel 吗？此操作会删除所有容器和数据！[y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "已取消卸载"
    exit 0
fi

load_env

# 检测 compose 命令
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    log_warn "未找到 docker-compose，将手动删除容器"
    COMPOSE_CMD=""
fi

echo ""

if [ -n "$COMPOSE_CMD" ] && [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    log_info "停止并删除容器..."
    ${COMPOSE_CMD} down -v --rmi local 2>/dev/null || ${COMPOSE_CMD} down 2>/dev/null || true
    log_info "已删除容器和数据卷"
else
    log_info "删除容器..."
    for container in trojan-panel-ui trojan-panel mysql redis; do
        docker rm -f "$container" 2>/dev/null || true
    done

    log_info "删除命名卷..."
    for vol in trojan-mysql-data trojan-redis-data trojan-panel-data; do
        docker volume rm "$vol" 2>/dev/null || true
    done

    log_info "删除镜像 (可选)..."
    for image in mysql:8.0 redis:7 \
                 ghcr.io/berg-e5/trojan-panel:${VERSION:-latest} \
                 ghcr.io/berg-e5/trojan-panel-ui:${VERSION:-latest}; do
        docker rmi "$image" 2>/dev/null || true
    done
fi

# 删除配置文件
if [ -f "$SCRIPT_DIR/.env" ]; then
    read -p "删除配置文件 .env ? [y/N]: " del_env
    if [[ "$del_env" =~ ^[Yy]$ ]]; then
        rm -f "$SCRIPT_DIR/.env"
        log_info "已删除 .env"
    fi
fi

echo ""
echo "=========================================="
log_info "卸载完成!"
echo "=========================================="
