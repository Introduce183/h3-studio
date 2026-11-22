# H3 Studio · MiniMax-H3 图生视频 WebUI

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
