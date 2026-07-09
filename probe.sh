#!/usr/bin/env bash
# ============================================================
# Codex + DeepSeek + ccx 环境探测脚本（只读、无害、不含任何 key）
# 用途：在公司 Mac 上跑一遍，把输出贴回给 COO，据此定一键安装脚本
# 安全：不要求输入任何密码/key；config.toml 里的 sk- 串自动脱敏
# ============================================================
set +e

echo "########## A. 系统 ##########"
echo "[芯片 uname -m]   $(uname -m)"
echo "[架构 arch]       $(arch 2>/dev/null)"
echo "[macOS 版本]"; sw_vers 2>/dev/null
echo

echo "########## B. Shell ##########"
echo "[当前 \$SHELL]          $SHELL"
echo "[用户默认 shell]       $(dscl . -read ~/ UserShell 2>/dev/null | awk '{print $2}')"
echo "[~/.zshrc 存在?]       $([ -f ~/.zshrc ] && echo yes || echo no)"
echo "[~/.bash_profile 存在?] $([ -f ~/.bash_profile ] && echo yes || echo no)"
echo

echo "########## C. Codex App ##########"
echo "[/Applications 找 Codex]"; ls -d /Applications/*odex* 2>/dev/null || echo "  (无)"
echo "[Spotlight 搜 Codex.app]"; mdfind -name "Codex.app" 2>/dev/null | head -5
echo "[~/.codex 目录存在?]   $([ -d ~/.codex ] && echo yes || echo no)"
echo "[~/.codex 内容]"; ls -la ~/.codex 2>/dev/null
echo "[现有 config.toml（sk- 已脱敏）]"
if [ -f ~/.codex/config.toml ]; then
  sed -E 's/(sk-)[A-Za-z0-9_-]+/\1***/g' ~/.codex/config.toml
else echo "  (无)"; fi
echo

echo "########## D. 网络白名单实测（状态码，000=不通/超时）##########"
echo "[github.com]            $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://github.com)"
echo "[ccx releases/latest]   $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://github.com/BenedictKing/ccx/releases/latest)"
echo "[raw.githubusercontent]  $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://raw.githubusercontent.com/BenedictKing/ccx/main/README.md)"
echo "[api.deepseek.com]      $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://api.deepseek.com)"
echo "[git ls-remote ccx]"; git ls-remote https://github.com/BenedictKing/ccx HEAD 2>&1 | head -2
echo "[端口 3000 占用?]"; lsof -i :3000 2>/dev/null || echo "  (空闲)"
echo

echo "########## E. 已有工具 ##########"
for t in brew node npm git curl wget xattr launchctl tar; do
  p=$(command -v $t 2>/dev/null); echo "$t: ${p:-未安装}"
done
[ -n "$(command -v node)" ] && echo "node 版本: $(node -v 2>/dev/null)"
[ -n "$(command -v git)" ]  && echo "git 版本: $(git --version 2>/dev/null)"
echo

echo "########## F. LaunchAgents（自启方案用）##########"
echo "[~/Library/LaunchAgents 存在?] $([ -d ~/Library/LaunchAgents ] && echo yes || echo no)"
ls ~/Library/LaunchAgents 2>/dev/null
echo

echo "########## 探测完成 —— 把以上全部输出贴回给 COO ##########"
