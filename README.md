# codex-deploy —— Codex + DeepSeek 公司 Mac 一键安装

把 OpenAI **Codex 桌面 App** 接到 **DeepSeek** 模型（不走 OpenAI 计费），中间用 [ccx](https://github.com/BenedictKing/ccx) 做协议翻译（Codex 只会 Responses、DeepSeek 只会 Chat，ccx 在中间转）。

## 一行安装（公司 Mac）

打开「终端」，粘贴回车：

```bash
git clone https://github.com/Beltran12138/codex-deploy.git && cd codex-deploy && bash install.sh
```

脚本自动完成：下载 ccx（含 sha256 校验）→ 去除 Mac 拦截 → 写配置 → 设开机自启 → 注入密码到系统。
中途只问你**一个**东西：ccx 本地密码（自编一串）。

> **为什么是 `git clone` 不是 `curl | bash`**：公司网络 `raw.githubusercontent.com` 不通，但 `github.com` 和 `git` 正常，所以走 clone（实测）。

## 安装时唯一的"手动"步（约 30 秒）

脚本跑完会提示。浏览器开 `http://localhost:3000` → 添加渠道：

| 字段 | 填什么 |
|---|---|
| 服务类型 | DeepSeek（或 OpenAI Chat 兼容）|
| 上游地址 | `https://api.deepseek.com` |
| API Key | 你的 DeepSeek key（`sk-...`）|
| 模型映射 | `deepseek-v4-pro`（省钱用 `deepseek-v4-flash`）|

然后打开 Codex App（**不要登录 OpenAI 账号**），发一句话测试。

> DeepSeek 旧模型名 `deepseek-chat`/`deepseek-reasoner` 将于 **2026-07-24 停用**，本脚本直接用新名。

## 前提

- 已装 Codex App（`/Applications/Codex.app`），并打开过一次
- 有 DeepSeek API Key（问 IT/主管，或 platform.deepseek.com 自注册）

## 换模型

```bash
CODEX_DS_MODEL=deepseek-v4-flash bash install.sh   # 重跑覆盖配置即换 flash
```

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.local.ccx.plist ~/Library/LaunchAgents/com.local.ccx-env.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.local.ccx.plist ~/Library/LaunchAgents/com.local.ccx-env.plist
rm -rf ~/tools/ccx
launchctl unsetenv CCX_ACCESS_KEY
# Codex 配置按需保留或删： rm -f ~/.codex/config.toml
```

## 安全

- DeepSeek key 只在 `http://localhost:3000` 网页填给 ccx，**不进安装脚本、不进日志**。
- `~/tools/ccx/.env` 和两个 plist 含本地密码明文（权限已设 600），**勿共享/提交**。
- 仓库本身不含任何 key。
