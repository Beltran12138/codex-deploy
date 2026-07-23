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
  *) die "不支持的芯片：${ARCH}（仅支持 Apple Silicon / Intel Mac）" ;;
esac
ok "芯片 $ARCH → ccx-darwin-$CCX_ARCH"

# ---- 1. 就位 ccx 二进制 + sha256 校验 + 去隔离 ----
# 公司网出口层封 github.com（命令行连不上），ccx 走 github releases 直连会失败。
# 策略：先试直连（短超时）；连不上 → 找本地已下好的二进制（浏览器走飞连隧道可下，放 ~/Downloads）。
# sha256 硬编码在此（不依赖 github），两条路都校验，防损坏/篡改。
echo "【1/7】就位 ccx ${CCX_VER}（含校验）..."
mkdir -p "$CCX_DIR"
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN_URL="https://github.com/BenedictKing/ccx/releases/download/${CCX_VER}/ccx-darwin-${CCX_ARCH}"
case "$CCX_ARCH" in
  arm64) EXP="7751e70ef45e928a41e6c6eb23b8d9c522d68a92a26bf1f76ebde2a6c85e4a26" ;;
  amd64) EXP="4172b022fd00a816288ee8bc33c2a79b091f2c2711057b19001d1477bb0e97a5" ;;
  *) die "无此架构的 sha256：$CCX_ARCH" ;;
esac
if curl -fsSL -m 12 "$BIN_URL" -o "$CCX_DIR/ccx.tmp" 2>/dev/null; then
  info "已从 github 直连下载"
else
  warn "github 连不上（公司网常见）—— 改用本地已下好的二进制"
  SRC=""
  for CAND in "$HOME/Downloads/ccx-darwin-${CCX_ARCH}" "$HERE/ccx-darwin-${CCX_ARCH}"; do
    [ -f "$CAND" ] && { SRC="$CAND"; break; }
  done
  [ -n "$SRC" ] || die "找不到 ccx 二进制。公司网封 github 命令行下不了 —— 请用${Y}浏览器${N}下载后放到 ~/Downloads 再重跑本脚本：
    ${BIN_URL}
  （浏览器走飞连隧道可下；保持文件名 ccx-darwin-${CCX_ARCH} 不要改）"
  info "使用本地二进制：$SRC"
  cp "$SRC" "$CCX_DIR/ccx.tmp"
fi
ACT="$(shasum -a 256 "$CCX_DIR/ccx.tmp" | awk '{print $1}')"
[ "$EXP" = "$ACT" ] || die "sha256 校验失败！期望 $EXP 实得 $ACT（文件损坏/版本不符），已中止"
mv "$CCX_DIR/ccx.tmp" "$CCX_DIR/ccx"
chmod +x "$CCX_DIR/ccx"
xattr -d com.apple.quarantine "$CCX_DIR/ccx" 2>/dev/null || true
ok "ccx 就位 + sha256 校验通过"

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
# 合并写入（保留 Codex App 自身设置：plugins/mcp_servers/projects 等，只改我们这几个键）
# base_url 指向 :3001 auth-inject shim（下一步部署），因此 **无 env_key** —— GUI App 免环境变量（实证：GUI 读不到 launchctl env）
command -v python3 >/dev/null || die "缺 python3（合并配置 + shim 需要；macOS 装 Xcode CLT 即有：xcode-select --install）"
CODEX_MODEL="$MODEL" python3 - "$CODEX_DIR/config.toml" <<'PYEOF'
import os, re, sys
path = sys.argv[1]
model = os.environ.get("CODEX_MODEL", "glm4.7")
try:
    text = open(path, encoding="utf-8").read()
except FileNotFoundError:
    text = ""
lines = text.split("\n")
hdr = next((i for i, l in enumerate(lines) if l.lstrip().startswith("[")), len(lines))
def set_top(key, val):
    global lines, hdr
    for i in range(hdr):
        if re.match(r"\s*%s\s*=" % re.escape(key), lines[i]):
            lines[i] = "%s = %s" % (key, val); return
    lines.insert(0, "%s = %s" % (key, val)); hdr += 1
set_top("model", '"%s"' % model)
set_top("model_provider", '"ccx_local"')
set_top("wire_api", '"responses"')
text = "\n".join(lines)
text = re.sub(r"\n?\[model_providers\.ccx_local\][^\[]*", "\n", text)   # 移除旧 provider 块
if not text.endswith("\n"): text += "\n"
text += '\n[model_providers.ccx_local]\nname = "CCX local gateway"\nbase_url = "http://localhost:3001/v1"\n'
open(path, "w", encoding="utf-8").write(text)
PYEOF
ok "Codex 配置已合并（模型 ${MODEL}，指向 shim :3001，保留 App 其他设置）"

