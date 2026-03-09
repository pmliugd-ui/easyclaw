#!/usr/bin/env bash
# ============================================================================
# EasyClaw — OpenClaw 中文一键部署脚本
# 适用系统: Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12, macOS
# 作者: pmliugd-ui
# 项目地址: https://github.com/pmliugd-ui/easyclaw
# 许可证: MIT
# ============================================================================

set -uo pipefail
# 注意: 不使用 set -e，因为在 macOS 的 bash 3.2 上
# read 命令和某些条件判断会返回非零导致脚本意外退出
# 我们通过 ERR trap 和显式错误检查来处理错误

# ======================== 颜色与样式定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # 恢复默认

# ======================== 全局变量 ========================
SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/openclaw_install_$(date +%Y%m%d_%H%M%S).log"
NODE_MAJOR=22
OPENCLAW_CONFIG_DIR=""
OS_TYPE=""
DISTRO=""
ARCH=""
TOTAL_STEPS=7
SKIP_ONBOARD=false
INSTALL_DOCKER=false
NON_INTERACTIVE=false
PROVIDER_CHOICE=""
API_KEY=""

# ======================== 工具函数 ========================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}"
    cat << 'BANNER'
  _____                 ____ _                
 | ____|__ _ ___ _   _ / ___| | __ ___      __
 |  _| / _` / __| | | | |   | |/ _` \ \ /\ / /
 | |__| (_| \__ \ |_| | |___| | (_| |\ V  V / 
 |_____\__,_|___/\__, |\____|_|\__,_| \_/\_/  
                  |___/                         
BANNER
    echo -e "${NC}"
    echo -e "${BOLD}  🦞 EasyClaw v${SCRIPT_VERSION} — OpenClaw 中文一键部署脚本${NC}"
    echo -e "${DIM}  ─────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${DIM}OpenClaw 是一个开源的本地 AI 助手，可以帮你:${NC}"
    echo -e "  ${DIM}  • 在 WhatsApp/Telegram/微信/飞书 等平台上使用 AI${NC}"
    echo -e "  ${DIM}  • 让 AI 帮你执行命令、读写文件、浏览网页${NC}"
    echo -e "  ${DIM}  • 设置定时任务、自动化工作流${NC}"
    echo -e "  ${DIM}  • 完全运行在你自己的电脑/服务器上，数据不外传${NC}"
    echo ""
    echo -e "  ${BOLD}本脚本将分 ${TOTAL_STEPS} 步引导你完成安装:${NC}"
    echo ""
    echo -e "    ${DIM}1. 检查系统环境${NC}"
    echo -e "    ${DIM}2. 安装系统依赖${NC}"
    echo -e "    ${DIM}3. 安装 Node.js (OpenClaw 的运行环境)${NC}"
    echo -e "    ${DIM}4. 配置 npm 镜像源 (加速下载)${NC}"
    echo -e "    ${DIM}5. 安装 OpenClaw 本体${NC}"
    echo -e "    ${DIM}6. 配置 AI 模型提供商 & API Key${NC}"
    echo -e "    ${DIM}7. 运行初始化向导 & 验证${NC}"
    echo ""
    echo -e "  ${YELLOW}💡 整个过程大约需要 5-15 分钟，取决于你的网络速度${NC}"
    echo -e "  ${YELLOW}💡 遇到选择题时，不确定就直接按 Enter 使用默认值${NC}"
    echo ""
}

info() {
    echo -e "  ${BLUE}ℹ${NC}  $*"
    log "[INFO] $*"
}

success() {
    echo -e "  ${GREEN}✔${NC}  $*"
    log "[SUCCESS] $*"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC}  $*"
    log "[WARN] $*"
}

error() {
    echo -e "  ${RED}✘${NC}  $*"
    log "[ERROR] $*"
}

tip() {
    echo -e "  ${CYAN}💡${NC} $*"
}

step() {
    local step_num="$1"
    local step_title="$2"
    echo ""
    echo -e "  ${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "  ${MAGENTA}${BOLD}  步骤 ${step_num}/${TOTAL_STEPS}：${step_title}${NC}"
    echo -e "  ${CYAN}═══════════════════════════════════════════════════${NC}"
    log "[STEP ${step_num}] $step_title"
}

substep() {
    echo ""
    echo -e "  ${BLUE}▶ $*${NC}"
    log "[SUBSTEP] $*"
}

ask() {
    echo -ne "  ${CYAN}?${NC}  $* "
}

show_cmd() {
    echo -e "     ${CYAN}\$${NC} ${BOLD}$1${NC}"
}

wait_for_user() {
    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    fi
    echo ""
    safe_read -rp "  按 Enter 键继续下一步..."
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local c="${spin:i++%${#spin}:1}"
        echo -ne "\r  ${CYAN}${c}${NC}  ${msg}"
        sleep 0.1
    done
    wait "$pid" 2>/dev/null
    local exit_code=$?
    echo -ne "\r"
    return $exit_code
}

run_with_spinner() {
    local msg="$1"
    shift
    ("$@") >> "$LOG_FILE" 2>&1 &
    local pid=$!
    spinner "$pid" "$msg"
    if [ $? -eq 0 ]; then
        success "$msg"
    else
        error "$msg — 失败！查看日志: $LOG_FILE"
        return 1
    fi
}

cmd_exists() {
    command -v "$1" &>/dev/null
}

# 安全的 read 封装，防止在 set -e 或 ERR trap 下意外退出
safe_read() {
    read "$@" || true
}

# ======================== 步骤 1：系统检测 ========================

