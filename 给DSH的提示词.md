> ⚠️ **部署前第一件事：读 [`docs/本机适配指南.md`](docs/本机适配指南.md)，按你这台机器的显存重新选配置。**
> 本仓库里所有耗时秒数、能跑多长、能不能用参考视频，都是**8 GB 显存笔记本**的实测结果。
> 你的机器可能是 6 GB / 12 GB / 24 GB，照抄会得到"卡死"或"跑不完"：
> - 显存 8 GB：单次 5 秒，**不要跑 15 秒**，参考视频 ≤3 秒或不用
> - 12–16 GB：单次 10 秒，参考视频 ≤5 秒
> - 24 GB+：单次 15 秒，可用完整参考视频
>
> 判断方法：先跑一条 5 秒（1 图、精细档），再跑同配置 10 秒，若耗时暴涨或卡住，就说明你的显存上限到了。

> **给 DSH agent 的执行指令（当前基线 v1.4.0）**：v1.4.0 起新增三档画质、9 张参考图、参考视频、视频改人物模式与三段式提示词；
> 相关小节见第 6.5 / 6.6 节。落地命令一律用仓库里的 sync.ps1，不要手工拷文件。

> **（仓库版说明）** 本文原先是配 zip 包用的；现在项目在 GitHub 上，包已不需要——直接 git clone 这个仓库即可，workflows/、webui/、docs/、
efs/ 的对应物分别是仓库里的 workflows/、webui/、docs/（参考图未入库，用你自己的）。下面第 1 节的复制命令把 <解压目录> 换成仓库根目录即可。

# 任务：把这套 MiniMax-H3 图生视频方案在本机复刻并验收

我给了你一个压缩包 **`H3完整复刻包.zip`**（10 MB）。里面是另一台机器上**已经跑通并实测过**的完整方案：3 套 ComfyUI 工作流模板、一个 WebUI、7 张参考图、部署文档和实测笔记。

你的任务：把它在本机装好、跑通、验收，最后按第 7 节格式汇报。

包内结构：

```
H3完整复刻包.zip
├─ 给DSH的提示词.md          ← 就是本文件
├─ workflows/                ← 3 套工作流模板（API 图 + 变量声明 + 备注），共 9 个文件
│   ├─ minimax-h3-ref2v-community.json / .schema.json / .meta.json       单图参考
│   ├─ minimax-h3-ref2v-community-multi.json / ...                       7 图参考
│   └─ minimax-h3-ref2v-continue.json / ...                              续接（末帧锚定）
├─ webui/                    ← WebUI 源码：app.py + static/index.html + 启动.bat + config.example.json + README.md
├─ refs/                     ← 7 张参考图 hero_ref_1..7.png
└─ docs/
    ├─ 部署说明.md            ← 模板与 WebUI 的安装细节
    ├─ 部署提示词.md          ← 模型清单 + sha256 + 依赖节点 + 踩坑（要下模型时按这个做）
    └─ 调优笔记.md            ← 实测数据：步数/分辨率/LoRA 对比/注意事项
```

---

## 第 0 步：同步自查（**每次拿到新版本都要做，别跳**）

