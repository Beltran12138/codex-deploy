# codex-deploy —— Codex + DeepSeek 公司 Mac 一键安装

把 OpenAI **Codex 桌面 App** 接到 **DeepSeek** 模型（不走 OpenAI 计费），中间用 [ccx](https://github.com/BenedictKing/ccx) 做协议翻译（Codex 只会 Responses、DeepSeek 只会 Chat，ccx 在中间转）。

## 一行安装（公司 Mac）

打开「终端」，粘贴回车：

```bash
git clone https://github.com/Beltran12138/codex-deploy.git && cd codex-deploy && bash install.sh
```

脚本自动完成：下载 ccx（含 sha256 校验）→ 去隔离 → 写配置 → 设开机自启 → 注入密码。
中途只问你**一个**东西：ccx 本地密码（自编一串）。

> **为什么 `git clone` 不是 `curl | bash`**：公司网络 `raw.githubusercontent.com` 不通，但 `github.com` / `git` 正常（实测）。

## 安装后两步（约 1 分钟，必做）

install.sh 跑完会提示。**这两步不做 Codex 用不了**：

**① 网页填 DeepSeek key**：浏览器开 `http://localhost:3000`（access key 填你刚设的本地密码）→ 添加渠道，只需填两样：
- 上游地址：`https://api.deepseek.com`
- API Key：你的 DeepSeek key（`sk-...`）

（服务类型先随便选，下一步脚本会改对。）

**② 跑修正脚本**：

```bash
bash fix-channel.sh
```

它自动把渠道配成 Codex 能用的正确格式（**三关**：服务类型/模型映射/角色映射），重启 ccx 并自测。看到 `✅ 链路打通` 即通过。

**③ 测 Codex**：打开 Codex App（**不要登录 OpenAI 账号**），发一句话。

> ⚠️ **别跳过 fix-channel.sh**。手动配渠道几乎必踩三关报错（见下排错表），且其中一关 Web UI 根本没开关。

## 三关：为什么必须跑 fix-channel.sh

Codex → ccx → DeepSeek 链路有三个配置坑，ccx 默认值 + Web UI 都防不住，手动配几乎必踩（2026-07-09 实测）：

| 关 | 症状 | 根因 | fix-channel.sh 自动修 |
|---|---|---|---|
| **1 服务类型** | DeepSeek 返回 404 → ccx 熔断报 503 | `serviceType=responses`（ccx 透传到 `/v1/responses`，DeepSeek 无此端点） | `serviceType→openai`（ccx 转 `/v1/chat/completions`） |
| **2 模型映射** | `model not found` | Codex 发 `gpt-5.4-mini`（占约 1/3 流量），DeepSeek 只认 v4 系列 | `gpt-5.4-mini→deepseek-v4-flash` |
| **3 角色映射** | `unknown variant developer` | Codex 发 `developer` role（Responses 特有），DeepSeek 不认 | `normalizeNonstandardChatRoles=true`（developer→system） |

fix-channel.sh 用 ccx REST API（`PUT /api/responses/channels/{id}`）+ config.json 改这三关，**只动非密字段，不碰 DeepSeek key**。幂等，可重复跑。

## 排错

| 报错 | 原因 | 修法 |
|---|---|---|
| `404` / `All upstream channels unavailable` (503) | 关1：serviceType 错 | 跑 `bash fix-channel.sh` |
| `model not found` / `gpt-5.4-mini` 报错 | 关2：缺模型映射 | 跑 `bash fix-channel.sh` |
| `unknown variant developer, expected system/user/...` | 关3：角色未标准化 | 跑 `bash fix-channel.sh` |
| Codex 登录后失效 | Codex bug #24457 | 用本地 provider 时**不登录** OpenAI 账号 |
| `ccx 没响应` / health 不通 | ccx 没跑 | `launchctl load ~/Library/LaunchAgents/com.local.ccx.plist` |

日志：`tail -50 ~/tools/ccx/ccx.log`

## 前提

- 已装 Codex App（`/Applications/Codex.app`），打开过一次
- 有 DeepSeek API Key（问 IT/主管，或 platform.deepseek.com 自注册）

> **关于 Codex 与 ChatGPT 合并**（2026-07）：OpenAI 把独立 Codex **应用**并入 ChatGPT，但 **Codex CLI（开源 github.com/openai/codex）保留**，自定义 provider 机制仍在。本方案当前可用（Desktop App 实测通过）；若未来 Desktop App 被强转纯 ChatGPT，切到 Codex CLI（`~/.codex/config.toml` 同一套，后端 ccx+DeepSeek 不变）。

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

- DeepSeek key 只在 `http://localhost:3000` 网页填给 ccx，**不进安装脚本、不进 fix-channel.sh、不进日志**。
- `~/tools/ccx/.env` 和两个 plist 含本地密码明文（权限 600），**勿共享/提交**。
- 仓库本身不含任何 key。

## 文件

- `install.sh` —— 主安装（ccx 下载/校验/自启 + Codex config）
- `fix-channel.sh` —— 三关自动修正（安装后跑一次）
- `probe.sh` —— 只读环境探测（装机前自检）