detect_system() {
    step "1" "检查系统环境"
    echo ""
    info "这一步会检查你的操作系统、CPU 架构、磁盘空间和网络连通性"
    info "确保你的电脑满足 OpenClaw 的运行要求"
    echo ""

    substep "检测操作系统"
    case "$(uname -s)" in
        Linux*)  OS_TYPE="linux" ;;
        Darwin*) OS_TYPE="macos" ;;
        MINGW*|MSYS*|CYGWIN*) 
            error "检测到 Windows 系统"
            echo ""
            info "OpenClaw 不能直接在 Windows 上运行，但可以通过 WSL2 使用"
            info ""
            info "📋 安装 WSL2 的步骤:"
            info "  1. 以管理员身份打开 PowerShell"
            info "  2. 运行: wsl --install -d Ubuntu"
            info "  3. 重启电脑"
            info "  4. 打开「Ubuntu」应用"
            info "  5. 在 Ubuntu 终端里重新运行本脚本"
            exit 1
            ;;
        *)
            error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)
            error "不支持的 CPU 架构: $ARCH"
            exit 1
            ;;
    esac

    if [ "$OS_TYPE" = "linux" ]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO="$ID"
            success "操作系统: ${PRETTY_NAME:-$ID} ($ARCH)"
        else
            warn "无法检测 Linux 发行版，将以 Debian 系方式处理"
            DISTRO="debian"
        fi
    else
        DISTRO="macos"
        local mac_ver
        mac_ver=$(sw_vers -productVersion)
        success "操作系统: macOS $mac_ver ($ARCH)"
        if [ "$ARCH" = "arm64" ]; then
            info "检测到 Apple Silicon (M1/M2/M3/M4) 芯片"
        else
            info "检测到 Intel 芯片"
        fi
    fi

    OPENCLAW_CONFIG_DIR="$HOME/.openclaw"

    substep "检查磁盘空间"
    local available_gb
    if [ "$OS_TYPE" = "macos" ]; then
        available_gb=$(df -g "$HOME" | awk 'NR==2{print $4}')
    else
        available_gb=$(df -BG "$HOME" | awk 'NR==2{print $4}' | tr -d 'G')
    fi
    
    if [ "${available_gb:-0}" -lt 2 ]; then
        error "磁盘空间不足！需要至少 2GB，当前可用: ${available_gb}GB"
        info "请清理磁盘后重新运行"
        exit 1
    fi
    success "磁盘空间充足: ${available_gb}GB 可用 (需要 ≥2GB)"

    substep "检查网络连接"
    if curl -sS --max-time 5 https://registry.npmjs.org/ > /dev/null 2>&1; then
        success "网络连接正常 (可访问 npm 仓库)"
    else
        error "无法连接到 npm 仓库，请检查网络"
        echo ""
        info "如果你在中国大陆，网络可能比较慢，但通常不至于完全不通"
        info "可以尝试以下方法:"
        info "  1. 检查是否能打开网页"
        info "  2. 如果使用代理，确保终端也配置了代理"
        show_cmd "export https_proxy=http://127.0.0.1:7890"
        info "  3. 稍后步骤中可以切换为淘宝镜像源加速下载"
        exit 1
    fi

    if [ "$OS_TYPE" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
        info "检测到 WSL2 环境 (Windows 子系统)"
        if ! pidof systemd &>/dev/null; then
            warn "WSL2 中未启用 systemd"
            info "OpenClaw 的守护进程需要 systemd 才能开机自启"
            info "启用方法: 在 /etc/wsl.conf 中添加:"
            echo -e "    ${DIM}[boot]${NC}"
            echo -e "    ${DIM}systemd=true${NC}"
            info "修改后需要重启 WSL: wsl --shutdown"
        else
            success "WSL2 的 systemd 已启用"
        fi
    fi

    echo ""
    success "系统环境检查全部通过！"
    wait_for_user
}

# ======================== 步骤 2：系统依赖 ========================

install_system_deps() {
    step "2" "安装系统依赖"
    echo ""
    info "这一步会安装一些基础工具软件，比如 curl、git 等"
    info "这些是安装和运行 OpenClaw 必需的底层组件"
    echo ""

    if [ "$OS_TYPE" = "macos" ]; then
        substep "检查 Xcode 命令行工具"
        info "macOS 上编译软件需要 Xcode 命令行工具"
        
        if ! xcode-select -p &>/dev/null; then
            info "需要安装 Xcode 命令行工具"
            info "系统会弹出安装窗口，请点击「安装」按钮"
            xcode-select --install 2>/dev/null || true
            echo ""
            warn "请在弹出的窗口中完成安装"
            warn "安装完成后，请重新运行本脚本"
            exit 0
        fi
        success "Xcode 命令行工具已就绪"
        
        if ! cmd_exists brew; then
            substep "安装 Homebrew"
            info "Homebrew 是 macOS 上最流行的软件包管理器"
            info "相当于 Linux 上的 apt-get，可以方便地安装各种软件"
            echo ""
            ask "是否安装 Homebrew? (强烈推荐) [Y/n]:"
            local install_brew
            safe_read -r install_brew
            if [[ "${install_brew:-Y}" =~ ^[Yy] ]]; then
                info "正在安装 Homebrew，这可能需要几分钟..."
                tip "如果下载慢，可以 Ctrl+C 中断，配置代理后重试"
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                    warn "Homebrew 安装未完成，但这不影响后续安装"
                    warn "之后可以手动安装: https://brew.sh"
                }
                if [ "$ARCH" = "arm64" ]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
                else
                    eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
                fi
            fi
        else
            success "Homebrew 已安装"
        fi

        wait_for_user
        return 0
    fi

    # Linux
    local need_sudo=""
    if [ "$(id -u)" -ne 0 ]; then
        need_sudo="sudo"
    fi

    local deps=(curl wget git jq unzip build-essential)
    local to_install=()

    substep "检查必要的系统软件"
    for dep in "${deps[@]}"; do
        if dpkg -l "$dep" &>/dev/null 2>&1; then
            success "$dep 已安装"
        else
            to_install+=("$dep")
            info "$dep 需要安装"
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo ""
        info "需要安装以下软件: ${to_install[*]}"
        tip "这些都是常见的系统工具，不会影响你的其他软件"
        echo ""
        run_with_spinner "更新软件包列表" $need_sudo apt-get update -qq
        run_with_spinner "安装系统依赖" \
            $need_sudo apt-get install -y -qq "${to_install[@]}"
    else
        success "所有系统依赖已就绪，无需额外安装"
    fi

    wait_for_user
}

# ======================== 步骤 3：Node.js ========================

