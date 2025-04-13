#!/bin/bash

# 输出所有操作日志到文件
LOG_FILE="/var/log/gensyn-ai-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为 root 或 sudo 权限
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 或带 sudo 权限运行脚本。"
    exit 1
fi

# 设置脚本路径变量
SCRIPT_PATH="$HOME/gensyn-ai.sh"
PROJECT_DIR="$HOME/rl-swarm"

# 安装 gensyn-ai 节点
function install_gensyn_ai_node() {
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf \
        tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip \
        python3 python3-pip python3.10-venv xdg-utils

    # 安装 NVM（使用 safer 方式）
    if ! command -v nvm &> /dev/null; then
        echo "正在安装 NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
    else
        echo "NVM 已安装"
    fi

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # 安装 Node.js 18
    nvm install 18
    nvm use 18
    nvm alias default 18

    echo "当前 Node.js 版本：$(node -v)"
    echo "当前 npm 版本：$(npm -v)"

    # 安装 Yarn
    npm install -g yarn

    # 安装 Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        echo "Docker 安装完成。请重新登录或重启使 Docker 权限生效。"
    else
        echo "Docker 已安装"
    fi

    # 克隆仓库
    git clone https://github.com/gensyn-ai/rl-swarm.git "$PROJECT_DIR" || true
    cd "$PROJECT_DIR" || exit 1

    # 修复 run_rl_swarm.sh
    if [ -f "run_rl_swarm.sh" ]; then
        sed -i 's|open http://localhost:3000|xdg-open http://localhost:3000 2>/dev/null || echo "请手动打开 http://localhost:3000"|' run_rl_swarm.sh
        echo "已修改 run_rl_swarm.sh"
    else
        echo "未找到 run_rl_swarm.sh"
    fi

    # Python 虚拟环境
    python3 -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install "protobuf>=3.12.2,<5.28.0" --force-reinstall

    # Node.js 依赖
    rm -rf node_modules package-lock.json yarn.lock
    yarn install

    # 设置线程数
    CPU_CORES=$(nproc)
    DEFAULT_THREADS=$((CPU_CORES / 2))
    echo ""
    read -p "请输入线程数（建议：$DEFAULT_THREADS）: " USER_THREADS
    if ! [[ "$USER_THREADS" =~ ^[0-9]+$ ]]; then
        USER_THREADS=$DEFAULT_THREADS
    fi
    export OMP_NUM_THREADS="$USER_THREADS"
    echo "已设置 OMP_NUM_THREADS=$OMP_NUM_THREADS"

    # 启动服务
    if screen -list | grep -q "swarm"; then
        echo "已有 swarm 会话正在运行。"
    else
        if [ -f "./run_rl_swarm.sh" ]; then
            chmod +x run_rl_swarm.sh
            screen -S swarm -d -m bash -c "./run_rl_swarm.sh"
            echo "Swarm 已在后台运行（使用 screen）。"
        else
            screen -S swarm -d -m bash -c "python main.py"
            echo "未找到 run_rl_swarm.sh，已使用 Python 启动。"
        fi
    fi

    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 删除 gensyn-ai 节点
function delete_gensyn_ai_node() {
    echo "即将删除节点并清理 Docker 镜像。"
    read -p "确定继续吗？[y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        sudo systemctl stop docker
        sudo rm -rf "$PROJECT_DIR"
        sudo docker system prune -a -f
        sudo systemctl start docker
        echo "节点已删除，Docker 镜像已清理。"
    else
        echo "已取消删除操作。"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 日志查看
function view_logs() {
    case $1 in
        "swarm") cd "$PROJECT_DIR" && docker-compose logs -f swarm_node ;;
        "web") cd "$PROJECT_DIR" && docker-compose logs -f fastapi ;;
        "telemetry") cd "$PROJECT_DIR" && docker-compose logs -f otel-collector ;;
    esac
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "============================zh1p4ng==============================""
        echo "退出脚本请按 Ctrl + C"
        echo ""
        echo "1. 安装 gensyn-ai 节点"
        echo "2. 查看 RL Swarm 日志"
        echo "3. 查看 Web UI 日志"
        echo "4. 查看 Telemetry 日志"
        echo "5. 删除 gensyn-ai 节点"
        echo "6. 退出"
        read -p "请输入选项 [1-6]: " choice
        case $choice in
            1) install_gensyn_ai_node ;;
            2) view_logs "swarm" ;;
            3) view_logs "web" ;;
            4) view_logs "telemetry" ;;
            5) delete_gensyn_ai_node ;;
            6) exit 0 ;;
            *) echo "无效选项，请重试..."; sleep 2 ;;
        esac
    done
}

# 启动菜单
main_menu
