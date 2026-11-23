# H3 Studio · MiniMax-H3 图生视频 WebUI

> ## ⚠️ 部署前必读：[`docs/本机适配指南.md`](docs/本机适配指南.md)
>
> **这套参数是 8 GB 显存笔记本的实测结果，不是标准答案。** 换机器必须按显存/内存重新选配置：
> - 8 GB → 单次只跑 **5 秒**；15 秒会显存抖动卡死；**参考视频请 ≤3 秒或干脆不用**
> - 12–16 GB → 10 秒稳，参考视频 ≤5 秒
> - 24 GB+ → 15 秒 + 完整参考视频
>
> 里面有按显存分档的配置表、参考视频的真实代价（实测数据）、以及"部署后必须自己测的三件事"。
> **不要照抄本文档里任何秒数**——那些是特定机器上的数字。


> ## 🤖 如果你是 AI agent（DSH / Claude / Codex 等），按这个顺序读
>
> 1. **先读根目录的 [`给DSH的提示词.md`](给DSH的提示词.md)** —— 这是写给你的执行指令：装模板、重载插件、起 WebUI、跑 4 条验收、按格式汇报。**照着做就行，不用猜。**
> 2. 要准备环境（下模型、装 VideoHelperSuite）时读 [`docs/部署提示词.md`](docs/部署提示词.md) —— 模型文件名、字节数、SHA256、按显存档位调整的表都在里面。**光看 README 不会知道要下哪 5 个文件。**
> 3. 装模板或 WebUI 的具体步骤读 [`docs/部署说明.md`](docs/部署说明.md)。
> 4. 出片参数不对/很慢/报错时查 [docs/调优笔记.md](docs/调优笔记.md)。
> 5. 要手机/公网访问（DSH 用 dshgo、WebUI 用隧道）看 [docs/远程访问.md](docs/远程访问.md)。
>
> **一键同步（已部署过的机器）**：`powershell -ExecutionPolicy Bypass -File .\sync.ps1`
>
> ⚠️ 三个最容易漏的点：
> - 工作流模板要复制到 `%USERPROFILE%\.dsh-comfyui-workbench\workflows\`，**不是**放在仓库里就生效
> - 复制完**必须重载插件**（`plugin_manager` 里 `set_bundle` 关→开各一次），否则 `comfyui_run` 会误报缺节点
> - 模板里写死了 5 个模型文件名，**名字不一致就提交失败**，清单在 `docs/部署提示词.md` 第 2 步

本机 ComfyUI 上的 MiniMax-H3（ref2va）图生视频方案的配套工具：一个傻瓜化 WebUI + 三套调好的 DSH 工作流模板 + 部署文档。

## 这是什么

- **webui/** —— 本地 WebUI。拖参考图、写提示词、选时长/模式，直接出片；支持「接着上一段继续」（末帧锚定）
- **workflows/** —— 3 套 ComfyUI 工作流模板（DSH `dsh-comfyui-workbench` 插件格式：API 图 + 变量声明 + 备注）
- **docs/** —— 部署 runbook（模型清单 + SHA256 + 依赖节点 + 踩坑）、安装说明、调优笔记（实测数据）

## 工作流模板

| 模板 | 用途 | 耗时（8 GB 显存实测） |
|---|---|---|
| `minimax-h3-ref2v-community` | 单图参考，最快 | 3 秒片约 3 分钟（冷启 5 分钟） |
| `minimax-h3-ref2v-community-multi` | 7 图参考，保身份 | 3 秒片约 8–10 分钟 |
| `minimax-h3-ref2v-continue` | 续接：把上一段末帧锚在第 0 帧 | 同上 |

关键参数：8 步、`euler`/`simple`、768×1024、LoRA 强度 1.0、`comfy kitchen attention` 注意力后端、VHS `crf 12`。

## 快速开始

1. 把 `workflows/*` 复制到 `%USERPROFILE%\.dsh-comfyui-workbench\workflows\`
2. 重载插件（`plugin_manager` 里 `set_bundle` 关→开各一次），否则预检会误报缺节点
3. `comfyui_workflow` 能看到 3 个模板、`missingNodes` 为空 = 装好
4. 进 `webui/`，双击 `启动.bat`，打开 <http://127.0.0.1:8190>

环境（模型、自定义节点）按 [`docs/部署提示词.md`](docs/部署提示词.md) 准备。

## 时长与帧数

H3 只认 `17k+5` 网格，模型训练区间 **124–362 帧（5–15 秒）**：

| 输入秒数 | 帧数 | 实际时长 |
|---|---|---|
| 3 | 73 | 3.04 s |
| 5 | 124 | 5.17 s |
| 15 | 362 | 15.08 s |

低于 5 秒能跑但质量明显下降。

## 构图决定脸

实测（YOLO 人脸检测量脸框）：

| 提示词 | 脸框 | 观感 |
|---|---|---|
| `full body shot, head to toe` | 92–100 px | 放大后糊 |
| `close-up portrait, head and shoulders` | 333–364 px | 五官清晰 |

要看清脸就写近景，要全身就别指望脸。

## WebUI 接口

| 接口 | 说明 |
|---|---|
| `POST /api/upload` | 多图上传到 ComfyUI input 目录 |
| `POST /api/generate` | `{prompt, duration, images[], mode: single\|continue, anchor}` |
| `GET /api/job/{id}` | 进度 / 耗时 / 产物 |
| `GET /api/outputs` | 作品库列表（去重、带稳定编号 `no`） |
| `GET /api/video?no=N` / `?rel=...` | 按编号或路径取视频（支持 Range） |
| `GET /api/thumb?no=N` | 缩略图（取 1/3 处帧，磁盘缓存） |

## 已验证不可用的方案

- **Sol-Attn**（sm_120 稀疏注意力）：第一次 `torch.compile` 直接把 ComfyUI 进程打崩，已弃用
- **SageAttention**：sm_120 上是负优化（比 kitchen 慢 1.27×、误差 2.4×）
- **H3-FaceRefine**：官方示例依赖 `MiniMaxH3NativeAudioLock`（不在包内），装上也跑不通

## 许可

自用项目，无授权。用到的模型与节点遵循各自上游许可。

## 多台机器同步

仓库只放**代码 + 模板 + 文档**；运行产物（`outputs/`、`jobs.json`、`library.json`、`thumbs/`）和个人配置（`config.json`）都在 `.gitignore` 里，不会互相覆盖。

### 第一次（另一台机器）

```powershell
gh auth login                                    # 私有仓库需要先认证
git clone https://github.com/Introduce183/h3-studio.git <项目目录>
cd <项目目录>
# 首次还要装环境：见 docs/部署提示词.md（模型、VideoHelperSuite）
powershell -ExecutionPolicy Bypass -File .\sync.ps1   # 同步模板 + 起 WebUI
```

### 以后更新

```powershell
cd <项目目录>
git pull          # 或者一步到位：
powershell -ExecutionPolicy Bypass -File .\sync.ps1
```

`sync.ps1` 会：拉最新代码 → 把 `workflows/*` 同步到 DSH 插件目录（按哈希判断，没变不覆盖）→ 重启 WebUI → 健康检查 → 打印作品库状态。模板有变化时会提醒你去 DSH 里重载插件。

### 注意

- **仓库目录 = 部署目录**：直接从 clone 出来的目录跑 `webui/app.py`，`git pull` 才等于更新。别把仓库克隆到 A 处、再从 B 处跑旧副本。
- **工作流模板不在仓库运行路径里**：它们要复制到 `%USERPROFILE%\.dsh-comfyui-workbench\workflows\`，`sync.ps1` 负责这步；手动的话 `git pull` 不会自动生效。
- **模板变了要重载插件**：`plugin_manager` 里 `set_bundle` 关→开各一次，否则 `comfyui_run` 预检会误报缺节点。
- **私有仓库要先认证**：`gh auth login`（推荐）或配置 PAT；没认证 `git clone` 会 404。

## 怎么判断有没有更新

三种方式，从快到慢：

```powershell
# 1. 只看有没有更新（不动任何文件）
powershell -ExecutionPolicy Bypass -File .\sync.ps1 -Check
#   输出示例：
#   本地版本: v1.1.0 (8551206)
#   ⬆ 落后远端 2 个提交（远端 v1.2.0 / 9a1b2c3）
#      最新提交: feat: xxx
#      待更新文件:
#        - webui/app.py

# 2. 纯 git
git fetch; git log --oneline HEAD..origin/main

# 3. 看 GitHub 页面
#    https://github.com/Introduce183/h3-studio/commits/main
```

**版本号**在仓库根目录的 `VERSION` 文件里，每次有实质更新会递增并打 git tag（`v1.1.0`、`v1.2.0`…），`sync.ps1` 也会把本地/远端版本号打出来。

> 注意：`git pull` 只更新仓库里的文件；`workflows/` 还要复制到 DSH 插件目录才生效，`sync.ps1` 会做这步并按文件哈希报告"更新了几个模板"。

## 路径约定（重要）

仓库里**没有写死任何一台机器的绝对路径**。文档里出现的占位符和脚本的探测逻辑如下：

| 占位符 | 指什么 | 谁来确定 |
|---|---|---|
| `<项目目录>` | 你 clone 下来的仓库目录 | **你自己**（`sync.ps1` 用脚本所在目录，无需填） |
| `<ComfyUI 安装目录>` | ComfyUI 的安装根（含 `main.py`） | 你的 ComfyUI Desktop 安装位置 |
| `<ComfyUI 的 venv python>` | ComfyUI 自带的 python | `启动.bat` / `sync.ps1` 会自动找：`H3_PYTHON` → Desktop 自带 venv → `C:\ComfyUI\...` → PATH |
| `<models 目录>` / `<ComfyUI input 目录>` / `<ComfyUI output 目录>` | 模型与输入输出目录 | `webui/app.py` **自动从 ComfyUI `/system_stats` 的 `argv` 里读 `--input-directory` / `--output-directory`**；读不到就用 `<ComfyUI 安装目录>\input|output` |
| `%USERPROFILE%\.dsh-comfyui-workbench\workflows` | DSH 插件的模板目录 | 脚本自动用当前用户目录，不用填 |

想显式指定就拷 `webui/config.example.json` → `config.json` 填 `inputDir` / `outputDir` / `workflowsDir`；`config.json` 在 `.gitignore` 里，不会同步到别的机器。

**判断探测对不对**：`curl http://127.0.0.1:8190/api/outputs`，`items` 非空说明输出目录找对了；为空就是没探测到，去填 `config.json`。

## 一键启动（重启电脑后只需一步）

```powershell
powershell -ExecutionPolicy Bypass -File .\make-shortcut.ps1   # 首次：建桌面快捷方式
```

之后**双击桌面的「H3 Studio」**即可：自动启动 ComfyUI（带模型路径）→ 等就绪 → 启动 WebUI → 打开浏览器。

命令行用法：

```powershell
.\start-all.ps1              # 启动（已在跑的会自动跳过）
.\start-all.ps1 -Init        # 重新探测路径并写入 startup.json
.\start-all.ps1 -Restart     # 强制重启两个服务
.\start-all.ps1 -NoBrowser   # 不自动开浏览器
```

`start-all.ps1` 自动探测 ComfyUI 的 `main.py`、venv python、`--extra-model-paths-config` 的 yaml、以及 `ComfyUI-Shared\input|output`，结果缓存到 `startup.json`（每台机器独立，不进仓库）。启动后还会自检**模型可见性**——如果 ComfyUI 起来了但看不到模型，会警告"模型路径没生效"，避免跑了半天才发现。

> 找不到 ComfyUI？设环境变量 `COMFYUI_MAIN` 指向 `main.py` 再跑 `-Init`。

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。当前 `VERSION` 会随每次改动递增并打 tag。

## 画质三档（WebUI 顶部切换，也可 `quality: fast|fine|ultra`）

| 档位 | 配置 | 3 秒片实测 | 适用 |
|---|---|---|---|
| 快速 | pruned 蒸馏 LoRA + **4 步** | 98 s | 试创意、调提示词 |
| 精细 | **无 LoRA** + 8 步 | 157.6 s | 默认出片 |
| 极精细 | 无 LoRA + 20 步 | ≈1.85× | 最终成片、复杂镜头 |

**为什么这样配**（同 8 步实测）：无 LoRA 157.6 s / pruned LoRA 188.9 s / 非剪枝 LoRA 190.1 s —— 同步数下挂 LoRA 是负优化；但降到 4 步时基模直接崩（79.9 s 但画面废），必须用 **pruned 适配**的蒸馏 LoRA。非剪枝 LoRA 在剪枝基模上无效（HF 文件卡：AdaLN 适配器已被移除）。

## 参考图与参考视频

| 类型 | 上限 | 说明 |
|---|---|---|
| 参考图 `ref_images` | **9 张** | 提示词用 `<Picture 1>`…`<Picture 9>` |
| 参考视频 `ref_videos` | 1 段（2–15 秒 / 24fps） | 提示词用 `<Video 1>`，原声作 `<Audio 1>` |
| 参考音频 `ref_audios` | 3 条 | 本 WebUI 未接线 |

**时长规则**：参考视频**不决定**成片时长（成片由「时长」滑块决定，5–15 秒）；想让动作演完整，参考视频与成片时长尽量接近。参考视频会把帧喂进每一步注意力，实测 3 秒片从 113 s 涨到 **310.9 s**。

## 三种生成模式

| 模式 | 干什么 | 用到的节点 |
|---|---|---|
| 单段生成 | 参考图 + 提示词直接出 | — |
| 衔接上一段 | 把上段**末帧**钉在新段第 0 帧 | `47` LoadImage + `48` MiniMaxH3AddGuide |
| 视频改人物 | 参考视频定动作运镜，参考图定人物 | `50` VHS_LoadVideoPath → `ref_videos` |

## 三段式提示词

① 参考说明（**随图片/视频数量自动生成**，可手改，`恢复自动说明` 按钮可还原）
② 动作精细描写（每段最多 2 个动作、动作要量化、写承接、情绪外化）
③ 镜头描写（17 条官方三段式预设：**方向 + 幅度/速度 + 落点**）

> H3 只认三段式运镜句。`camera moves left` 出来是静止的；`The camera pans left with large amplitude at slow speed, revealing the window behind her.` 才动得起来。
