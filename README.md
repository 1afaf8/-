# 饭碗工作室

本机（ASUS / LAPTOP-JT2DPF1I）的工作区，跑在 DeepSeek Harness 桌面端上。

## 环境备忘

- 默认 shell 是 **Windows PowerShell 5.1**（没有 pwsh/PS7）。写脚本别用 `?:`、`??`、`-Parallel` 这些 PS7 语法；文件若含中文，必须存成 **UTF-8 with BOM**，否则 5.1 按 ANSI 解码会把路径读成乱码（踩过一次，在 D:\ 建出乱码目录）。
- PATH 里没有 `pnpm`、`gh`；`git` 在 `C:\Program Files\Git\cmd\git.exe`。
- 网络：`github.com:443` 的 git smart-http 被阻断（页面能开、`/info/refs` 超时），但 `api.github.com`、`raw.githubusercontent.com`、`codeload.github.com` 正常，速度约 0.5 MB/s。
- 全局 git 配置用 `ghproxy.net` 做 `insteadOf` 镜像（原来的 `gh-proxy.com` 已关停，旧配置备份在 `~/.gitconfig.bak-20261122`）。
- SSH 走 `ssh.github.com:443`；公钥 `~/.ssh/id_ed25519.pub` 已登记到 GitHub（账号 `1afaf8`）。
  `~/.ssh/config` 必须是**无 BOM** 的 ASCII：PS 5.1 的 `Set-Content -Encoding utf8` 会加 BOM，
  于是 git 自带的 ssh 报 `Bad configuration option: \357\273\277host`（系统 OpenSSH 反而能容忍）。
  写入用 `[System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))`。

## 工具

- `bin/ghget.ps1` — 按 `owner/repo` 拉源码（走 codeload 下载 tarball 再解包，不需要 git 身份）：

  ```powershell
  powershell -NoProfile -File bin\ghget.ps1 -Repo octocat/Hello-World
  powershell -NoProfile -File bin\ghget.ps1 -Repo owner/repo -Ref refs/heads/dev -Out D:\src\repo
  ```

## 提交与推送

`push.ps1`（仓库根目录）一条命令走完 **add → commit → push**：

```powershell
.\push.ps1                          # 交互式，会提示你输入 commit 信息
.\push.ps1 -Message "feat: 登录页"   # 直接带信息，适合脚本/自动化
.\push.ps1 -Message "wip" -NoPush    # 只提交，不推送
```

行为约定：

- 固定操作**脚本所在的仓库**，在哪个目录调用都一样。
- `git add -A`，新增、修改、删除、重命名都会进暂存区。
- 工作区干净时打印黄字 `Nothing to commit` 并返回 0，不算失败。
- commit 信息为空则直接中止，已暂存的内容原样保留。
- 首次推送会自动 `git push -u origin HEAD`，之后直接 `git push`。
- 结束时打印 short sha、分支和推送结果。

约定：**以后写完代码，直接 `.\push.ps1 -Message "..."` 收尾**，不用手敲三条 git 命令。

## 用 Gemini

本机**直连 Google 全部超时**，必须先开 Clash Verge（`C:\Program Files\Clash Verge\clash-verge.exe`，
起来后 `verge-mihomo.exe` 监听 `127.0.0.1:7897`）。2026-11-23 实测出口是香港（183.179.43.252）。

走 7897 之后各通道的实测结果：

| 通道 | 端点 | 结果 |
|---|---|---|
| AI Studio API key | `generativelanguage.googleapis.com` | 通，key 无效时返回 `400 API_KEY_INVALID` |
| Gemini 网页 | `gemini.google.com` | 通，200 |
| Antigravity / Cloud Code Assist | `cloudcode-pa.googleapis.com`、`daily-cloudcode-pa.sandbox.googleapis.com` | 通，无凭据时 `401` |
| Antigravity 主端点 | `daily-cloudcode-pa.googleapis.com` | **不通**（TLS 被重置），走 daily 优先的插件要靠 sandbox 兜底 |
| Vertex AI | `aiplatform.googleapis.com` | 通，但要开通 Vertex AI 并绑计费项目 |
| Gemini 网页 cookie 逆向（gemini-webapi 一类） | — | **不建议**，cookie 会被轮换、违反 ToS |

所以「用上 Gemini」只差凭据，三条路按门槛从低到高：

1. **AI Studio 免费 API key**（只要一个 Google 账号，不要钱）——去 `aistudio.google.com/apikey` 建，
   有免费额度限制。把 key 发我即可接到 DSH。
2. **Google AI Pro 订阅**（走 Antigravity 通道，吃订阅额度）——`dsh-gemini-pool` 这类插件支持浏览器登录，
   但主端点不通时只能靠 sandbox 端点，稳定性打折。
3. **Vertex AI**——要 Google Cloud 项目 + 计费，适合长期、量大。

注意：`aa2246740/dsh-antigravity-oauth` 这类逆向 OAuth 的插件 README 自述**有封号风险**，不要装。
纯本地跑 Gemini（`gemma`）可以用 Ollama，不联网、不要账号，但能力和云端 Gemini 不是一个量级。

## 本地 skills（用户级）

装在 `C:\Users\ASUS\.dsh\skills\`，DSH 自动发现，任何项目都能调用（豆包 2026-11-23 写的一套编码流程技能）：

| skill | 用途 | 什么时候触发 |
|---|---|---|
| `repo-onboarding` | 用最少读取量产出 `.agent/REPO_MAP.md` 代码地图 | 第一次进仓库、在陌生模块改代码 |
| `test-fix-loop` | 测试/CI 变绿的闭环，禁止改断言绕过 | 测试挂了、CI 红、类型检查报错 |
| `bug-triage` | 复现 → 二分 → 根因假设 → 回归用例 | 报错/崩溃，原因未知 |
| `diff-review` | 提交前自审 diff，挡密钥和调试残留 | 准备提交、发 PR、任务收尾 |
| `refactor-migration` | 跨文件机械改造，每步可验证可回滚 | 重命名、改签名、换库、搬迁 |

每个技能是一个文件夹 + `SKILL.md`（frontmatter 的 `description` 决定路由，触发词写在那里）。

## 已装的 DSH 插件（profile: desktop）

billion-context、modlens、dsh-vision-router、dsh-our-free-model、hindsight、OpenViking、
WeKnora、treg、dsh-web-all、dsh-ssh、dsh-im、dsh-pocket、wallpaper-engine、whale-widget、dshmarket。

其中 treg / WeKnora / Hindsight / OpenViking / dsh-im 需要各自的凭据或服务端才能实际工作。