install_node() {
    step "3" "安装 Node.js 运行环境"
    echo ""
    info "Node.js 是 OpenClaw 的运行环境 (就像 Java 需要 JDK 一样)"
    info "OpenClaw 需要 Node.js 22 或更高版本"
    echo ""

    if cmd_exists node; then
        local node_ver
        node_ver=$(node -v | sed 's/v//' | cut -d. -f1)
        if [ "$node_ver" -ge "$NODE_MAJOR" ]; then
            success "Node.js $(node -v) 已安装，版本满足要求 (≥ v${NODE_MAJOR})"
            
            if cmd_exists npm; then
                success "npm v$(npm -v) 已安装"
            fi
            
            tip "无需安装，跳过此步骤"
            wait_for_user
            return 0
        else
            warn "Node.js $(node -v) 版本过低"
            info "当前版本: $(node -v), 需要: ≥ v${NODE_MAJOR}"
            info "将为你升级..."
        fi
    else
        info "未检测到 Node.js，需要安装"
    fi

    case "$OS_TYPE" in
        macos) install_node_macos ;;
        linux) install_node_linux ;;
    esac

    substep "验证 Node.js 安装"
    if cmd_exists node && [ "$(node -v | sed 's/v//' | cut -d. -f1)" -ge "$NODE_MAJOR" ]; then
        success "Node.js $(node -v) 安装成功"
        if cmd_exists npm; then
            success "npm v$(npm -v) 已就绪"
        fi
    else
        error "Node.js 安装失败"
        echo ""
        info "请尝试手动安装 Node.js ≥ v${NODE_MAJOR}:"
        echo ""
        info "方法 1 (推荐): 使用 fnm 版本管理器"
        show_cmd "curl -fsSL https://fnm.vercel.app/install | bash"
        show_cmd "fnm install ${NODE_MAJOR}"
        echo ""
        info "方法 2: 从官网下载"
        info "  访问 https://nodejs.org/zh-cn/ 下载 LTS 版本"
        echo ""
        info "安装完成后，重新运行本脚本即可"
        exit 1
    fi

    wait_for_user
}

install_node_macos() {
    substep "在 macOS 上安装 Node.js ${NODE_MAJOR}"

    if cmd_exists brew; then
        info "将使用 Homebrew 安装 Node.js ${NODE_MAJOR}"
        show_cmd "brew install node@${NODE_MAJOR}"
        echo ""
        run_with_spinner "安装 Node.js ${NODE_MAJOR}" brew install "node@${NODE_MAJOR}" || {
            info "尝试升级已有的 Node.js..."
            run_with_spinner "升级 Node.js" brew upgrade "node@${NODE_MAJOR}" || true
        }
        if ! cmd_exists node; then
            export PATH="/opt/homebrew/opt/node@${NODE_MAJOR}/bin:$PATH"
            local shell_rc="$HOME/.zshrc"
            if ! grep -q "node@${NODE_MAJOR}" "$shell_rc" 2>/dev/null; then
                echo "export PATH=\"/opt/homebrew/opt/node@${NODE_MAJOR}/bin:\$PATH\"" >> "$shell_rc"
                tip "已将 Node.js 路径添加到 ~/.zshrc"
            fi
        fi
    elif cmd_exists fnm; then
        run_with_spinner "通过 fnm 安装 Node.js ${NODE_MAJOR}" fnm install "$NODE_MAJOR"
        eval "$(fnm env)"
    else
        info "安装 fnm (Node.js 版本管理器)..."
        tip "fnm 可以让你轻松管理多个 Node.js 版本"
        curl -fsSL https://fnm.vercel.app/install | bash >> "$LOG_FILE" 2>&1
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env)" 2>/dev/null || true
        run_with_spinner "安装 Node.js ${NODE_MAJOR}" fnm install "$NODE_MAJOR"
        eval "$(fnm env)"
    fi
}

install_node_linux() {
    substep "在 Linux 上安装 Node.js ${NODE_MAJOR}"

    local need_sudo=""
    if [ "$(id -u)" -ne 0 ]; then
        need_sudo="sudo"
    fi

    info "使用 NodeSource 官方仓库安装 (最可靠的方式)"
    echo ""

    info "添加 NodeSource 仓库..."
    (
        $need_sudo apt-get update -qq
        $need_sudo apt-get install -y -qq ca-certificates curl gnupg
        $need_sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
            $need_sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | \
            $need_sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
        $need_sudo apt-get update -qq
    ) >> "$LOG_FILE" 2>&1

    run_with_spinner "安装 Node.js ${NODE_MAJOR}" \
        $need_sudo apt-get install -y -qq nodejs
}

# ======================== 步骤 4：npm 镜像源 ========================

configure_npm_mirror() {
    step "4" "配置 npm 下载镜像源"
    echo ""
    info "npm 是 Node.js 的包管理器，用来下载和安装 OpenClaw"
    info "默认从国外服务器下载，如果你在中国大陆，速度可能会很慢"
    info "切换到淘宝镜像源可以大幅提升下载速度"
    echo ""

    echo -e "  ${BOLD}选择 npm 镜像源:${NC}"
    echo ""
    echo -e "    ${CYAN}1)${NC} npm 官方源 (registry.npmjs.org)"
    echo -e "       ${DIM}适合: 海外服务器、已有代理的用户${NC}"
    echo ""
    echo -e "    ${CYAN}2)${NC} 淘宝镜像源 (registry.npmmirror.com) ${GREEN}⭐ 大陆推荐${NC}"
    echo -e "       ${DIM}适合: 中国大陆用户，速度快 10-50 倍${NC}"
    echo ""
    echo -e "    ${CYAN}3)${NC} 保持当前设置不变"
    echo ""

    if [ "$NON_INTERACTIVE" = true ]; then
        info "非交互模式，保持当前 npm 源设置"
        wait_for_user
        return 0
    fi

    local choice
    ask "请选择 [1/2/3，默认 3]:"
    safe_read -r choice
    choice="${choice:-3}"

    case "$choice" in
        1)
            npm config set registry https://registry.npmjs.org/
            success "已设置为 npm 官方源"
            ;;
        2)
            npm config set registry https://registry.npmmirror.com/
            success "已设置为淘宝镜像源 (国内下载会快很多)"
            ;;
        3)
            local current
            current=$(npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/")
            info "保持当前源: $current"
            ;;
        *)
            info "无效输入，保持当前设置"
            ;;
    esac

    wait_for_user
}

# ======================== 步骤 5：安装 OpenClaw ========================

