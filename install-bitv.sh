#!/usr/bin/env bash
# ============================================================
# Codex + BitV 一键安装（公司 Mac）
# 路径：Codex App → ccx(:3000 responses 入口) → proxy(:8423) → BitV 网关
# 与 install.sh（DeepSeek）并列：ccx 主体共用，差异只在渠道（走 fix-channel-bitv.sh）
# 用法： bash install-bitv.sh   （幂等）
# 前置：Codex App 已装（飞连）+ curl/git + BitV key
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_DIR="$HOME/chat-path-rewrite-proxy"
PROXY_RAW="https://raw.githubusercontent.com/Beltran12138/chat-path-rewrite-proxy/main"
SELF_RAW="https://raw.githubusercontent.com/Beltran12138/codex-deploy/main"
PROXY_PORT=8423

G='\033[32m'; Y='\033[33m'; R='\033[31m'; N='\033[0m'
ok(){ printf "${G}✓${N} %s\n" "$1"; }
info(){ printf "  %s\n" "$1"; }
warn(){ printf "${Y}!${N} %s\n" "$1"; }
die(){ printf "${R}✗ %s${N}\n" "$1" >&2; exit 1; }

echo "=========================================="
echo "  Codex + BitV 一键安装"
echo "=========================================="

command -v curl >/dev/null || die "缺 curl"
command -v git  >/dev/null || die "缺 git"
[ -d "/Applications/Codex.app" ] || warn "未检测到 /Applications/Codex.app —— 先在飞连载 Codex App 并打开一次"

# ---- 自举：本脚本可能是单独 curl 下来的（公司网封 github，不能 git clone 整仓）----
# 缺的兄弟脚本用 raw 补齐（raw.githubusercontent 未被封）
for f in install.sh fix-channel-bitv.sh; do
  curl -fsSL "$SELF_RAW/$f" -o "$SCRIPT_DIR/$f" || die "拉取 $f 失败（raw 连通？）"
done
info "兄弟脚本已就位（raw 最新版）"

# ---- 1. 拉 proxy（BitV 必需，DeepSeek 不需要）----
echo "【1/3】确保 proxy 在跑（:${PROXY_PORT}）..."
if curl -fsS -m 3 "http://localhost:${PROXY_PORT}/v1/models" >/dev/null 2>&1; then
  ok "proxy 已在线（跳过）"
else
  warn "proxy 未跑，开始装（会让你粘 BitV key）..."
  # 每次强制重拉覆盖（防复用昨天残留的旧/损坏文件——曾致 install-proxy.sh 跑错版本）
  mkdir -p "$PROXY_DIR"
  for f in install-proxy.sh proxy.js package.json; do
    curl -fsSL "$PROXY_RAW/$f" -o "$PROXY_DIR/$f" || die "拉取 proxy/$f 失败（raw 连通？）"
  done
  info "proxy 文件已就位（raw 最新版，已覆盖旧文件）"
  bash "$PROXY_DIR/install-proxy.sh" || die "proxy 安装失败"
  ok "proxy 已装并自启"
fi

# ---- 2. 装 ccx（复用 install.sh；中途编本地密码）----
# config.toml 的 model 写 glm4.7（与 BitV 渠道一致；最终 proxy 也会兜底重写）
echo "【2/3】装 ccx（Codex 基础设施，与 DeepSeek 版共用）..."
info "中途会让你自编一串本地密码（ccx 钥匙，不是 BitV key）"
CODEX_DS_MODEL=glm4.7 bash "$SCRIPT_DIR/install.sh" || die "ccx 安装失败（见上方 install.sh 输出）"
ok "ccx 已装"

# ---- 3. BitV 渠道提示（覆盖 install.sh 末尾的 DeepSeek 渠道提示）----
echo "【3/3】下一步：建 BitV 渠道"
cat <<EOF

${G}========================================================${N}
 ccx 已装好。${Y}忽略${N}上方 install.sh 末尾的「DeepSeek 渠道」提示
 —— BitV 不走网页填 DeepSeek 那步，直接跑：

   bash fix-channel-bitv.sh

 它自动在 ccx 建 BitV 渠道（POST /api/responses/channels，
 serviceType=openai，上游 localhost:8423）+ 自测。
 看到${G} ✅ 链路打通 ${N}后，打开 Codex App（${Y}不要登录 OpenAI${N}）发一句话验证。
${G}========================================================${N}
EOF
