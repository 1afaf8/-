# 饭碗工作室 · 工作面规则

这份文件是我（DSH agent）在这个工作区里的常驻操作约定，开工前先读一遍。

## 1. 豆包工作的免费额度要主动用掉

这台机器上装着「豆包工作」桌面端（窗口标题形如 `xxx - 豆包`，进程名 `Doubao`），**每天有免费额度，用不完就浪费**。

- 原则：能外包给豆包的粗活，不要自己烧上下文。典型适合外派的工作：
  - 长文档 / 网页 / 资料的搜集、摘要、对比
  - 写初稿类工作：文案、说明、README、报告骨架
  - 报错初筛、日志归类、方案备选清单
  - 需要长时间在 GUI 里点来点去的流程（她能在本机跑 PowerShell）
- 不外包：涉及密钥、涉及删数据的高风险执行、需要读本仓库精确上下文的活。
- 流程：我先拆清任务与验收标准 → 用键鼠把需求发给她 → 读回结果 → **验收后才采用**（她不保证正确，拿回来当"初稿/线索"，不是结论）。
- 交互方式（本机没有豆包 API）：
  1. 截图窗口区域：`Graphics.CopyFromScreen`
  2. 读屏：`powershell -NoProfile -ExecutionPolicy Bypass -File bin\ocr.ps1 -Path <png>`
  3. 输入：`Set-Clipboard` + `SendKeys ^v` + `{ENTER}`；窗口找 `Chrome_WidgetWin_1` 且 Name 以 ` - 豆包` 结尾
- 单次任务耗时通常 2～10 分钟，用后台 job 轮询，别干等。
- **她的产物直接落盘**：`C:\Users\ASUS\Doubao\chats\<日期>\<会话>\`（例如
  `C:\Users\ASUS\Doubao\chats\2026-11-23\new-chat\clean-caches.ps1`）。让她"写成文件"比让她"贴在聊天里"更好，
  之后直接从磁盘读，不用截图 OCR。

## 2. 收尾一律走 push.ps1

写完代码用 `.\push.ps1 -Message "..."` 提交并推送，不要手敲三条 git 命令。
远端：`git@github.com:1afaf8/-.git`（仓库名就是一个减号，用户明确不改）。

## 3. 这台机器的硬约束

- 只有 Windows PowerShell 5.1，没有 pwsh/PS7：脚本禁用 `?:`、`??`、`-Parallel`。
- 含中文的 `.ps1` 必须 UTF-8 **with BOM**；`~/.ssh/config` 必须 **无 BOM**。
- 执行策略限制：跑脚本加 `-ExecutionPolicy Bypass`。
- `github.com` 的 git smart-http 直连不通，走 SSH（`ssh.github.com:443`）。
- 本机 skills 装在 `C:\Users\ASUS\.dsh\skills`，DSH 自动发现，新增即热加载。

## 4. 交付习惯

- 声称"做完了"之前，必须有可复现的证据（命令输出、API 返回、截图、文件内容）。
- 报数字要带来源；不确定就说不确定，不用漂亮话填空。
- 用户不喜欢被反复征询：能自己判断的直接做，做完汇报。
