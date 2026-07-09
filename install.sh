#!/usr/bin/env bash
# ============================================================
# Codex + DeepSeek + ccx 一键安装（公司 Mac）
# 用法： bash install.sh    （幂等，可重复运行）
# 不依赖 brew/wget；只用 curl+git+shasum+xattr+launchctl
# ============================================================
set -uo pipefail

# ---- 配置（一般不用改）----
CCX_VER="v2.7.0"
CCX_DIR="$HOME/tools/ccx"
CCX_PORT="3000"
MODEL="${CODEX_DS_MODEL:-deepseek-v4-pro}"   # 省钱: export CODEX_DS_MODEL=deepseek-v4-flash
CODEX_DIR="$HOME/.codex"
LA_DIR="$HOME/Library/LaunchAgents"
CCX_PLIST="$LA_DIR/com.local.ccx.plist"
ENV_PLIST="$LA_DIR/com.local.ccx-env.plist"
CCX_LOG="$CCX_DIR/ccx.log"

G='\033[32m'; Y='\033[33m'; R='\033[31m'; N='\033[0m'
ok(){ printf "${G}✓${N} %s\n" "$1"; }
info(){ printf "  %s\n" "$1"; }
warn(){ printf "${Y}!${N} %s\n" "$1"; }
die(){ printf "${R}✗ %s${N}\n" "$1" >&2; exit 1; }

echo "=========================================="
echo "  Codex + DeepSeek 一键安装"
echo "=========================================="

# ---- 0. 前置检查 ----
echo "【0/7】检查环境..."
command -v curl   >/dev/null || die "缺少 curl，找 IT"
command -v git    >/dev/null || die "缺少 git，找 IT"
command -v shasum >/dev/null || die "缺少 shasum，找 IT"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64)  CCX_ARCH=arm64 ;;
  x86_64) CCX_ARCH=amd64 ;;
  *) die "不支持的芯片：$ARCH（仅支持 Apple Silicon / Intel Mac）" ;;
esac
ok "芯片 $ARCH → ccx-darwin-$CCX_ARCH"

# ---- 1. 下载 ccx + sha256 校验 + 去隔离 ----
echo "【1/7】下载 ccx $CCX_VER（含校验）..."
mkdir -p "$CCX_DIR"
BIN_URL="https://github.com/BenedictKing/ccx/releases/download/$CCX_VER/ccx-darwin-$CCX_ARCH"
SHA_URL="https://github.com/BenedictKing/ccx/releases/download/$CCX_VER/ccx-darwin-$CCX_ARCH.sha256"
curl -fsSL "$BIN_URL" -o "$CCX_DIR/ccx.tmp" || die "下载失败，检查能否打开：$BIN_URL"
curl -fsSL "$SHA_URL" -o "$CCX_DIR/ccx.sha256" || die "校验文件下载失败"
EXP="$(awk '{print $1}' "$CCX_DIR/ccx.sha256")"
ACT="$(shasum -a 256 "$CCX_DIR/ccx.tmp" | awk '{print $1}')"
[ "$EXP" = "$ACT" ] || die "sha256 校验失败！文件可能损坏/被篡改，已中止"
mv "$CCX_DIR/ccx.tmp" "$CCX_DIR/ccx"
chmod +x "$CCX_DIR/ccx"
xattr -d com.apple.quarantine "$CCX_DIR/ccx" 2>/dev/null || true
ok "ccx 下载 + 校验通过"

# ---- 2. 设本地密码 + 写 .env ----
echo "【2/7】设置 ccx 本地密码（ccx 的本地钥匙，${Y}不是${N} DeepSeek key）"
warn "密码请只用字母/数字，勿含 < > & \" 等字符"
while true; do
  printf "  请自编一串本地密码（输入不显示）: "; read -rs CCX_PWD; echo
  [ -n "$CCX_PWD" ] && break || warn "不能为空"
done
cat > "$CCX_DIR/.env" <<EOF
PROXY_ACCESS_KEY=$CCX_PWD
PORT=$CCX_PORT
ENABLE_WEB_UI=true
APP_UI_LANGUAGE=zh
EOF
chmod 600 "$CCX_DIR/.env"
ok "ccx 配置写入（$CCX_DIR/.env，权限 600）"

# ---- 3. Codex config.toml（备份后覆盖）----
echo "【3/7】配置 Codex..."
mkdir -p "$CODEX_DIR"
if [ -f "$CODEX_DIR/config.toml" ]; then
  cp "$CODEX_DIR/config.toml" "$CODEX_DIR/config.toml.bak.$(date +%Y%m%d%H%M%S)"
  info "已备份原 config.toml"
fi
cat > "$CODEX_DIR/config.toml" <<EOF
model = "$MODEL"
model_provider = "ccx_local"
wire_api = "responses"

[model_providers.ccx_local]
name = "CCX local gateway"
base_url = "http://localhost:$CCX_PORT/v1"
env_key = "CCX_ACCESS_KEY"
EOF
ok "Codex 配置写入（模型 $MODEL）"

# ---- 4. 注入 CCX_ACCESS_KEY（GUI App 可读 + 开机持久）----
echo "【4/7】注入本地密码到系统环境（让 Codex App 读到）..."
launchctl setenv CCX_ACCESS_KEY "$CCX_PWD" || die "launchctl setenv 失败"
cat > "$ENV_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.ccx-env</string>
  <key>ProgramArguments</key>
  <array>
    <string>sh</string><string>-c</string><string>launchctl setenv CCX_ACCESS_KEY $CCX_PWD</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
launchctl unload "$ENV_PLIST" 2>/dev/null || true
launchctl load "$ENV_PLIST" 2>/dev/null || true
ok "已注入 + 开机自动（重启后 Codex 仍能用）"

# ---- 5. ccx 开机自启 + 立即启动 ----
echo "【5/7】配置 ccx 开机自启..."
cat > "$CCX_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.ccx</string>
  <key>ProgramArguments</key>
  <array><string>$CCX_DIR/ccx</string></array>
  <key>WorkingDirectory</key><string>$CCX_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$CCX_LOG</string>
  <key>StandardErrorPath</key><string>$CCX_LOG</string>
</dict></plist>
EOF
launchctl unload "$CCX_PLIST" 2>/dev/null || true
launchctl load "$CCX_PLIST"
ok "ccx 已开机自启并运行"

# ---- 6. 等 ccx 就绪 ----
echo "【6/7】等待 ccx 就绪..."
READY=0
for i in $(seq 1 15); do
  if curl -fsS "http://localhost:$CCX_PORT/health" >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done
[ "$READY" = 1 ] && ok "ccx 就绪（http://localhost:$CCX_PORT）" || warn "ccx 15s 未响应，查日志：$CCX_LOG"

# ---- 7. 唯一手动步：网页配 DeepSeek 渠道 ----
echo "【7/7】最后一步（手动，~30 秒）：在 ccx 网页接入 DeepSeek"
cat <<EOF

${G}========================================================${N}
 1. 浏览器打开： http://localhost:$CCX_PORT
 2. 若要 access key，填你刚设的本地密码
 3. 点「添加渠道 / Add Channel」，按下面填：
      服务类型 : DeepSeek（或 OpenAI Chat 兼容）
      上游地址 : https://api.deepseek.com
      API Key  : 你的 DeepSeek key（sk-...）
      模型映射 : 映射到 $MODEL
    保存。
 4. 打开 Codex App（${Y}不要登录 OpenAI 账号${N}），
    发一句「用 Python 写个加法函数」测试。
${G}========================================================${N}

完成。以后开机自动可用。日志：$CCX_LOG
EOF