# ---- 4. 部署 auth-inject shim（:3001）----
# 根因（实证 2026-07-23）：macOS GUI 应用（Codex App）读不到 launchctl setenv 的环境变量，登出重登都不行。
# 解法：Codex → :3001（无认证）→ 本 shim 运行时从 ccx/.env 读 PROXY_ACCESS_KEY 注入 Bearer → ccx :3000。
# 因此 config.toml base_url 指 :3001 且无 env_key，GUI App 彻底免环境变量。DeepSeek 与 BitV 两条路共用。
echo "【4/7】部署 auth-inject shim（:3001，让 Codex App 免环境变量）..."
PY3="$(command -v python3)"
SHIM_PY="$CODEX_DIR/auth-inject-proxy.py"
cat > "$SHIM_PY" <<'PYEOF'
#!/usr/bin/env python3
"""auth-inject shim：接收无认证请求，运行时从 ~/tools/ccx/.env 读 PROXY_ACCESS_KEY 注入 Bearer 后转发到 ccx。"""
import http.server, urllib.request, urllib.error, os, re
CCX_URL = "http://127.0.0.1:3000"
LISTEN = ("127.0.0.1", 3001)
def read_key():
    try:
        for line in open(os.path.expanduser("~/tools/ccx/.env"), encoding="utf-8"):
            m = re.match(r"\s*PROXY_ACCESS_KEY\s*=\s*(.*)", line)
            if m:
                return m.group(1).strip()
    except OSError:
        pass
    return ""
class Proxy(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        self._p("GET")
    def do_POST(self):
        self._p("POST")
    def do_OPTIONS(self):
        self.send_response(200); self.end_headers()
    def _p(self, method):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n) if n > 0 else b""
        req = urllib.request.Request(CCX_URL + self.path, data=body, method=method)
        req.add_header("Authorization", "Bearer " + read_key())
        req.add_header("Content-Type", self.headers.get("Content-Type", "application/json"))
        try:
            r = urllib.request.urlopen(req, timeout=180)
            self.send_response(r.status)
            for k, v in r.getheaders():
                if k.lower() not in ("transfer-encoding", "connection"):
                    self.send_header(k, v)
            self.end_headers(); self.wfile.write(r.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code); self.end_headers(); self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502); self.end_headers(); self.wfile.write(str(e).encode())
if __name__ == "__main__":
    print("auth-inject on :%d -> %s" % (LISTEN[1], CCX_URL))
    http.server.HTTPServer(LISTEN, Proxy).serve_forever()
PYEOF
SHIM_PLIST="$LA_DIR/com.local.ccx-auth-inject.plist"
cat > "$SHIM_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.ccx-auth-inject</string>
  <key>ProgramArguments</key>
  <array><string>$PY3</string><string>$SHIM_PY</string></array>
  <key>WorkingDirectory</key><string>$CODEX_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$CODEX_DIR/auth-inject.log</string>
  <key>StandardErrorPath</key><string>$CODEX_DIR/auth-inject.log</string>
</dict></plist>
EOF
# 清理旧的环境变量方案（不再用）
launchctl unload "$ENV_PLIST" 2>/dev/null || true
rm -f "$ENV_PLIST"
launchctl unload "$SHIM_PLIST" 2>/dev/null || true
launchctl load "$SHIM_PLIST" || die "shim launchd 加载失败"
ok "auth-inject shim 已部署并自启（:3001）"

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
[ "$READY" = 1 ] && ok "ccx 就绪（http://localhost:${CCX_PORT}）" || warn "ccx 15s 未响应，查日志：$CCX_LOG"

# shim 就绪（:3001/health → 经 shim 打到 ccx /health）
SHIM_READY=0
for i in $(seq 1 10); do
  if curl -fsS -m 3 "http://localhost:3001/health" >/dev/null 2>&1; then SHIM_READY=1; break; fi
  sleep 1
done
[ "$SHIM_READY" = 1 ] && ok "auth-inject shim 就绪（:3001）" || warn "shim 10s 未响应，查日志：$CODEX_DIR/auth-inject.log"

# ---- 7. 唯一手动步：网页配 DeepSeek 渠道 ----
echo "【7/7】最后一步（手动，~30 秒）：在 ccx 网页接入 DeepSeek"
cat <<EOF

${G}========================================================${N}
 最后一步（手动填 key + 跑一个脚本，约 1 分钟）：
 1. 浏览器打开： http://localhost:${CCX_PORT}
 2. 若要 access key，填你刚设的本地密码
 3. 点「添加渠道 / Add Channel」，只需填两样：
      上游地址 : https://api.deepseek.com
      API Key  : 你的 DeepSeek key（sk-...）
    （服务类型先随便选，下一步脚本会自动改对）
    保存。
 4. 回终端，跑：
      bash fix-channel.sh
    自动修正三关（服务类型/模型映射/角色映射），防 Codex 报错，
    并重启 ccx + 自测。看到 ${G}✅${N} 即通过。
 5. 打开 Codex App（${Y}不要登录 OpenAI 账号${N}），
    发一句「用 Python 写个加法函数」测试。
${G}========================================================${N}

完成。以后开机自动可用。日志：${CCX_LOG}
EOF

# __FETCH_OK__
