#!/usr/bin/env bash
# ============================================================
# fix-channel-bitv.sh —— 在 ccx responses 入口建 BitV 渠道（Codex 用）
# POST /api/responses/channels，body 三关直接写对（serviceType=openai / modelMapping 空 /
#   normalizeNonstandardChatRoles=true）；proxy 强制重写 model→glm4.7
# 前提：install-bitv.sh 已跑（ccx :3000 + proxy :8423 在线）
# 幂等：若已有 bitv 渠道会重建。本地密码变量引用不打印。
# 实证：ccx responses/messages 双入口独立（Qoder 2026-07-20）；Codex 走 responses
# ============================================================
set -uo pipefail

CCX_DIR="${HOME}/tools/ccx"
BASE="http://localhost:3000"
ENV_FILE="${CCX_DIR}/.env"
CHANNEL_NAME="bitv"

G='\033[32m'; Y='\033[33m'; R='\033[31m'; N='\033[0m'
ok(){ printf "${G}✓${N} %s\n" "$1"; }
info(){ printf "  %s\n" "$1"; }
warn(){ printf "${Y}!${N} %s\n" "$1"; }
die(){ printf "${R}✗ %s${N}\n" "$1" >&2; exit 1; }

echo "=========================================="
echo "  建 BitV 渠道（ccx responses 入口，Codex 用）"
echo "=========================================="

command -v curl >/dev/null || die "缺 curl"
command -v python3 >/dev/null || die "缺 python3"
[ -f "$ENV_FILE" ] || die "找不到 $ENV_FILE，先跑 install-bitv.sh"

# ccx 本地密码（变量引用，全程不打印）
KEY="$(grep '^PROXY_ACCESS_KEY=' "$ENV_FILE" | cut -d= -f2-)"
[ -n "$KEY" ] || die "读不到 PROXY_ACCESS_KEY，查 $ENV_FILE"

# ---- 0. 前置：proxy + ccx 在线 ----
echo "【0/4】检查依赖..."
curl -fsS -m 3 "http://localhost:8423/v1/models" >/dev/null 2>&1 \
  || die "proxy :8423 没跑。先装：bash chat-path-rewrite-proxy/install-proxy.sh"
ok "proxy 在线"
curl -fsS "$BASE/health" >/dev/null 2>&1 || die "ccx 没响应 $BASE，先跑 install-bitv.sh"
ok "ccx 在线"

# ---- 1. 删除已有同名 bitv 渠道（幂等：避免重复）----
echo "【1/4】清理旧 bitv 渠道（若有）..."
# 列 responses 渠道，找 name=bitv 的 index 删除
EXIST_IDX="$(curl -s "$BASE/api/responses/channels" -H "Authorization: Bearer $KEY" \
  | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except: sys.exit(0)
a = d if isinstance(d,list) else (d.get('channels') or d.get('data') or [])
for ch in a:
    if ch.get('name')=='$CHANNEL_NAME':
        print(ch.get('index', ch.get('id',''))); break
" 2>/dev/null)"
if [ -n "$EXIST_IDX" ]; then
  curl -s -X DELETE "$BASE/api/responses/channels/${EXIST_IDX}" -H "Authorization: Bearer $KEY" >/dev/null 2>&1 \
    && info "已删旧 bitv 渠道(index=$EXIST_IDX)" || info "删旧渠道跳过（继续）"
else
  info "无旧 bitv 渠道"
fi

# ---- 2. POST 建 BitV 渠道（三关全含）----
echo "【2/4】POST 建 BitV 渠道..."
BODY='{"name":"'"$CHANNEL_NAME"'","serviceType":"openai","baseUrl":"http://localhost:8423","apiKeys":["dummy-proxy-injects-real-key"],"modelMapping":{},"supportedModels":["glm4.7"],"normalizeNonstandardChatRoles":true,"reasoningMapping":{},"reasoningParamStyle":"reasoning"}'
RES="$(curl -s -X POST "$BASE/api/responses/channels" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" -d "$BODY")"
info "POST 返回：$(printf '%s' "$RES" | head -c 200)"
echo "$RES" | grep -qiE '添加|added|success|200' && ok "BitV 渠道已建" \
  || warn "POST 返回异常（可能字段要求不同，把返回贴回）"

# ---- 3. 重启 ccx（让新渠道进调度 + 触发探针）----
echo "【3/4】重启 ccx..."
launchctl kickstart -k "gui/$(id -u)/com.local.ccx" 2>/dev/null && ok "kickstart 成功" \
  || warn "kickstart 失败，手动：launchctl unload/load ~/Library/LaunchAgents/com.local.ccx.plist"
sleep 5
READY=0
for i in $(seq 1 12); do
  curl -fsS "$BASE/health" >/dev/null 2>&1 && { READY=1; break; }
  sleep 1
done
[ "$READY" = 1 ] && ok "ccx 就绪" || warn "ccx 12s 未就绪，查 $CCX_DIR/ccx.log"

# ---- 4. 自测（模拟 Codex 走 responses 入口）----
echo "【4/4】自测（Codex 协议：/v1/responses）..."
TEST="$(curl -s -w '\nHTTP %{http_code}' --max-time 45 "$BASE/v1/responses" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $KEY" \
  -d '{"model":"glm4.7","input":[{"type":"message","role":"user","content":"say hi"}]}')"
CODE="$(printf '%s' "$TEST" | grep -oE 'HTTP [0-9]+' | tail -1 | awk '{print $2}')"
if [ "$CODE" = "200" ]; then
  ok "✅ BitV 链路打通（Codex → ccx → proxy → BitV）"
  echo "   打开 Codex App（${Y}不要登录 OpenAI 账号${N}），发一句话验证。"
  echo "   若 Codex 自称 Claude = 渠道走错（检查 ccx 默认渠道是 bitv 不是 claude 系）"
else
  warn "自测 HTTP=${CODE:-空}"
  info "503=熔断未恢复（等 1-2 分钟自动探针后重跑本脚本）"
  info "其他=查 tail -50 $CCX_DIR/ccx.log"
  info "响应：$(printf '%s' "$TEST" | head -c 200)"
fi
