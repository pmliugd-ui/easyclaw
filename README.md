# 🦞 EasyClaw — OpenClaw 中文一键部署脚本

> 专为中文用户打造的 OpenClaw 一键安装工具，全中文引导，小白友好。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%7C22.04%7C24.04-orange)](https://ubuntu.com/)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue)](https://www.apple.com/macos/)

## ⚠️ 安全提示

近期出现了假冒的 OpenClaw 安装器传播恶意软件的情况。请务必：
- **只从本仓库或 OpenClaw 官方渠道下载安装脚本**
- 运行前检查脚本内容：`cat install.sh | less`
- 不要运行来历不明的"一键安装"脚本

## ✨ 特性

- 🇨🇳 **全中文界面** — 所有提示和引导均为中文
- 🎯 **一键安装** — 自动处理 Node.js、npm、依赖等全部环节
- 🧭 **交互式引导** — 逐步引导配置 AI 提供商、API Key，每步都告诉你为什么
- 🌐 **镜像源支持** — 内置淘宝 npm 镜像，国内安装不卡顿
- 🤖 **多模型支持** — Anthropic / OpenAI / OpenRouter / Groq / Ollama / 自定义
- 📱 **多平台适配** — Ubuntu / Debian / macOS / WSL2
- 🔧 **智能检测** — 自动检测已有环境，避免重复安装
- 📝 **完整日志** — 全程记录安装日志，方便排查问题

## 🚀 快速开始

### 一行命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/pmliugd-ui/easyclaw/main/install.sh | bash
```

### 或者克隆后运行

```bash
git clone https://github.com/pmliugd-ui/easyclaw.git
cd easyclaw
bash install.sh
```

## 📖 安装流程

脚本会按以下顺序引导你完成安装：

```
步骤 1/7  🔍 检查系统环境 (OS、架构、磁盘、网络)
步骤 2/7  📦 安装系统依赖 (curl, git, jq 等)
步骤 3/7  🟢 安装/检查 Node.js ≥ 22
步骤 4/7  🪞 配置 npm 镜像源 (可选淘宝镜像)
步骤 5/7  🦞 安装 OpenClaw
步骤 6/7  🤖 选择 AI 模型提供商 & 配置 API Key
步骤 7/7  🧙 运行 OpenClaw 初始化向导 & 验证
```

## 🤖 支持的 AI 提供商

| 提供商 | 说明 | 获取 Key |
|--------|------|----------|
| **Anthropic Claude** ⭐ | 综合推荐，效果最佳 | [console.anthropic.com](https://console.anthropic.com/settings/keys) |
| **OpenRouter** ⭐ | 一个 Key 用所有模型，新手友好 | [openrouter.ai](https://openrouter.ai/keys) |
| **Groq** ⭐ | 有免费额度，速度极快 | [console.groq.com](https://console.groq.com/keys) |
| **OpenAI** | GPT-4o / GPT-5 系列 | [platform.openai.com](https://platform.openai.com/api-keys) |
| **Ollama** | 本地运行，完全离线 | [ollama.com](https://ollama.com) |
| **自定义/国内** | DeepSeek / 硅基流动 / Kimi 等 | 各平台官网 |

## ⚙️ 命令行参数

```bash
# 交互式安装 (推荐新手)
bash install.sh

# 非交互式 + 指定 Anthropic
bash install.sh --provider anthropic --api-key sk-ant-xxx

# 仅安装，不运行 onboard 向导
bash install.sh --skip-onboard

# 显示帮助
bash install.sh --help
```

| 参数 | 说明 |
|------|------|
| `--non-interactive, -n` | 非交互模式 |
| `--skip-onboard` | 跳过初始化向导 |
| `--provider <name>` | 指定提供商 |
| `--api-key <key>` | 指定 API Key |
| `--help, -h` | 显示帮助 |

## 🛠️ 安装后常用命令

```bash
# 打开 Web 控制台
openclaw dashboard

# 查看运行状态
openclaw status

# 健康诊断
openclaw doctor

# 重新配置
openclaw configure

# 添加消息通道
openclaw channel add telegram
openclaw channel add whatsapp
openclaw channel add discord
openclaw channel add wechat
openclaw channel add feishu
```

## 🔧 常见问题

### Q: `openclaw` 命令找不到？

打开一个**新终端**，或手动加载 PATH：

```bash
export PATH="$(npm prefix -g)/bin:$PATH"
```

### Q: npm 下载很慢/超时？

使用淘宝镜像源：

```bash
npm config set registry https://registry.npmmirror.com
```

### Q: Node.js 版本不对？

OpenClaw 需要 Node.js ≥ 22：

```bash
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 22
fnm use 22
```

### Q: sharp 模块编译失败？

```bash
SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
```

### Q: Windows 怎么装？

请先安装 WSL2，然后在 WSL2 里运行：

```bash
wsl --install -d Ubuntu
# 在 Ubuntu 终端中
bash install.sh
```

### Q: 如何手动配置 API Key？

编辑 `~/.openclaw/openclaw.json`：

```json
{
  "models": {
    "providers": {
      "anthropic": {
        "apiKey": "sk-ant-你的key"
      }
    },
    "defaults": {
      "provider": "anthropic",
      "model": "claude-sonnet-4-20250514"
    }
  }
}
```

## 📁 项目结构

```
easyclaw/
├── install.sh          # 主安装脚本
├── README.md           # 本文件
└── LICENSE             # MIT 许可证
```

## 🤝 贡献

欢迎提交 Issue 和 PR！

## 📄 许可证

MIT License