install_openclaw() {
    step "5" "安装 OpenClaw 本体"
    echo ""
    info "现在开始安装 OpenClaw —— 这是今天的主角！🦞"
    info "它会通过 npm 全局安装到你的系统中"
    echo ""

    if cmd_exists openclaw; then
        local current_ver
        current_ver=$(openclaw --version 2>/dev/null || echo "unknown")
        success "检测到 OpenClaw 已安装 (版本: $current_ver)"
        echo ""
        echo -e "    ${CYAN}1)${NC} 升级到最新版本 (推荐，获取最新功能和修复)"
        echo -e "    ${CYAN}2)${NC} 保持当前版本，继续后续配置"
        echo ""

        if [ "$NON_INTERACTIVE" = true ]; then
            local choice="1"
        else
            ask "请选择 [1/2，默认 2]:"
            local choice
            safe_read -r choice
            choice="${choice:-2}"
        fi

        if [ "$choice" = "1" ]; then
            run_with_spinner "升级 OpenClaw 到最新版本" npm install -g openclaw@latest
            success "OpenClaw 已升级到 $(openclaw --version 2>/dev/null || echo 'latest')"
        else
            info "保持当前版本"
        fi
    else
        info "官方推荐安装命令:"
        show_cmd "npm install -g openclaw@latest"
        echo ""
        tip "安装过程可能需要 1-5 分钟，取决于网络速度"
        tip "如果长时间没反应，可能是网络问题，Ctrl+C 中断后换淘宝源重试"
        echo ""

        export SHARP_IGNORE_GLOBAL_LIBVIPS=1

        if run_with_spinner "下载并安装 OpenClaw (请耐心等待)" npm install -g openclaw@latest; then
            success "OpenClaw 安装成功！🎉"
        else
            error "OpenClaw 安装失败"
            echo ""
            info "常见原因和解决方法:"
            echo ""
            info "  ❶ 网络太慢 → 切换淘宝源后重试:"
            show_cmd "npm config set registry https://registry.npmmirror.com"
            show_cmd "npm install -g openclaw@latest"
            echo ""
            info "  ❷ npm 缓存损坏 → 清除缓存后重试:"
            show_cmd "npm cache clean --force"
            show_cmd "npm install -g openclaw@latest"
            echo ""
            info "  ❸ 权限问题 → 如果提示 EACCES 错误:"
            show_cmd "sudo npm install -g openclaw@latest"
            echo ""
            info "  ❹ sharp 模块编译失败:"
            show_cmd "SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest"
            exit 1
        fi
    fi

    ensure_path

    substep "验证 OpenClaw 安装"
    if cmd_exists openclaw; then
        success "openclaw 命令可用: $(openclaw --version 2>/dev/null || echo 'ok')"
    else
        warn "openclaw 命令暂时找不到"
        tip "这通常是 PATH 问题，请打开新终端窗口，或运行:"
        show_cmd "source ~/.zshrc  # 或 source ~/.bashrc"
    fi

    wait_for_user
}

ensure_path() {
    if ! cmd_exists openclaw; then
        local npm_prefix
        npm_prefix="$(npm prefix -g 2>/dev/null)/bin"
        
        if [ -f "$npm_prefix/openclaw" ]; then
            export PATH="$npm_prefix:$PATH"
            
            local shell_rc=""
            if [ -f "$HOME/.zshrc" ]; then
                shell_rc="$HOME/.zshrc"
            elif [ -f "$HOME/.bashrc" ]; then
                shell_rc="$HOME/.bashrc"
            fi

            if [ -n "$shell_rc" ]; then
                if ! grep -q 'npm prefix' "$shell_rc" 2>/dev/null; then
                    echo "export PATH=\"\$(npm prefix -g)/bin:\$PATH\"" >> "$shell_rc"
                    info "已将 npm 全局路径添加到 $shell_rc"
                fi
            fi
        else
            warn "openclaw 命令未找到，请检查 npm 全局安装路径"
        fi
    fi
}

# ======================== 步骤 6：AI 提供商配置 ========================

