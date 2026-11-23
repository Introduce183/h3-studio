# 更新日志

> 每次有实质改动都会：递增 `VERSION` → 在本文顶部加一节 → 打同名 git tag（`v1.3.0` 等）→ 推送。
>
> **怎么看自己落后多少**：`powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check`
> **看某版本改了什么**：`git show v1.3.0 --stat`，或看本文件对应小节
> **网页看差异**：`https://github.com/Introduce183/h3-studio/compare/v1.2.0...v1.3.0`

---

## v1.3.1 — 2026-11-23

### 新增

- **`push.ps1`** —— 推送脚本：自动探测本机代理端口（7897/7890/7891/1080/10809/2080）、验证能否通 GitHub、带 3 次重试；支持 `-Message` 顺带提交、`-Proxy <端口>` 指定、`-NoProxy` 强制直连

### 背景

`github.com` 直连在部分网络下会被 reset（`Recv failure: Connection was reset`），而 `api.github.com` 又是通的，很容易误判。有了这个脚本，推送前会先确认代理是否真的可用。

### 升级动作

```powershell
cd <项目目录>
git pull
# 之后推送用：
powershell -ExecutionPolicy Bypass -File .\push.ps1 -Message "你的改动说明"
```

> 影响文件：`push.ps1`(新)、`CHANGELOG.md`、`VERSION`

---
## v1.3.0 — 2026-11-23

### 新增

- **`start-all.ps1`** —— 一键启动 ComfyUI + WebUI
  - 自动探测 ComfyUI 的 `main.py`、venv python、`--extra-model-paths-config` 的 yaml、`ComfyUI-Shared\input|output`
  - 探测结果缓存到 `startup.json`（已在 `.gitignore`，每台机器各自一份）
  - 已运行的服务自动跳过；`-Restart` 强制重启；`-NoBrowser` 不开浏览器
  - **启动后自检模型可见性**：如果 ComfyUI 起来了但 `UNETLoader` 是 0 个，会明确警告"模型路径没生效"（避免踩到"裸实例"坑）
- **`make-shortcut.ps1`** —— 在桌面创建「H3 Studio」快捷方式（最小化窗口启动，不弹黑框）
- **`CHANGELOG.md`** —— 本文件

### 修改

- `README.md`：新增「一键启动」章节
- `VERSION`：`1.2.0` → `1.3.0`

### 升级动作

```powershell
cd <项目目录>
powershell -ExecutionPolicy Bypass -File .\sync.ps1     # 拉代码 + 同步模板
powershell -ExecutionPolicy Bypass -File .\start-all.ps1 -Init   # 探测本机路径（只需一次）
powershell -ExecutionPolicy Bypass -File .\make-shortcut.ps1     # 建桌面快捷方式
```

> 影响文件：`start-all.ps1`(新)、`make-shortcut.ps1`(新)、`CHANGELOG.md`(新)、`README.md`、`VERSION`

---

## v1.2.0 — 2026-11-22

### 修改

- **去掉所有机器相关的绝对路径**，改成占位符 + 自动探测（8 个文件、18 处）
  - `<ComfyUI 的 venv python>`、`<ComfyUI 安装目录>`、`<models 目录>`、`<ComfyUI input 目录>`、`<ComfyUI output 目录>`、`<项目目录>`
  - `C:\Users\<用户名>\...` 统一为 `%USERPROFILE%\...`
  - Desktop 的 `instance-model-paths\inst-1795322058155.yaml` 改为 `<Desktop 数据目录>\instance-model-paths\<实例id>.yaml`
- `README.md`：新增「路径约定」章节（说明每个占位符由谁来确定、怎么判断探测对不对）

### 为什么

原来的文档只能在我这台机器上照抄；换台机器路径全错。现在 `webui/app.py` 启动时读 ComfyUI `/system_stats` 的 `argv` 自动拿 `--input-directory` / `--output-directory`，`sync.ps1` / `启动.bat` 用脚本自身目录。

> 影响文件：`README.md`、`给DSH的提示词.md`、`docs/部署说明.md`、`docs/调优笔记.md`、`docs/更新说明-v2.md`、`webui/README.md`、`webui/启动.bat`、`VERSION`

---

## v1.1.0 — 2026-11-22

### 新增

- **`VERSION` 文件**（当前值即版本号）
- **`sync.ps1 -Check`** —— 只看有没有更新，不动任何文件；输出「本地版本 / 落后几个提交 / 远端版本 / 待更新文件列表」
- `sync.ps1` 正常运行时也会先 `git fetch` 报差异，并打印本次改动的文件清单
- `README.md`：新增「怎么判断有没有更新」章节

### 修改

- `sync.ps1`：模板同步改为**按文件哈希**逐文件判断（没变不覆盖），并只在真有变化时提示重载插件

> 影响文件：`sync.ps1`、`VERSION`(新)、`README.md`

---

## v1.0.0 — 2026-11-22

首个版本。

### 内容

- `webui/` —— 本地 WebUI（aiohttp 单文件后端 + 单页前端）
  - 参考图上传（最多 7 张）、提示词、时长 1–15 秒、单段/续接两种模式
  - 进度走 ComfyUI WebSocket，显示采样步数 + 耗时
  - **作品库**：缩略图网格、稳定编号 `#N`、按编号跳转、点播/下载/一键续接
  - 产物去重（`X.mp4` 与 `X-audio.mp4` 只保留带音轨的）、过滤无效视频
  - 任务记录落盘 `jobs.json`，重启后自动续跟；前端 404 时自动重连正在跑的任务
  - 路径自动探测，可用 `config.json` 覆盖
- `workflows/` —— 3 套工作流模板（API 图 + schema + meta）
  - `minimax-h3-ref2v-community`（单图参考）
  - `minimax-h3-ref2v-community-multi`（7 图参考）
  - `minimax-h3-ref2v-continue`（`MiniMaxH3AddGuide` 把上段末帧锚在第 0 帧）
- `docs/` —— 部署提示词（模型清单 + SHA256 + 依赖节点 + 踩坑）、部署说明、调优笔记
- `给DSH的提示词.md` —— 可直接贴给另一个 AI agent 的部署指令
- `sync.ps1` —— 拉代码 + 同步模板 + 重启 WebUI

### 关键参数（都写死在模板里）

8 步 · `euler`/`simple` · 768×1024 · LoRA 强度 1.0 · `comfy kitchen attention` · VHS `crf 12` · 时长吸附 `17k+5` 网格（3 秒=73 帧、5 秒=124 帧、15 秒=362 帧）
