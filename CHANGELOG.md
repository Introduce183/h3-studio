# 更新日志

> 每次有实质改动都会：递增 `VERSION` → 在本文顶部加一节 → 打同名 git tag（`v1.3.0` 等）→ 推送。
>
> **怎么看自己落后多少**：`powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check`
> **看某版本改了什么**：`git show v1.3.0 --stat`，或看本文件对应小节
> **网页看差异**：`https://github.com/Introduce183/h3-studio/compare/v1.2.0...v1.3.0`

---

## v1.5.0 — 2026-11-23

### 新增

- **停止按钮**（生成按钮旁）：先发 ComfyUI `interrupt`，前端轮询任务状态最多 44 秒；仍不停则**自动强制重启 ComfyUI**（应对显存抖动导致的"一步算不完"）
  - 接口 `POST /api/stop`，参数 `{hard: true}` 直接硬重启
- **隐私作品库**：作品库下方新增，需口令进入（本机独立设置，存 `webui/private.json` 的 sha256）
  - 作品可从主库「🔒 移入隐私」；隐私条目对 `/api/video`、`/api/thumb` 也要求口令
  - 接口：`/api/private/list`、`/api/private/move`、`/api/private/setpw`
- **隐私模式开关**：作品库右上角 🙈，缩略图与结果视频默认模糊，状态存 localStorage
- **自动拼接**：衔接模式跑完自动把上一段拼进来，产物命名 `H3_Chain_01_11.1s-audio.mp4`（链序号 + 总时长）
  - 合并版进作品库并分配编号，本段自动从作品库隐藏
  - 合并版可「看本段」切换；映射存 `webui/joined.json`
  - 实测：8.0s + 3.04s = 11.07s，流拷贝无重画
- **单条隐藏**：结果区「隐藏此条」，写入 `webui/hidden.json`
- **进度按相位显示**：采样 `6/8`、画面解码 `120/243`、收尾——不再出现"6/8 步忽然退回准备模型"
- **中断语义**：`interrupted` 状态（⏸），记录真实执行时间 `actual`，墙钟时间冻结

### 修复

- ComfyUI 重启时 worker 静默死掉 → 任务永远 `running`（现在会重试）
- `/api/stop` 之前会阻塞 8 秒并误报 `stopped=false`
- 参考视频下拉溢出卡片

### 文档

- **新增 [`docs/本机适配指南.md`](docs/本机适配指南.md)** —— 按显存分档的配置表、参考视频真实代价（实测）、"部署后必须自己测的三件事"
- README 与 `给DSH的提示词.md` 顶部都加了「按本机情况调整」的警告

### 实测数据（8 GB 笔记本，供参考，勿照搬）

| 配置 | 结果 |
|---|---|
| 5 秒 / 1 图 / 8 步 | 158 s |
| 5 秒 / 1 图 / 4 步 + pruned LoRA | 98 s |
| 5 秒 / 1 图 + 3 秒参考视频 / 4 步 | 311 s |
| 5 秒 / 5 图 + 5 秒参考视频 / 4 步 | **显存抖动，单步 20 分钟未完成** |
| 15 秒 / 5 图 + 15 秒参考视频 / 8 步 | **OOM**（`MiniMaxH3ReferenceToVideo`） |
| 15 秒 / 3 图 / 8 步（无视频参考） | **显存抖动，GPU 仅 40W** |

> 影响文件：`webui/app.py`、`webui/static/index.html`、`docs/本机适配指南.md`(新)、`README.md`、`给DSH的提示词.md`、`tunnel.ps1`(新)、`start-all.ps1`、`.gitignore`、`VERSION`

---

## v1.4.0 — 2026-11-23

### 新增