configure_provider() {
    step "6" "配置 AI 模型提供商"
    echo ""
    info "OpenClaw 本身是一个「框架」，它需要连接一个 AI 大模型才能工作"
    info "就像手机需要 SIM 卡才能打电话一样，OpenClaw 需要 API Key 才能用 AI"
    echo ""
    info "你需要:"
    info "  1. 选择一个 AI 提供商 (比如 Anthropic、OpenAI、OpenRouter 等)"
    info "  2. 去他们的官网注册账号，获取一个 API Key (一串密钥字符)"
    info "  3. 把 API Key 填入 OpenClaw 的配置中"
    echo ""
    tip "API Key 就像密码一样重要，请妥善保管，不要分享给他人"
    echo ""

    # 检查是否已有配置
    if [ -f "$OPENCLAW_CONFIG_DIR/openclaw.json" ] || [ -f "$OPENCLAW_CONFIG_DIR/openclaw.json5" ]; then
        success "检测到已有 OpenClaw 配置文件"
        echo ""
        echo -e "    ${CYAN}1)${NC} 使用已有配置，跳过此步"
        echo -e "    ${CYAN}2)${NC} 重新配置 AI 提供商"
        echo ""

        if [ "$NON_INTERACTIVE" = true ]; then
            info "非交互模式，保持已有配置"
            return 0
        fi

        ask "请选择 [1/2，默认 1]:"
        local choice
        safe_read -r choice
        if [ "${choice:-1}" = "1" ]; then
            info "保持已有配置"
            return 0
        fi
    fi

    echo ""
    echo -e "  ${BOLD}选择你的 AI 模型提供商:${NC}"
    echo ""
    echo -e "    ${CYAN}1)${NC} ${BOLD}Anthropic Claude${NC} ${GREEN}⭐ 综合推荐${NC}"
    echo -e "       ${DIM}效果最佳的 AI 模型之一，OpenClaw 官方推荐${NC}"
    echo -e "       ${DIM}需要海外网络 | 需要绑定信用卡${NC}"
    echo ""
    echo -e "    ${CYAN}2)${NC} ${BOLD}OpenAI${NC}"
    echo -e "       ${DIM}GPT-4o / GPT-5 系列，广泛使用${NC}"
    echo -e "       ${DIM}需要海外网络 | 需要绑定信用卡${NC}"
    echo ""
    echo -e "    ${CYAN}3)${NC} ${BOLD}OpenRouter${NC} ${GREEN}⭐ 新手友好${NC}"
    echo -e "       ${DIM}一个 Key 就能用所有主流模型 (Claude/GPT/Gemini/...)${NC}"
    echo -e "       ${DIM}支持免费模型 | 按量付费，门槛最低${NC}"
    echo ""
    echo -e "    ${CYAN}4)${NC} ${BOLD}Groq${NC} ${GREEN}⭐ 免费体验${NC}"
    echo -e "       ${DIM}有免费额度，推理速度极快${NC}"
    echo -e "       ${DIM}适合先体验，之后再换更强的模型${NC}"
    echo ""
    echo -e "    ${CYAN}5)${NC} ${BOLD}Ollama (本地运行)${NC}"
    echo -e "       ${DIM}在你的电脑上运行 AI 模型，完全离线，不花钱${NC}"
    echo -e "       ${DIM}但需要较好的 GPU 或 Apple Silicon 芯片${NC}"
    echo ""
    echo -e "    ${CYAN}6)${NC} ${BOLD}自定义 / 国内提供商${NC}"
    echo -e "       ${DIM}DeepSeek / 硅基流动 / Kimi / 零一万物 / OneAPI 等${NC}"
    echo -e "       ${DIM}国内直接访问，速度快，价格便宜${NC}"
    echo ""
    echo -e "    ${CYAN}7)${NC} ${BOLD}稍后配置${NC}"
    echo -e "       ${DIM}跳过此步，之后用 openclaw configure 配置${NC}"
    echo ""

    if [ "$NON_INTERACTIVE" = true ] && [ -n "$PROVIDER_CHOICE" ]; then
        local choice="$PROVIDER_CHOICE"
    else
        ask "请选择 [1-7，默认 7]:"
        local choice
        safe_read -r choice
        choice="${choice:-7}"
    fi

    case "$choice" in
        1) configure_anthropic ;;
        2) configure_openai ;;
        3) configure_openrouter ;;
        4) configure_groq ;;
        5) configure_ollama ;;
        6) configure_custom ;;
        7) 
            info "跳过 AI 提供商配置"
            info "之后可以运行以下命令配置:"
            show_cmd "openclaw configure"
            SKIP_ONBOARD=true
            ;;
        *)
            warn "无效选择，将跳过配置"
            SKIP_ONBOARD=true
            ;;
    esac

    wait_for_user
}

configure_anthropic() {
    PROVIDER_CHOICE="anthropic"
    echo ""
    info "你选择了 Anthropic Claude —— 好选择！"
    echo ""
    echo -e "  ${BOLD}📋 获取 API Key 的步骤:${NC}"
    echo ""
    echo -e "    ${DIM}1. 打开 https://console.anthropic.com/${NC}"
    echo -e "    ${DIM}2. 注册/登录 Anthropic 账号 (需要海外网络)${NC}"
    echo -e "    ${DIM}3. 登录后点击左侧菜单「API Keys」${NC}"
    echo -e "    ${DIM}4. 点击「Create Key」按钮${NC}"
    echo -e "    ${DIM}5. 给 Key 起个名字 (如 \"openclaw\")${NC}"
    echo -e "    ${DIM}6. 复制生成的 Key (以 sk-ant- 开头)${NC}"
    echo -e "    ${DIM}7. ⚠️  Key 只显示一次，请立即复制保存！${NC}"
    echo ""
    tip "Anthropic 需要绑定信用卡才能使用 API"
    tip "推荐模型: Claude Sonnet 4 (性价比最高)"
    echo ""

    if [ "$NON_INTERACTIVE" = true ] && [ -n "$API_KEY" ]; then
        return 0
    fi

    ask "请粘贴你的 Anthropic API Key (留空则稍后配置):"
    safe_read -rs API_KEY
    echo ""

    if [ -z "$API_KEY" ]; then
        warn "未输入 API Key"
        tip "没关系！稍后的 onboard 向导中还会再次让你输入"
        API_KEY=""
    else
        success "API Key 已记录 (sk-ant-...${API_KEY: -4})"
    fi
}

configure_openai() {
    PROVIDER_CHOICE="openai"
    echo ""
    info "你选择了 OpenAI"
    echo ""
    echo -e "  ${BOLD}📋 获取 API Key 的步骤:${NC}"
    echo ""
    echo -e "    ${DIM}1. 打开 https://platform.openai.com/${NC}"
    echo -e "    ${DIM}2. 注册/登录 OpenAI 账号 (需要海外网络)${NC}"
    echo -e "    ${DIM}3. 点击右上角头像 → 「API keys」${NC}"
    echo -e "    ${DIM}4. 点击「Create new secret key」${NC}"
    echo -e "    ${DIM}5. 复制生成的 Key (以 sk- 开头)${NC}"
    echo -e "    ${DIM}6. ⚠️  Key 只显示一次，请立即保存！${NC}"
    echo ""
    warn "注意: OpenAI 需要绑定海外信用卡才能使用 API"
    echo ""

    if [ "$NON_INTERACTIVE" = true ] && [ -n "$API_KEY" ]; then
        return 0
    fi

    ask "请粘贴你的 OpenAI API Key (留空则稍后配置):"
    safe_read -rs API_KEY
    echo ""

    if [ -z "$API_KEY" ]; then
        warn "未输入 API Key"
        tip "稍后的 onboard 向导中还会再次让你输入"
    else
        success "API Key 已记录 (sk-...${API_KEY: -4})"
    fi
}

