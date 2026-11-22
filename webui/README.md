# H3 Studio · 图生视频 WebUI

本机 MiniMax-H3（ref2va 主模型）的傻瓜化前端。给图 + 写提示词 + 选时长即可出片，支持"接着上一段继续"。

## 启动

双击 `启动.bat`，或：

```powershell
& 'E:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI\.venv\Scripts\python.exe' 'E:\Comfy-Desktop\h3-studio\app.py'
```

然后打开 **http://127.0.0.1:8190**

> 后端会直接调 `http://127.0.0.1:8188` 上的 ComfyUI；ComfyUI 没起来时页面右上角会显示「ComfyUI 未启动」。

## 怎么用

1. **参考图**：拖入 1–7 张（角色三视图/服装图效果最好）。第一张同时决定外貌与构图基调。
2. **提示词**：默认已填好一段可直接用的模板。要点：
   - 第一行写 `参考 <Picture 1>–<Picture 7> 中的同一角色：外貌、服装以参考图为准，不要改变。`
   - 再加 `[Shot 1] 固定镜头，close-up portrait，head and shoulders`（近景）或 `full body shot，head to toe`（全身）
   - 动作按秒写，**每段最多 2 个动作**
3. **时长**：滑块 1–15 秒，下方实时显示吸附后的帧数（H3 只认 `17k+5` 网格）。
4. **模式**：
   - `单段生成`：直接出片
   - `衔接上一段`：从下拉里选一条已有视频（自动取它的**最后一帧**当锚点），或上传一张锚点图
5. 点生成，看进度条（采样步数/耗时），完成后可直接播放、下载，或点「以此续接下一段」。

## 实测数据（本机 RTX 5070 Laptop 8 GB）

| 场景 | 帧数 | 耗时 |
|---|---|---|
| 3 秒 / 1 张参考图 | 73 | **2 分 39 秒** |
| 3 秒 / 7 张参考图 | 73 | 9–10 分钟 |
| 5 秒 / 1 张参考图 | 124 | 约 5 分钟（冷启）/ 2 分钟（热态） |
| 15 秒 / 8 张参考图 | 362 | 约 71 分钟 |

## 原理

后端把工作流模板（`C:\Users\Introduce\.dsh-comfyui-workbench\workflows\` 里的
`minimax-h3-ref2v-community-multi` / `minimax-h3-ref2v-continue`）读出来，
按你的选择替换节点参数（参考图、提示词、时长、锚点），再 POST 给 ComfyUI。

- 单段 → 多图模板（7 个 `ref_image` 槽）
- 衔接 → 续接模板（多一个 `H3Guide`，把末帧锚在第 0 帧）

产物：ComfyUI 输出到 `E:\Comfy-Desktop\ComfyUI-Shared\output\`，本程序会复制一份到 `h3-studio\outputs\` 并保留原名。