先跑这一条，它会逐项打 ✓/✗：

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1
```

**11 项必须全 ✓**，重点是这三个最容易漏的：

1. **桌面一键启动快捷方式**：`H3 Studio.lnk` 必须存在且参数指向 `start-all.ps1`
   - 不存在 → `powershell -ExecutionPolicy Bypass -File .\make-shortcut.ps1`
   - 存在但指向别处 → 先删掉再重建
   - 它决定了"双击启动时会不会自动带反向隧道"
2. **`startup.json` 的隧道四件套**：`tunnelHost` / `tunnelUser` / `tunnelRemotePort` / `tunnelKey`
   - 缺了 → 快捷方式能起 ComfyUI 和 WebUI，但**不会起隧道**，手机上打不开
3. **`webui/config.json` 的 token**：公网暴露必须设，否则等于把出片能力公开

**逐项对照本机状态**：打开 [`docs/项目结构.md`](docs/项目结构.md)，
按"一、仓库文件"清单逐个 `Test-Path`；工作流模板要额外比哈希（`verify.ps1` 已包含）。
任何本地缺文件、版本落后、模板不一致，都先修好再往下做，**不要带着不一致的状态验收**。

## 1. 装工作流模板

把包里的 `workflows/*` 复制到 DSH 插件的模板目录：

```powershell
$dst = Join-Path $env:USERPROFILE '.dsh-comfyui-workbench\workflows'
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item '<解压目录>\workflows\*' $dst -Force
Get-ChildItem $dst -Filter 'minimax-h3-*' | Select-Object Name
```

### 装完必须重载插件

插件把 ComfyUI 的 `/object_info` 缓存在进程里**永不刷新**，不重载就会误报缺节点。连续调用两次：

```
plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=false
plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=true
```

### 验证

1. `comfyui_workflow`（不带参数）→ 应列出 3 个模板（`...-community` / `...-community-multi` / `...-continue`）
2. `comfyui_workflow { workflowId: "minimax-h3-ref2v-community-multi" }` →
   - `missingNodes` 必须是 `[]`
   - `models.primary` = `minimax_h3_ref2va_pruned_int8_convrot.safetensors`
   - `inputs` 里能看到 `image1`…`image7`、`prompt`、`duration`
3. `comfyui_workflow { workflowId: "minimax-h3-ref2v-continue" }` → 节点清单里要有 `MiniMaxH3AddGuide` 和两个 `LoadImage`

`missingNodes` 非空 = 缺自定义节点，多半是 `VHS_VideoCombine`（VideoHelperSuite）或 ComfyUI 版本 < 0.33（`AddGuide` 是内置的，老版本没有）。按 `docs/部署提示词.md` 第 3 步补。

---

## 2. 装 WebUI

```powershell
Copy-Item '<解压目录>\webui' '<项目目录>' -Recurse -Force
```

可选固定路径：把 `config.example.json` 复制成 `config.json` 再填

```json
{"comfyUrl":"http://127.0.0.1:8188","port":8190,"inputDir":"","outputDir":"","workflowsDir":""}
```

留空 = 自动探测（`inputDir`/`outputDir` 从 ComfyUI `/system_stats` 的 `argv` 里取 `--input-directory` / `--output-directory`；`workflowsDir` 默认就是上面那个插件目录）。

启动：双击 `启动.bat`，或 `& '<ComfyUI 的 python.exe>' '<项目目录>\app.py'`。
**用 ComfyUI 自带的 venv python**（已含 `aiohttp`/`av`/`Pillow`/`imageio-ffmpeg`）。`启动.bat` 找 Python 的顺序：`H3_PYTHON` 环境变量 → ComfyUI Desktop 自带 venv → PATH 里的 `python`。

验证（用 curl，别只看页面）：

```powershell
curl.exe -s http://127.0.0.1:8190/api/health    # {"comfy":true,"port":8190}
curl.exe -s http://127.0.0.1:8190/api/outputs   # items 非空；空=输出目录没探对
curl.exe -s -o NUL -w "%{http_code}" http://127.0.0.1:8190/   # 200
```

---

## 3. 模型对齐

模板里**写死了模型文件名**，必须一致：

```
diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors
text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
vae/minimax_h3_video_vae_int8_convrot.safetensors
vae/minimax_h3_audio_vae_fp32.safetensors
loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors
```

缺就照 `docs/部署提示词.md` 第 2 步下（ModelScope 源，带字节数 + SHA256，还有按显存调整的档位表：8 GB 照抄 / 12–16 GB 可换 fp8 或 fp16 VAE / 内存 ≤16 GB 必须加 `--disable-pinned-memory`）。

本机模型名不同的话，**不要改文件名**，改模板 JSON 里对应节点的 `inputs`（如节点 `1` 的 `unet_name`），改完再重载一次插件。

---

## 4. 验收（4 条，必须实跑）

| # | 内容 | 期望 |
|---|---|---|
| 1 | 单图 · 3 秒 | 73 帧、768×1024、带音轨、**约 3 分钟** |
| 2 | 7 图 · 3 秒 | 73 帧、约 8–10 分钟 |
| 3 | 续接 · 3 秒 | 拿第 1 条视频末帧当锚点，**新片首帧应与上段末帧几乎一致** |
| 4 | 码率 | `crf 12` 时 5 秒片应 ≥4 MB；只有 1.5 MB 说明 crf 没生效 |

`comfyui_run` 示例（单图）：

```json
{ "workflow": {"id": "minimax-h3-ref2v-community"},
  "vars": { "image": "<ComfyUI input 目录里的图名>", "duration": 3,
            "prompt": "参考 <Picture 1> 的角色：外貌、服装以参考图为准。\n[Shot 1] 固定镜头，close-up portrait，head and shoulders。\n0.0-1.5 秒：双手举到脸旁做猫爪。\n1.5-3.0 秒：双手在胸前比爱心。" } }
```

续接：`workflow.id` 换成 `minimax-h3-ref2v-continue`，vars 加 `"last_frame": "<末帧 png 文件名>"`、`"frame_idx": 0`。

**计时用 ComfyUI `/history` 的 `execution_start → execution_success`，不要用插件的 `elapsedMs`**（那是从提交时刻算的，含排队）。

---

## 5. 已知坑

| 现象 | 原因 | 处理 |
|---|---|---|
| `missingNodes` 报缺 `VHS_VideoCombine` | 没装 VideoHelperSuite | 装包、重启 ComfyUI、重载插件 |
| 报缺节点但 `/object_info` 里有 | 插件缓存 | 两次 `set_bundle`（false→true） |
| 一直 running，30 分钟后变 `unknown` | 插件工具等待上限 30 分钟 | `comfyui_run { promptId: "..." }` 续查，产物会补收 |
| 出片 1.5 MB / 码率 2000 kbps | VHS 的 `crf` 没传进去 | 模板里 `VHS_VideoCombine.inputs` 必须有 `"crf": 12`（不在 /object_info 里，但扁平字段有效） |
| h264 编码失败 `EINVAL` | 宽高是奇数 | 分辨率用 32 的倍数（模板 `ResolutionSelector.multiple = 32`） |
| 连续跑几条后极慢 | 8 GB 显存碎片化 | 重启 ComfyUI；内存 ≤16 GB 加 `--disable-pinned-memory` |
| 设置在运行中被丢弃 | 模板 JSON 被外部改写 | 参数一律走 `comfyui_run` 的 `vars`，别改模板文件 |

---

## 6. 改之前先懂

- **参考图**走 `MiniMaxH3ReferenceToVideo` 的自动增长输入，槽名 `ref_images.ref_image_0`…（0 起，最多 9）。模板里 7 个 `LoadImage`（节点 `12`、`40`–`45`）接进去。
- **续接**用 `MiniMaxH3AddGuide` 把上一段末帧锚在**第 0 帧**（`frame_idx: 0`），`positive`/`latent` 来自节点 `16`，输出接 `BasicGuider`（节点 `8`）。
- **注意力后端**是 `comfy kitchen attention`（节点 `ModelAttentionBackend`），8 GB 卡实测最快。**不要换 SageAttention**（sm_120 上是负优化）。**也不要装 Sol-Attn**——实测第一次 `torch.compile` 就把 ComfyUI 进程打崩。
- **时长换算**：`f = max(5, round(秒×24))`，吸附 `f += (5 - f % 17) % 17`。3 秒→73、5 秒→124、15 秒→362。训练区间 **5–15 秒**。
- **参数**：8 步、`euler`/`simple`、LoRA 强度 1.0、768×1024。

模板节点 id 速查（v1.4.0）：
`1` UNETLoader、`7` LoraLoaderModelOnly、`10` CLIPLoader、`17`/`18` VAE、`20` RandomNoise、`21`/`22` 采样器、`33` VHS_VideoCombine、`16` MiniMaxH3ReferenceToVideo、`47` 续接锚点图、`48` MiniMaxH3AddGuide、**`50` VHS_LoadVideoPath（参考视频 → `ref_videos` + `ref_video_audios`）**。

参考图槽位：`12`、`40`、`41`、`42`、`43`、`44`、`45`、`46`、`49` → `ref_images.ref_image_0..8`（**最多 9 张**，模型 autogrow 上限）。

## 6.5 v1.4.0 新增能力（WebUI 侧重）

| 能力 | 说明 | 依赖 |
|---|---|---|
| 三档画质 | `quality: fast`（pruned LoRA + 4 步）/ `fine`（无 LoRA + 8 步）/ `ultra`（无 LoRA + 20 步） | fast 档需要 `minimax_h3_dmd_ref2va_8step_turbo_pruned.safetensors`，缺了就只剩 8 步效果 |
| 9 张参考图 | 之前模板只接了 7 个槽，模型其实支持 9 | 无 |
| 参考视频 | 2–15 秒 / 24fps，提示词用 `<Video 1>`、音频 `<Audio 1>`；**不决定成片时长** | 需要 VideoHelperSuite（`VHS_LoadVideoPath`） |
| 视频改人物 | 视频定动作 + 图片定人物，相当于"换角重演" | 同上 |
| 三段式提示词 | ① 参考说明自动生成 ② 动作描写 ③ 镜头描写（17 条官方三段式预设） | 无 |
| 上传视频 | `POST /api/upload_video` | 无 |

**性能事实**（8 GB 笔记本实测，3 秒 / 73 帧 / 1 图）：无 LoRA 8 步 157.6 s；pruned LoRA 8 步 188.9 s；非剪枝 LoRA 8 步 190.1 s；无 LoRA 4 步 79.9 s（但画面崩坏，不可用）；pruned LoRA 4 步 98 s；**加参考视频后 310.9 s**。

**结论**：同步数下挂 LoRA 是负优化；LoRA 的价值是"买更低步数"，且必须是 **pruned 适配版**（非剪枝版的 AdaLN 适配器在剪枝基模上会被移除）。

## 6.6 升级到 v1.4.0 的步骤

```powershell
cd <项目目录>
git pull
powershell -ExecutionPolicy Bypass -File .\sync.ps1     # 同步模板到 DSH 插件目录
# 模板变了，必须重载插件：
# plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=false
# plugin_manager action=set_bundle target=dsh-comfyui-workbench enabled=true
```

验证：`comfyui_workflow {workflowId:"minimax-h3-ref2v-community-multi"}` 应看到 `missingNodes: []`，
且节点清单里有 `VHS_LoadVideoPath`（节点 `50`）；`inputs` 里应有 `image1..image9` 和 `ref_video`。


---

## 7. 汇报格式

```
【环境】ComfyUI 版本 / GPU / 显存 / 内存 / Python+torch
【模板】3 个模板的 missingNodes + models.primary
【WebUI】health / outputs 条数 / 首页状态码 + 访问地址
【验收】4 条实跑：帧数、时长、真实耗时、文件大小、产物路径
【差异】与本包偏离项（改了哪些 id / 换了哪些模型 / 为什么）
【阻塞】没跑通的部分 + 报错原文
```

不要只回"已完成"，要给可核对的数据。

**现在开始：先解压 → 装模板 → 重载插件 → 报第一次验证结果，再往下做。**