- **三档画质**（WebUI 顶部选择，也可 `quality: fast|fine|ultra`）
  | 档位 | 配置 | 3 秒片实测 |
  |---|---|---|
  | 快速 | pruned 蒸馏 LoRA（`minimax_h3_dmd_ref2va_8step_turbo_pruned`）+ **4 步** | 98 s |
  | 精细 | **无 LoRA** + 8 步 | 157.6 s |
  | 极精细 | 无 LoRA + 20 步 | 约 1.85×（按 4/8 步实测拟合） |

  依据：同 8 步下 LoRA 是**负优化**（无 LoRA 157.6 s vs 挂 LoRA 188.9/190.1 s，且画质更软）；但**降到 4 步必须有 pruned 适配 LoRA**——基模 4 步只有 79.9 s 但画面崩坏。非剪枝 LoRA（lightx2v 系列）在剪枝基模上无效，HF 文件卡也写明 AdaLN 适配器已被移除。

- **参考图上限 7 → 9**（模型 `ref_images` autogrow 上限就是 9，之前是我们模板只接了 7 个槽）
- **参考视频**：新增 `VHS_LoadVideoPath`（节点 `50`）→ `ref_videos.ref_video_0` + `ref_video_audios.ref_video_audio_0`
  - 限制：**2–15 秒 / 24fps**，超过只取前 15 秒；**不决定成片时长**（成片仍由时长滑块控制）
  - 提示词用 `<Video 1>` 指代，音频用 `<Audio 1>`
  - 代价：视频参考的帧会参与每一步注意力，实测 3 秒片从 113 s 涨到 **310.9 s**
- **新模式「视频改人物」**：参考视频定动作/运镜，参考图定人物，生成"同一动作换个人演"
- **三段式提示词**：① 参考说明（按上传的图片/视频数量**自动生成**，可手动改并支持恢复自动）② 动作精细描写 ③ 镜头描写
- **17 条运镜预设**：按 H3 官方三段式「方向 + 幅度/速度 + 落点」写成完整英文句，例如
  `The camera pushes in with small amplitude at slow speed toward the character's face, coming to rest at a close-up.`
- 接口：`POST /api/upload_video`（上传参考视频，原样存进 ComfyUI input）；`GET /api/outputs` 新增 `abs`（绝对路径，供 VHS 直接读）
- 本机耗时校准：每完成一条就记一次真实执行时间到 `calib.json`（本机文件，**不入库**）

### 修复

- 参考视频下拉超出卡片宽度（`#refVideo` 是卡片直接子元素，`select{flex:1}` 不生效）
- 送进 `/api/generate` 的 `estimated` 在没有校准样本时返回 `null`（前端只显示倍率，避免暴露某台机器的绝对耗时）

### 升级动作

```powershell
cd <项目目录>
powershell -ExecutionPolicy Bypass -File .\sync.ps1      # 拉代码 + 同步模板
# 模板有变化，务必在 DSH 里重载插件：
#   plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=false
#   plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=true
```

需要"快速"档的话，确认 `models/loras/` 里有 `minimax_h3_dmd_ref2va_8step_turbo_pruned.safetensors`（2.13 GB，
`https://hf-mirror.com/drbaph/MiniMax-H3-Turbo-Lora-ComfyUI/resolve/main/experimental/minimax_h3_dmd_ref2va_8step_turbo_pruned.safetensors`）；
缺了也能用，只是"快速"档会退回 8 步无 LoRA 的效果。

> 影响文件：`webui/app.py`、`webui/static/index.html`、`workflows/*`（3 套模板 + schema）、`README.md`、`给DSH的提示词.md`、`.gitignore`、`VERSION`

---
## v1.3.2 — 2026-11-23

### 修改

- **WebUI 模板目录三级兜底**：`config.json` 的 `workflowsDir` → `%USERPROFILE%\.dsh-comfyui-workbench\workflows`（DSH 插件目录）→ **仓库自带的 `workflows/`**
  - 以前如果插件目录不存在或没同步模板，生成会直接抛 `FileNotFoundError`
  - 现在只要仓库在，即使没装 DSH 插件也能跑

### 升级动作

```powershell
cd <项目目录>
powershell -ExecutionPolicy Bypass -File .\sync.ps1
```

> 影响文件：`webui/app.py`、`CHANGELOG.md`、`VERSION`

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