configure_openrouter() {
    PROVIDER_CHOICE="openrouter"
    echo ""
    info "你选择了 OpenRouter —— 非常适合新手！"
    echo ""
    echo -e "  ${BOLD}📋 获取 API Key 的步骤:${NC}"
    echo ""
    echo -e "    ${DIM}1. 打开 https://openrouter.ai/${NC}"
    echo -e "    ${DIM}2. 点击右上角「Sign In」用 Google/GitHub 登录${NC}"
    echo -e "    ${DIM}3. 登录后点击右上角头像 → 「Keys」${NC}"
    echo -e "    ${DIM}4. 点击「Create Key」${NC}"
    echo -e "    ${DIM}5. 复制生成的 Key (以 sk-or- 开头)${NC}"
    echo ""
    tip "OpenRouter 的优势:"
    tip "  • 一个 Key 就能用 Claude、GPT、Gemini 等所有模型"
    tip "  • 支持免费模型 (如 Llama)，可以先体验不花钱"
    tip "  • 按量付费，充值 $5 就能用很久"
    echo ""

    if [ "$NON_INTERACTIVE" = true ] && [ -n "$API_KEY" ]; then
        return 0
    fi

    ask "请粘贴你的 OpenRouter API Key (留空则稍后配置):"
    safe_read -rs API_KEY
    echo ""

    if [ -z "$API_KEY" ]; then
        warn "未输入 API Key"
        tip "稍后的 onboard 向导中还会再次让你输入"
    else
        success "API Key 已记录 (sk-or-...${API_KEY: -4})"
    fi
}

configure_groq() {
    PROVIDER_CHOICE="groq"
    echo ""
    info "你选择了 Groq —— 速度超快且有免费额度！"
    echo ""
    echo -e "  ${BOLD}📋 获取 API Key 的步骤:${NC}"
    echo ""
    echo -e "    ${DIM}1. 打开 https://console.groq.com/${NC}"
    echo -e "    ${DIM}2. 用 Google/GitHub 账号注册登录${NC}"
    echo -e "    ${DIM}3. 点击左侧菜单「API Keys」${NC}"
    echo -e "    ${DIM}4. 点击「Create API Key」${NC}"
    echo -e "    ${DIM}5. 复制生成的 Key${NC}"
    echo ""
    tip "Groq 提供免费额度，非常适合先试用体验"
    tip "推理速度极快 (比其他服务快 5-10 倍)"
    tip "支持 Llama 3、Mixtral 等开源模型"
    echo ""

    if [ "$NON_INTERACTIVE" = true ] && [ -n "$API_KEY" ]; then
        return 0
    fi

    ask "请粘贴你的 Groq API Key (留空则稍后配置):"
    safe_read -rs API_KEY
    echo ""

    if [ -z "$API_KEY" ]; then
        warn "未输入 API Key"
        tip "稍后的 onboard 向导中还会再次让你输入"
    else
        success "API Key 已记录 (...${API_KEY: -4})"
    fi
}

configure_ollama() {
    PROVIDER_CHOICE="ollama"
    echo ""
    info "你选择了 Ollama —— 完全本地运行，隐私优先！"
    echo ""
    info "Ollama 可以让你在自己的电脑上运行 AI 模型"
    info "  优点: 完全离线、不花钱、数据不出你的电脑"
    info "  缺点: 需要较好的硬件 (推荐 16GB 内存 + GPU 或 Apple Silicon)"
    echo ""

    if cmd_exists ollama; then
        success "Ollama 已安装"
        local models
        models=$(ollama list 2>/dev/null | tail -n +2 || true)
        if [ -n "$models" ]; then
            info "你已经下载的模型:"
            echo "$models" | head -5 | while read -r line; do
                echo -e "      ${DIM}$line${NC}"
            done
        else
            echo ""
            info "你还没有下载任何模型，推荐下载一个试试:"
            echo ""
            echo -e "    ${CYAN}ollama pull llama3.2${NC}"
            echo -e "    ${DIM}  → Meta 的 Llama 3.2，小巧快速，约 2GB${NC}"
            echo ""
            echo -e "    ${CYAN}ollama pull qwen2.5${NC}"
            echo -e "    ${DIM}  → 阿里的通义千问，中文特别好，约 4.7GB${NC}"
            echo ""
            echo -e "    ${CYAN}ollama pull deepseek-r1${NC}"
            echo -e "    ${DIM}  → DeepSeek R1，推理能力强，约 4.7GB${NC}"
        fi
    else
        warn "Ollama 还没有安装"
        echo ""
        echo -e "  ${BOLD}📋 安装 Ollama 的步骤:${NC}"
        echo ""
        echo -e "    ${DIM}方法 1: 访问 https://ollama.com 下载安装包${NC}"
        echo -e "    ${DIM}方法 2: 在终端运行:${NC}"
        show_cmd "curl -fsSL https://ollama.com/install.sh | sh"
        echo -e "    ${DIM}安装完成后下载一个模型:${NC}"
        show_cmd "ollama pull llama3.2"
        echo ""

        ask "是否现在安装 Ollama? [y/N]:"
        local install_ollama
        safe_read -r install_ollama
        if [[ "$install_ollama" =~ ^[Yy] ]]; then
            run_with_spinner "安装 Ollama" bash -c "curl -fsSL https://ollama.com/install.sh | sh"
            if cmd_exists ollama; then
                success "Ollama 安装完成！"
                tip "记得下载模型哦: ollama pull llama3.2"
            fi
        fi
    fi
    API_KEY=""
}

configure_custom() {
    PROVIDER_CHOICE="custom"
    echo ""
    info "配置自定义 / 国内 AI 提供商"
    echo ""
    info "适用于兼容 OpenAI API 格式的服务，包括:"
    echo ""
    echo -e "    ${DIM}• DeepSeek     官网: https://platform.deepseek.com/${NC}"
    echo -e "    ${DIM}• 硅基流动     官网: https://cloud.siliconflow.cn/${NC}"
    echo -e "    ${DIM}• Kimi/月之暗面 官网: https://platform.moonshot.cn/${NC}"
    echo -e "    ${DIM}• 零一万物     官网: https://platform.lingyiwanwu.com/${NC}"
    echo -e "    ${DIM}• OneAPI/NewAPI  你自己搭建的中转服务${NC}"
    echo ""
    tip "这些服务在中国大陆可以直接访问，速度快，价格便宜"
    echo ""
    info "你需要提供三个信息: API 地址、API Key、模型名称"
    echo ""

    ask "请输入 API Base URL (例: https://api.deepseek.com/v1):"
    local base_url
    safe_read -r base_url
    echo ""

    ask "请输入 API Key:"
    safe_read -rs API_KEY
    echo ""
    echo ""

    ask "请输入模型名称 (例: deepseek-chat):"
    local model_id
    safe_read -r model_id

    if [ -n "$base_url" ] && [ -n "$API_KEY" ]; then
        export CUSTOM_BASE_URL="$base_url"
        export CUSTOM_MODEL_ID="${model_id:-gpt-4}"
        export CUSTOM_API_KEY="$API_KEY"
        
        success "自定义提供商配置已记录"
        info "  API 地址: $base_url"
        info "  模型名称: ${model_id:-gpt-4}"
    else
        warn "信息不完整，将在 onboard 向导中手动配置"
    fi
}

