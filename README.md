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

## 已装的 DSH 插件（profile: desktop）

billion-context、modlens、dsh-vision-router、dsh-our-free-model、hindsight、OpenViking、
WeKnora、treg、dsh-web-all、dsh-ssh、dsh-im、dsh-pocket、wallpaper-engine、whale-widget、dshmarket。

其中 treg / WeKnora / Hindsight / OpenViking / dsh-im 需要各自的凭据或服务端才能实际工作。
