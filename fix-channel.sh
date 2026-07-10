#!/usr/bin/env bash
# ============================================================
# fix-channel.sh —— 把 ccx 的 DeepSeek 渠道修成 Codex 能用的正确格式
# 用途：install.sh 跑完 + 你在网页填好 DeepSeek key 后，跑这一个脚本，
#       自动修正三关（服务类型 / 模型映射 / 角色映射），防 Codex 报错。
# 幂等：可重复跑。只动非密字段，不碰你的 DeepSeek key。
# 依赖：curl + python3（macOS 自带）
# 安全：本地密码用变量引用不打印；渠道列表（可能含 key）绝不回显原文。
# 版本：v0.1（2026-07-09，待 Mac 实测迭代）
# ============================================================
set -uo pipefail

CCX_DIR="${HOME}/tools/ccx"
CFG="${CCX_DIR}/config.json"
BASE="http://localhost:3000"
G='\033[32m'; Y='\033[33m'; R='\033[31m'; N='\033[0m'
ok(){ printf "${G}✓${N} %s\n" "$1"; }
info(){ printf "  %s\n" "$1"; }
warn(){ printf "${Y}!${N} %s\n" "$1"; }
die(){ printf "${R}✗ %s${N}\n" "$1" >&2; exit 1; }

# 期望的最终配置（三关全含）
WANT='{"serviceType":"openai","modelMapping":{"gpt-5.4-mini":"deepseek-v4-flash","deepseek-v4-pro":"deepseek-v4-pro"},"supportedModels":["deepseek-v4-pro","deepseek-v4-flash","gpt-5.4-mini"],"normalizeNonstandardChatRoles":true}'

echo "=========================================="
echo "  修正 ccx DeepSeek 渠道（三关）"
echo "=========================================="
command -v curl    >/dev/null || die "缺 curl"
command -v python3 >/dev/null || die "缺 python3，找 IT"
[ -f "${CCX_DIR}/.env" ] || die "找不到 ${CCX_DIR}/.env，先跑 install.sh"

# 本地密码（变量引用，全程不打印）
KEY="$(grep '^PROXY_ACCESS_KEY=' "${CCX_DIR}/.env" | cut -d= -f2-)"
[ -n "${KEY}" ] || die "读不到 PROXY_ACCESS_KEY，查 ${CCX_DIR}/.env"
curl -fsS "${BASE}/health" >/dev/null 2>&1 || die "ccx 没响应 ${BASE}，先跑 install.sh"
ok "ccx 在线"

# 取字段的小工具：从渠道列表 JSON 提取一个字段（不回显原文，防 key 泄露）
getfield() {  # $1=字段名
  curl -s "${BASE}/api/responses/channels" -H "Authorization: Bearer ${KEY}" \
    | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except: print('PARSE_ERR'); sys.exit(0)
a = d if isinstance(d,list) else (d.get('channels') or d.get('data') or [])
if not a: print('NO_CHANNEL'); sys.exit(0)
print(a[0].get('$1','?'))
"
}

# ---- 1. 取首个渠道 id ----
echo "【1/5】读取 Responses 入口渠道..."
CID="$(getfield id)"
case "${CID}" in
  PARSE_ERR) die "ccx 渠道列表非合法 JSON。手动检查（输出可能含 key，勿外传）：
    curl -s ${BASE}/api/responses/channels -H \"Authorization: Bearer \$KEY\" | python3 -m json.tool" ;;
  NO_CHANNEL) die "Responses 入口下还没有渠道。先在 ${BASE} 网页加一个：
    上游地址 https://api.deepseek.com + 你的 DeepSeek key，保存后再跑本脚本" ;;
esac
info "首个渠道 id=${CID}"

# ---- 2. PUT 三关字段（serviceType + modelMapping + normalize）----
echo "【2/5】PUT 修正（serviceType / modelMapping / normalize）..."
PUTR="$(curl -s -X PUT "${BASE}/api/responses/channels/${CID}" \
  -H "Content-Type: application/json" -H "Authorization: Bearer ${KEY}" -d "${WANT}")"
info "PUT 返回：$(printf '%s' "${PUTR}" | head -c 160)"

# ---- 3. 验证 serviceType；API 没改成 openai 就 fallback 改 config.json ----
echo "【3/5】验证 serviceType..."
NOW="$(getfield serviceType)"
info "当前 serviceType=${NOW}"
if [ "${NOW}" != "openai" ]; then
  warn "API 没改动 serviceType，fallback 改 config.json"
  [ -f "${CFG}" ] || die "找不到 ${CFG}。把目录结构贴回：ls -la ${CCX_DIR}/"
  cp "${CFG}" "${CFG}.bak.$(date +%Y%m%d%H%M%S)"
  python3 - "${CFG}" <<'PYEOF' || die "改 config.json 失败"
import json, sys
p = sys.argv[1]
d = json.load(open(p))
arr = d.get('responsesUpstream') or d.get('ResponsesUpstream') or []
if not arr:
    sys.exit('config.json 无 responsesUpstream 数组')
arr[0]['serviceType'] = 'openai'
arr[0]['modelMapping'] = {'gpt-5.4-mini': 'deepseek-v4-flash', 'deepseek-v4-pro': 'deepseek-v4-pro'}
arr[0]['supportedModels'] = ['deepseek-v4-pro', 'deepseek-v4-flash', 'gpt-5.4-mini']
arr[0]['normalizeNonstandardChatRoles'] = True
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print('config.json 已改')
PYEOF
  ok "config.json serviceType→openai（重启生效）"
fi

# ---- 4. 重启 ccx（清运行态 + 让 config.json 生效 + 触发熔断探针）----
echo "【4/5】重启 ccx..."
launchctl kickstart -k "gui/$(id -u)/com.local.ccx" 2>/dev/null && ok "kickstart 成功" \
  || warn "kickstart 失败，手动执行：
    launchctl unload ~/Library/LaunchAgents/com.local.ccx.plist
    launchctl load   ~/Library/LaunchAgents/com.local.ccx.plist"
sleep 3
READY=0
for i in $(seq 1 12); do
  curl -fsS "${BASE}/health" >/dev/null 2>&1 && { READY=1; break; }
  sleep 1
done
[ "${READY}" = 1 ] && ok "ccx 就绪" || warn "ccx 12s 未就绪，查 ${CCX_DIR}/ccx.log"

# ---- 5. 自测（含 developer role，专门测关3）----
echo "【5/5】自测（含 developer role）..."
TEST="$(curl -s -w '\nHTTP %{http_code}' "${BASE}/v1/responses" \
  -H "Content-Type: application/json" -H "Authorization: Bearer ${KEY}" \
  -d '{"model":"deepseek-v4-pro","input":[{"type":"message","role":"developer","content":"be brief"},{"type":"message","role":"user","content":"say hi"}]}')"
CODE="$(printf '%s' "${TEST}" | grep -oE 'HTTP [0-9]+' | tail -1 | awk '{print $2}')"
printf '%s\n' "${TEST}" | sed 's/^/    /'
if [ "${CODE}" = "200" ]; then
  ok "✅ 链路打通！打开 Codex App（不登录 OpenAI 账号）发一句话验证"
else
  warn "自测 HTTP=${CODE:-空}。503=熔断未恢复（等 1-2 分钟自动探针后重跑本脚本）；其他=查 tail -50 ${CCX_DIR}/ccx.log"
fi