# ======================== 步骤 7：Onboard + 验证 ========================

run_onboard() {
    step "7" "运行初始化向导 & 验证安装"
    echo ""
    info "最后一步！OpenClaw 自带一个初始化向导 (onboard)"
    info "向导会帮你完成以下事情:"
    info "  • 创建工作空间和配置文件"
    info "  • 设置 Gateway 守护进程 (让 OpenClaw 在后台持续运行)"
    info "  • 连接你选择的 AI 模型提供商"
    info "  • 可选: 配置消息通道 (WhatsApp/Telegram/Discord 等)"
    info "  • 可选: 安装推荐的 Skills 扩展功能"
    echo ""

    if [ "$SKIP_ONBOARD" = true ]; then
        info "你选择了稍后配置，跳过 onboard 向导"
        echo ""
        info "之后运行以下命令完成初始化:"
        show_cmd "openclaw onboard --install-daemon"
        echo ""
        tip "或者使用简化版配置向导:"
        show_cmd "openclaw configure"
        echo ""
        verify_installation
        return 0
    fi

    # 构建 onboard 命令
    local onboard_cmd="openclaw onboard --install-daemon"

    if [ -n "$API_KEY" ]; then
        case "$PROVIDER_CHOICE" in
            anthropic)
                export ANTHROPIC_API_KEY="$API_KEY"
                onboard_cmd="$onboard_cmd --auth-choice anthropic-api-key --anthropic-api-key \"\$ANTHROPIC_API_KEY\""
                ;;
            openai)
                export OPENAI_API_KEY="$API_KEY"
                onboard_cmd="$onboard_cmd --auth-choice openai-api-key --openai-api-key \"\$OPENAI_API_KEY\""
                ;;
            openrouter)
                export OPENROUTER_API_KEY="$API_KEY"
                onboard_cmd="$onboard_cmd --auth-choice apiKey --token-provider openrouter --token \"\$OPENROUTER_API_KEY\""
                ;;
            custom)
                onboard_cmd="$onboard_cmd --auth-choice custom-api-key"
                [ -n "${CUSTOM_BASE_URL:-}" ] && onboard_cmd="$onboard_cmd --custom-base-url \"$CUSTOM_BASE_URL\""
                [ -n "${CUSTOM_MODEL_ID:-}" ] && onboard_cmd="$onboard_cmd --custom-model-id \"$CUSTOM_MODEL_ID\""
                [ -n "$API_KEY" ] && onboard_cmd="$onboard_cmd --custom-api-key \"\$CUSTOM_API_KEY\""
                onboard_cmd="$onboard_cmd --custom-compatibility openai"
                ;;
        esac
    fi

    echo ""
    echo -e "  ${YELLOW}${BOLD}📌 向导操作提示 (第一次用请仔细看):${NC}"
    echo ""
    echo -e "  ${YELLOW}  • 用 ↑↓ 方向键 在选项之间移动，按 Enter 确认选择${NC}"
    echo -e "  ${YELLOW}  • 不确定选什么? 直接按 Enter 使用默认值就好${NC}"
    echo -e "  ${YELLOW}  • 需要输入密钥时: 粘贴后按 Enter (输入不会显示在屏幕上)${NC}"
    echo -e "  ${YELLOW}  • 向导卡住了? 按 Ctrl+C 中断，不会损坏任何东西${NC}"
    echo -e "  ${YELLOW}  • 搞砸了? 可以随时重新运行: openclaw onboard --install-daemon${NC}"
    echo ""

    ask "准备好了? 按 Enter 启动向导..."
    safe_read -r

    echo ""
    echo -e "  ${CYAN}════════════════ OpenClaw 向导开始 ════════════════${NC}"
    echo ""
    
    eval "$onboard_cmd" || {
        local exit_code=$?
        echo ""
        echo -e "  ${CYAN}════════════════ OpenClaw 向导结束 ════════════════${NC}"
        echo ""
        
        if [ $exit_code -ne 0 ]; then
            warn "向导未完全成功 (退出码: $exit_code)"
            echo ""
            info "这通常不是致命错误，常见原因:"
            info "  • API Key 不正确 → 稍后编辑配置文件修改"
            info "  • 网络连接中断 → 检查网络后重新运行向导"
            info "  • 某个可选步骤跳过了 → 完全正常，不影响使用"
            echo ""
            info "你可以随时重新运行向导:"
            show_cmd "openclaw onboard --install-daemon"
            echo ""
        fi
    }
    
    echo ""
    echo -e "  ${CYAN}════════════════ OpenClaw 向导结束 ════════════════${NC}"

    verify_installation
}

verify_installation() {
    echo ""
    substep "验证安装结果"

    if cmd_exists openclaw; then
        success "openclaw 命令可用 — $(openclaw --version 2>/dev/null || echo 'ok')"
    else
        error "openclaw 命令不可用"
        tip "请打开新终端窗口重试"
    fi

    if [ -f "$OPENCLAW_CONFIG_DIR/openclaw.json" ] || [ -f "$OPENCLAW_CONFIG_DIR/openclaw.json5" ]; then
        success "配置文件已生成"
    else
        if [ "$SKIP_ONBOARD" = true ]; then
            info "配置文件尚未生成 (运行 onboard 后会自动创建)"
        else
            warn "配置文件未找到"
        fi
    fi

    if cmd_exists openclaw; then
        echo ""
        info "运行健康检查..."
        echo ""
        openclaw doctor 2>&1 | head -20 | while IFS= read -r line; do
            echo -e "    ${DIM}$line${NC}"
        done
        echo ""

        local status_output
        status_output=$(openclaw status 2>&1 || true)
        if echo "$status_output" | grep -qi "running\|active\|online"; then
            success "OpenClaw Gateway 正在运行！"
        else
            info "Gateway 尚未运行 (这可能是正常的)"
            tip "手动启动: openclaw gateway"
        fi
    fi
}

# ======================== 完成提示 ========================

print_completion() {
    echo ""
    echo ""
    echo -e "  ${GREEN}${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}${BOLD}║                                                       ║${NC}"
    echo -e "  ${GREEN}${BOLD}║        🎉🦞 OpenClaw 安装完成！恭喜你！🦞🎉          ║${NC}"
    echo -e "  ${GREEN}${BOLD}║                                                       ║${NC}"
    echo -e "  ${GREEN}${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}🚀 接下来你可以做这些事:${NC}"
    echo ""
    echo -e "    ${CYAN}1.${NC} 打开 Web 控制面板 (在浏览器中和 AI 对话):"
    show_cmd "openclaw dashboard"
    echo ""
    echo -e "    ${CYAN}2.${NC} 查看运行状态:"
    show_cmd "openclaw status"
    echo ""
    echo -e "    ${CYAN}3.${NC} 把 AI 助手连接到你的聊天软件:"
    show_cmd "openclaw channel add telegram    # Telegram 机器人"
    show_cmd "openclaw channel add whatsapp    # WhatsApp"
    show_cmd "openclaw channel add discord     # Discord"
    show_cmd "openclaw channel add wechat      # 微信"
    show_cmd "openclaw channel add feishu      # 飞书"
    echo ""
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}🔧 日常维护命令速查:${NC}"
    echo ""
    echo -e "    ${CYAN}openclaw doctor${NC}        诊断问题 (遇到问题先跑这个)"
    echo -e "    ${CYAN}openclaw configure${NC}     修改配置"
    echo -e "    ${CYAN}openclaw gateway${NC}       启动/重启 Gateway"
    echo -e "    ${CYAN}openclaw --help${NC}        查看所有可用命令"
    echo ""
    echo -e "  ${BOLD}📂 重要文件位置:${NC}"
    echo ""
    echo -e "    ${DIM}配置文件:${NC}  $OPENCLAW_CONFIG_DIR/openclaw.json"
    echo -e "    ${DIM}安装日志:${NC}  $LOG_FILE"
    echo ""
    echo -e "  ${BOLD}📖 学习资源:${NC}"
    echo ""
    echo -e "    ${DIM}官方文档:${NC}  https://docs.openclaw.ai"
    echo -e "    ${DIM}GitHub:${NC}    https://github.com/openclaw/openclaw"
    echo ""
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ -z "$API_KEY" ] && [ "$SKIP_ONBOARD" = true ]; then
        echo -e "  ${YELLOW}${BOLD}⚠ 别忘了！你还需要配置 AI 提供商才能开始使用${NC}"
        echo ""
        echo -e "    运行初始化向导:"
        show_cmd "openclaw onboard --install-daemon"
        echo ""
        echo -e "    或手动编辑配置文件:"
        show_cmd "nano $OPENCLAW_CONFIG_DIR/openclaw.json"
        echo ""
    fi

    echo -e "  ${DIM}💡 如果 openclaw 命令未找到，请打开一个新终端窗口重试${NC}"
    echo ""
    echo -e "  ${GREEN}感谢使用 EasyClaw！祝你和你的 AI 助手愉快相处 🦞${NC}"
    echo ""
}

# ======================== 命令行参数 ========================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive|-n)
                NON_INTERACTIVE=true
                shift
                ;;
            --skip-onboard)
                SKIP_ONBOARD=true
                shift
                ;;
            --provider)
                PROVIDER_CHOICE="$2"
                shift 2
                ;;
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "EasyClaw v$SCRIPT_VERSION — OpenClaw 中文一键部署脚本"
                exit 0
                ;;
            *)
                error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo ""
    echo "🦞 EasyClaw v$SCRIPT_VERSION — OpenClaw 中文一键部署脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --non-interactive, -n   非交互模式，跳过所有确认"
    echo "  --skip-onboard          跳过 onboard 初始化向导"
    echo "  --provider <name>       指定 AI 提供商"
    echo "                          可选: anthropic / openai / openrouter / groq / ollama"
    echo "  --api-key <key>         指定 API Key"
    echo "  --help, -h              显示帮助信息"
    echo "  --version, -v           显示版本号"
    echo ""
    echo "示例:"
    echo ""
    echo "  # 交互式安装 (推荐新手)"
    echo "  bash install.sh"
    echo ""
    echo "  # 一行命令完成 (适合老手)"
    echo "  bash install.sh --provider anthropic --api-key sk-ant-xxx"
    echo ""
    echo "  # 只安装不配置 (之后手动 onboard)"
    echo "  bash install.sh --skip-onboard"
    echo ""
}

# ======================== 安全检查 ========================

security_check() {
    if [ "$(id -u)" -eq 0 ] && [ "${OS_TYPE:-linux}" = "linux" ]; then
        warn "检测到正在以 root 用户运行"
        echo ""
        info "npm 在 root 下全局安装可能导致权限问题"
        info "建议: 使用普通用户运行本脚本，需要时会自动使用 sudo"
        echo ""
        ask "是否继续以 root 身份安装? [y/N]:"
        local continue_as_root
        safe_read -r continue_as_root
        if [[ ! "$continue_as_root" =~ ^[Yy] ]]; then
            info "请使用普通用户重新运行本脚本"
            exit 0
        fi
    fi
}

# ======================== 主流程 ========================

main() {
    parse_args "$@"
    print_banner

    if [ "$NON_INTERACTIVE" != true ]; then
        ask "准备好了吗? 按 Enter 开始安装..."
        safe_read -r
    fi

    security_check
    detect_system          # 步骤 1
    install_system_deps    # 步骤 2
    install_node           # 步骤 3
    configure_npm_mirror   # 步骤 4
    install_openclaw       # 步骤 5
    configure_provider     # 步骤 6
    run_onboard            # 步骤 7
    print_completion
}

# 捕获未预期的错误
trap 'error "EasyClaw 脚本在第 $LINENO 行出错，退出码: $?"; echo ""; info "查看详细日志: $LOG_FILE"; echo ""; tip "如果问题持续，可以截图日志到 GitHub 提 issue: github.com/pmliugd-ui/easyclaw"; exit 1' ERR

# 运行
main "$@"
exit 0
