"""H3 Studio — 基于本机 MiniMax-H3 模板的傻瓜化视频生成 WebUI。

启动：<ComfyUI venv python> app.py   然后浏览器打开 http://127.0.0.1:8190
"""
import asyncio, json, os, re, shutil, time, uuid
from pathlib import Path

import av
from aiohttp import ClientSession, WSMsgType, web
from PIL import Image

COMFY_DEFAULT = "http://127.0.0.1:8188"
PORT_DEFAULT = 8190

HERE = Path(__file__).parent
GALLERY = HERE / "outputs"
UPLOADS = HERE / "uploads"


def load_config() -> dict:
    cfg = {"comfyUrl": COMFY_DEFAULT, "port": PORT_DEFAULT,
           "inputDir": "", "outputDir": "", "workflowsDir": ""}
    p = HERE / "config.json"
    if p.exists():
        try:
            cfg.update(json.loads(p.read_text(encoding="utf-8")))
        except Exception as exc:
            print(f"[warn] config.json 读取失败：{exc}")
    return cfg


def probe_comfy_dirs(comfy: str) -> tuple[str | None, str | None, str | None]:
    """从 ComfyUI 的 /system_stats argv 里推 --input-directory / --output-directory 与安装目录。"""
    import urllib.request
    try:
        with urllib.request.urlopen(f"{comfy}/system_stats", timeout=6) as r:
            stats = json.loads(r.read().decode("utf-8"))
    except Exception:
        return None, None, None
    argv = (stats.get("system") or {}).get("argv") or []
    inp = out = inst = None
    for i, a in enumerate(argv):
        if a == "--input-directory" and i + 1 < len(argv):
            inp = argv[i + 1]
        elif a == "--output-directory" and i + 1 < len(argv):
            out = argv[i + 1]
        elif a.endswith("main.py") and i > 0:
            inst = str(Path(argv[i - 1]).parent if Path(argv[i - 1]).name.lower() not in ("python.exe", "python") else "")
    return inp, out, inst


CFG = load_config()
COMFY = str(CFG["comfyUrl"]).rstrip("/")
PORT = int(CFG["port"])

_inp, _out, _inst = probe_comfy_dirs(COMFY)

if CFG.get("inputDir"):
    INPUT_DIR = Path(CFG["inputDir"])
elif _inp:
    INPUT_DIR = Path(_inp)
elif _inst:
    INPUT_DIR = Path(_inst) / "input"
else:
    INPUT_DIR = HERE / "input"

if CFG.get("outputDir"):
    OUTPUT_DIR = Path(CFG["outputDir"])
elif _out:
    OUTPUT_DIR = Path(_out)
elif _inst:
    OUTPUT_DIR = Path(_inst) / "output"
else:
    OUTPUT_DIR = HERE / "output"

def pick_workflows_dir(cfg_dir: str) -> Path:
    """模板目录优先级：config.json → DSH 插件目录 → 仓库自带 workflows/（兜底）。"""
    candidates = []
    if cfg_dir:
        candidates.append(Path(cfg_dir))
    candidates.append(Path.home() / ".dsh-comfyui-workbench" / "workflows")
    candidates.append(HERE.parent / "workflows")      # 仓库里的副本
    candidates.append(HERE / "workflows")
    for c in candidates:
        if (c / "minimax-h3-ref2v-community-multi.json").exists():
            return c
    return candidates[0]


WORKFLOWS = pick_workflows_dir(CFG.get("workflowsDir", ""))

# 三档画质：快速 = pruned 蒸馏 LoRA + 4 步；精细/极精细 = 无 LoRA，8/20 步
QUALITY = {
    "fast":  {"steps": 4,  "lora": "minimax_h3_dmd_ref2va_8step_turbo_pruned.safetensors", "label": "快速"},
    "fine":  {"steps": 8,  "lora": None, "label": "精细"},
    "ultra": {"steps": 20, "lora": None, "label": "极精细"},
}
# 3 秒（73 帧）实测基准，用于估算耗时
# 相对倍率（与硬件无关，以"精细"=1 为基准，本机实测拟合）
QUALITY_RATIO = {"fast": 0.72, "fine": 1.0, "ultra": 1.85}
LORA_NODE = "7"
ATTN_NODE = "6"

T_SINGLE = "minimax-h3-ref2v-community-multi"
T_CONTINUE = "minimax-h3-ref2v-continue"
REF_NODES = ["12", "40", "41", "42", "43", "44", "45", "46", "49"]   # ref_image_0..8（模型上限 9 张）
ANCHOR_NODE = "47"
VIDEO_NODE = "50"       # VHS_LoadVideoPath：参考视频帧 + 原声
MAX_REFS = len(REF_NODES)

CLIENT_ID = uuid.uuid4().hex
PROGRESS: dict[str, dict] = {}
JOBS: dict[str, dict] = {}
JOB_FILE = HERE / "jobs.json"


def save_jobs() -> None:
    try:
        tmp = JOB_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(JOBS, ensure_ascii=False), encoding="utf-8")
        tmp.replace(JOB_FILE)
    except Exception as exc:
        print(f"[warn] 任务记录落盘失败：{exc}")


def load_jobs() -> None:
    if not JOB_FILE.exists():
        return
    try:
        data = json.loads(JOB_FILE.read_text(encoding="utf-8"))
        for k, v in data.items():
            if isinstance(v, dict) and "pid" in v:
                JOBS[k] = v
    except Exception as exc:
        print(f"[warn] 任务记录读取失败：{exc}")


for d in (GALLERY, UPLOADS, INPUT_DIR):
    d.mkdir(parents=True, exist_ok=True)


# ---------- 工具 ----------
def frames_for(seconds: float) -> int:
    f = max(5, round(seconds * 24))
    return f + (5 - f % 17) % 17


def load_template(tid: str) -> dict:
    return json.loads((WORKFLOWS / f"{tid}.json").read_text(encoding="utf-8"))


def build_graph(prompt: str, duration: float, images: list[str], mode: str, anchor: str | None,
                quality: str = "fine", video: str | None = None) -> dict:
    tid = T_CONTINUE if mode == "continue" else T_SINGLE
    g = load_template(tid)
    q = QUALITY.get(quality) or QUALITY["fine"]
    g["11"]["inputs"]["value"] = prompt
    g["14"]["inputs"]["value"] = float(duration)
    g["22"]["inputs"]["steps"] = int(q["steps"])
    if q["lora"]:
        g[LORA_NODE]["inputs"]["lora_name"] = q["lora"]
        g[LORA_NODE]["inputs"]["strength_model"] = 1.0
    else:
        # 摘掉 LoRA 节点，让 guider / scheduler 直接吃注意力后端的模型
        g.pop(LORA_NODE, None)
        for nid in ("8", "22"):
            if g.get(nid, {}).get("inputs", {}).get("model", [None])[0] == LORA_NODE:
                g[nid]["inputs"]["model"] = [ATTN_NODE, 0]
    for i, node in enumerate(REF_NODES):
        key = f"ref_images.ref_image_{i}"
        if i < len(images):
            g[node]["inputs"]["image"] = images[i]
            g["16"]["inputs"][key] = [node, 0]
        else:
            g["16"]["inputs"].pop(key, None)
            g.pop(node, None)
    if video:
        g[VIDEO_NODE]["inputs"]["video"] = video
        g["16"]["inputs"]["ref_videos.ref_video_0"] = [VIDEO_NODE, 0]
        g["16"]["inputs"]["ref_video_audios.ref_video_audio_0"] = [VIDEO_NODE, 2]
    else:
        g.pop(VIDEO_NODE, None)
        for key in ("ref_videos.ref_video_0", "ref_video_audios.ref_video_audio_0"):
            g["16"]["inputs"].pop(key, None)
    if mode == "continue":
        if not anchor:
            raise web.HTTPBadRequest(text="衔接模式需要一个锚点（上一段末帧或指定图片）")
        g[ANCHOR_NODE]["inputs"]["image"] = anchor
    return g


CALIB_FILE = HERE / "calib.json"


def load_calib() -> list[dict]:
    try:
        if CALIB_FILE.exists():
            d = json.loads(CALIB_FILE.read_text(encoding="utf-8"))
            return d.get("samples", [])
    except Exception:
        pass
    return []


def add_calib(steps: int, frames: int, images: int, seconds: float) -> None:
    """记录一次真实耗时，用于本机自适应估算。"""
    if not seconds or steps <= 0 or frames <= 0:
        return
    samples = load_calib()
    samples.append({"steps": int(steps), "frames": int(frames),
                    "images": int(max(1, images)), "seconds": round(float(seconds), 1),
                    "at": int(time.time())})
    samples = samples[-60:]
    try:
        tmp = CALIB_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps({"samples": samples}, ensure_ascii=False), encoding="utf-8")
        tmp.replace(CALIB_FILE)
    except Exception as exc:
        print(f"[warn] 校准数据落盘失败：{exc}")


def estimate_seconds(duration: float, quality: str, n_images: int) -> int | None:
    """本机没跑过就返回 None（前端只显示倍率）；有样本才给绝对秒数。"""
    samples = load_calib()
    if not samples:
        return None
    frames = frames_for(duration)
    steps = QUALITY[quality]["steps"]
    ref = sorted(s["steps"] for s in samples)[len(samples) // 2]     # 参考步数
    base = [s for s in samples if s["steps"] == ref] or samples
    per_run = sorted(s["seconds"] for s in base)[len(base) // 2]
    est = per_run * (steps / ref) * (frames / 73)
    if n_images > 1:
        est *= 1 + min(n_images - 1, 6) * 0.09
    return int(est)


def last_frame_png(video: Path, dst: Path) -> None:
    c = av.open(str(video))
    frames = [f for f in c.decode(video=0)]
    if not frames:
        raise RuntimeError("视频解不出帧")
    frames[-1].to_image().save(dst)


def pick_artifact(entry: dict) -> Path | None:
    cands = []
    for out in (entry.get("outputs") or {}).values():
        for key in ("gifs", "videos", "images"):
            for item in out.get(key) or []:
                fn = item.get("filename") or ""
                if fn.lower().endswith((".mp4", ".webm", ".mkv")):
                    cands.append(OUTPUT_DIR / (item.get("subfolder") or "") / fn)
    cands = [p for p in cands if p.exists()]
    if not cands:
        return None
    cands.sort(key=lambda p: ("-audio" not in p.name, p.name))
    return cands[0]


async def comfy_json(session: ClientSession, path: str, data=None):
    async with session.post(f"{COMFY}{path}", json=data) if data is not None else session.get(f"{COMFY}{path}") as r:
        return await r.json()


async def ws_progress_loop():
    """订阅 ComfyUI 的 ws，记录每个 prompt 的进度。"""
    while True:
        try:
            async with ClientSession() as s:
                async with s.ws_connect(f"{COMFY}/ws?clientId={CLIENT_ID}") as ws:
                    async for msg in ws:
                        if msg.type != WSMsgType.TEXT:
                            continue
                        try:
                            d = json.loads(msg.data)
                        except Exception:
                            continue
                        t = d.get("type")
                        data = d.get("data") or {}
                        pid = data.get("prompt_id")
                        if t == "progress" and pid:
                            PROGRESS[pid] = {"step": data.get("value", 0), "total": data.get("max", 0)}
                        elif t == "executing" and pid and data.get("node") is None:
                            PROGRESS.setdefault(pid, {})["done"] = True
        except Exception:
            await asyncio.sleep(2)


async def job_worker(app, job_id: str, pid: str):
    job = JOBS[job_id]
    job["state"] = "running"
    async with ClientSession() as s:
        deadline = time.time() + 7200
        tick = 0
        while time.time() < deadline:
            await asyncio.sleep(2)
            tick += 1
            h = await comfy_json(s, f"/history/{pid}")
            entry = h.get(pid)
            job["elapsed"] = round(time.time() - job["started"], 1)
            job["progress"] = PROGRESS.get(pid, {})
            if tick % 3 == 0:
                save_jobs()
            if entry:
                st = (entry.get("status") or {}).get("status_str")
                # 记录真实执行耗时（不含排队），用于本机自适应校准
                if st != "error":
                    try:
                        msgs = (entry.get("status") or {}).get("messages") or []
                        t0 = next((m[1]["timestamp"] for m in msgs if m[0] == "execution_start"), None)
                        t1 = next((m[1]["timestamp"] for m in msgs if m[0] == "execution_success"), None)
                        if t0 and t1:
                            job["actual"] = round((t1 - t0) / 1000, 1)
                            add_calib(job.get("steps") or 0, job.get("frames") or 0,
                                      len(job.get("images") or []), job["actual"])
                    except Exception:
                        pass
                if st == "error":
                    job["state"] = "failed"
                    job["error"] = json.dumps((entry.get("status") or {}).get("messages"))[:600]
                    save_jobs()
                    return
                art = pick_artifact(entry)
                if art:
                    dst = GALLERY / f"{job_id}_{art.name}"
                    shutil.copyfile(art, dst)
                    job["state"] = "done"
                    job["artifact"] = dst.name
                    job["rel"] = str(art.relative_to(OUTPUT_DIR)).replace("\\", "/")
                    job["duration"] = round(float(av.open(str(dst)).duration) / 1e6, 2)
                    save_jobs()
                    return
                job["state"] = "done"
                save_jobs()
                return
            # 队列里已经没有它、history 也没有 → 说明 ComfyUI 重启过，任务已丢
            q = await comfy_json(s, "/queue")
            busy = {str(x[1]) for x in (q.get("queue_running") or []) if len(x) > 1}
            pend = {str(x[1]) for x in (q.get("queue_pending") or []) if len(x) > 1}
            if pid not in busy and pid not in pend:
                job["state"] = "failed"
                job["error"] = "任务不在队列里（ComfyUI 可能重启过）"
                save_jobs()
                return
        job["state"] = "failed"
        job["error"] = "超时"
        save_jobs()


# ---------- 路由 ----------
async def index(_req):
    return web.FileResponse(HERE / "static" / "index.html")


def _video_meta(p: Path) -> dict | None:
    """探测一个文件是不是有效视频；无效返回 None。"""
    try:
        if p.stat().st_size < 20 * 1024:
            return None
        c = av.open(str(p))
        vs = [s for s in c.streams if s.type == "video"]
        if not vs:
            return None
        dur = round(float(c.duration) / 1e6, 2) if c.duration else 0.0
        if dur <= 0:
            return None
        v = vs[0].codec_context
        return {"name": p.name, "rel": str(p.relative_to(OUTPUT_DIR)).replace("\\", "/"),
                "mb": round(p.stat().st_size / 1024 / 1024, 2), "dur": dur,
                "w": v.width, "h": v.height, "mtime": int(p.stat().st_mtime), "abs": str(p.resolve())}
    except Exception:
        return None


LIB_FILE = HERE / "library.json"


def load_lib() -> dict:
    if LIB_FILE.exists():
        try:
            d = json.loads(LIB_FILE.read_text(encoding="utf-8"))
            d.setdefault("next", 1)
            d.setdefault("map", {})
            return d
        except Exception:
            pass
    return {"next": 1, "map": {}}


def save_lib(lib: dict) -> None:
    try:
        tmp = LIB_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(lib, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(LIB_FILE)
    except Exception as exc:
        print(f"[warn] 编号表落盘失败：{exc}")


def rel_by_no(no: int) -> str | None:
    lib = load_lib()
    for rel, n in lib["map"].items():
        if n == no:
            return rel
    return None


async def api_outputs(_req):
    """列出输出目录里的视频；同名 -audio / 无音轨 两份只保留带音轨的那份；每条分配稳定编号。"""
    cands = [p for p in OUTPUT_DIR.rglob("*.mp4") if not p.name.startswith("_")]
    picked: dict[str, tuple[dict, bool]] = {}
    for p in cands:
        meta = _video_meta(p)
        if not meta:
            continue
        stem = p.stem
        base = stem[:-6] if stem.endswith("-audio") else stem
        key = f"{p.parent}|{base}"
        has_audio = stem.endswith("-audio")
        old = picked.get(key)
        if old is None or (has_audio and not old[1]):
            picked[key] = (meta, has_audio)

    items = [m for m, _ in picked.values()]

    lib = load_lib()
    changed = False
    for m in sorted(items, key=lambda x: x["mtime"]):
        if m["rel"] not in lib["map"]:
            lib["map"][m["rel"]] = lib["next"]
            lib["next"] += 1
            changed = True
        m["no"] = lib["map"][m["rel"]]
    if changed:
        save_lib(lib)

    items.sort(key=lambda x: x["no"], reverse=True)
    return web.json_response({"items": items[:80], "total": len(items), "next": lib["next"]})


async def api_video(req):
    rel = req.query.get("rel", "")
    if not rel and req.query.get("no", "").isdigit():
        rel = rel_by_no(int(req.query["no"])) or ""
    p = (OUTPUT_DIR / rel).resolve()
    if not rel or OUTPUT_DIR not in p.parents or not p.exists():
        raise web.HTTPNotFound()
    return web.FileResponse(p)


THUMBS = HERE / "thumbs"


async def api_thumb(req):
    """取视频中间一帧做缩略图，按 文件名+mtime 缓存到磁盘。"""
    rel = req.query.get("rel", "")
    if not rel and req.query.get("no", "").isdigit():
        rel = rel_by_no(int(req.query["no"])) or ""
    p = (OUTPUT_DIR / rel).resolve()
    if not rel or OUTPUT_DIR not in p.parents or not p.exists():
        raise web.HTTPNotFound()
    THUMBS.mkdir(parents=True, exist_ok=True)
    key = f"{abs(hash((rel, int(p.stat().st_mtime)))):x}.jpg"
    dst = THUMBS / key
    if not dst.exists():
        def _make():
            c = av.open(str(p))
            frames = [f.to_image() for f in c.decode(video=0)]
            if not frames:
                raise RuntimeError("空视频")
            img = frames[len(frames) // 3]
            img.thumbnail((320, 440), Image.LANCZOS)
            img.convert("RGB").save(dst, quality=82)
        await asyncio.to_thread(_make)
    return web.FileResponse(dst, headers={"Cache-Control": "max-age=86400"})


async def api_lastframe(req):
    rel = req.query.get("rel", "")
    p = (OUTPUT_DIR / rel).resolve()
    if OUTPUT_DIR not in p.parents or not p.exists():
        raise web.HTTPNotFound()
    dst = UPLOADS / f"last_{uuid.uuid4().hex[:8]}.png"
    last_frame_png(p, dst)
    return web.json_response({"preview": f"/api/uploaded/{dst.name}"})


async def api_upload(req):
    reader = await req.multipart()
    names = []
    while True:
        part = await reader.next()
        if part is None:
            break
        if part.name != "images":
            continue
        ext = Path(part.filename or "img.png").suffix.lower() or ".png"
        name = f"ui_{uuid.uuid4().hex[:10]}{ext}"
        dst = INPUT_DIR / name
        with open(dst, "wb") as fh:
            while True:
                chunk = await part.read_chunk()
                if not chunk:
                    break
                fh.write(chunk)
        # 统一转成 png，避免 webp/avif 兼容问题
        try:
            im = Image.open(dst)
            im = im.convert("RGBA")
            bg = Image.new("RGB", im.size, (0, 0, 0))
            bg.paste(im, mask=im.split()[3])
            png = dst.with_suffix(".png")
            bg.save(png)
            if png != dst:
                dst.unlink(missing_ok=True)
            names.append(png.name)
        except Exception:
            names.append(name)
    return web.json_response({"names": names})


async def api_uploaded(req):
    p = UPLOADS / req.match_info["name"]
    if not p.exists():
        raise web.HTTPNotFound()
    return web.FileResponse(p)


async def api_upload_video(req):
    """上传参考视频：原样存进 ComfyUI 的 input 目录（不转码）。"""
    reader = await req.multipart()
    saved = []
    while True:
        part = await reader.next()
        if part is None:
            break
        if part.name != "video":
            continue
        ext = Path(part.filename or "clip.mp4").suffix.lower() or ".mp4"
        if ext not in (".mp4", ".webm", ".mkv", ".mov", ".avi"):
            raise web.HTTPBadRequest(text=f"不支持的视频格式 {ext}")
        name = f"refvid_{uuid.uuid4().hex[:10]}{ext}"
        dst = INPUT_DIR / name
        with open(dst, "wb") as fh:
            while True:
                chunk = await part.read_chunk()
                if not chunk:
                    break
                fh.write(chunk)
        saved.append(name)
    return web.json_response({"names": saved})


async def api_inputimg(req):
    p = INPUT_DIR / req.match_info["name"]
    if not p.exists():
        raise web.HTTPNotFound()
    return web.FileResponse(p)


async def api_generate(req):
    body = await req.json()
    prompt = (body.get("prompt") or "").strip()
    if not prompt:
        return web.json_response({"error": "提示词不能为空"}, status=400)
    duration = float(body.get("duration") or 5)
    if not 1 <= duration <= 15:
        return web.json_response({"error": "时长需在 1–15 秒之间"}, status=400)
    images = [n for n in (body.get("images") or []) if n][:MAX_REFS]
    mode = body.get("mode") or "single"
    quality = body.get("quality") or "fine"
    if quality not in QUALITY:
        return web.json_response({"error": f"未知画质档位 {quality}，可选 fast / fine / ultra"}, status=400)
    anchor = body.get("anchor") or None
    video = body.get("video") or None
    if video:
        # 既支持 input 目录里的文件名，也支持已有成片的绝对路径（VHS 接受绝对路径）
        cand = Path(video)
        src = cand if cand.is_absolute() else (INPUT_DIR / cand.name)
        if not src.exists():
            return web.json_response({"error": f"参考视频不存在：{video}"}, status=400)
        try:
            dur = float(av.open(str(src)).duration) / 1e6
            if dur < 1.5:
                return web.json_response({"error": f"参考视频太短（{dur:.1f} 秒），需要 2–15 秒"}, status=400)
        except Exception:
            pass
        video = str(src) if src.is_absolute() else src.name
    if mode == "swap" and not video:
        return web.json_response({"error": "「视频改人物」必须提供一段参考视频"}, status=400)
    if mode == "continue":
        if anchor and anchor.endswith((".mp4", ".webm", ".mkv")):
            src = (OUTPUT_DIR / anchor).resolve()
            if OUTPUT_DIR not in src.parents or not src.exists():
                return web.json_response({"error": "找不到要衔接的视频"}, status=400)
            img = INPUT_DIR / f"anchor_{uuid.uuid4().hex[:8]}.png"
            last_frame_png(src, img)
            anchor = img.name
        elif anchor:
            src = UPLOADS / Path(anchor).name
            if not src.exists():
                return web.json_response({"error": "找不到锚点图片"}, status=400)
            mask = INPUT_DIR / f"anchor_{uuid.uuid4().hex[:8]}.png"
            Image.open(src).convert("RGB").save(mask)
            anchor = mask.name
        else:
            return web.json_response({"error": "衔接模式请选择一条视频或上传一张锚点图"}, status=400)

    graph = build_graph(prompt, duration, images, mode, anchor, quality, video)
    try:
        async with ClientSession() as s:
            r = await s.post(f"{COMFY}/prompt", json={"prompt": graph, "client_id": CLIENT_ID})
            data = await r.json()
            if r.status != 200 or "prompt_id" not in data:
                return web.json_response({"error": "ComfyUI 拒绝了这次提交", "detail": data}, status=400)
    except Exception as exc:
        return web.json_response({"error": f"连不上 ComfyUI：{exc}"}, status=502)

    jid = uuid.uuid4().hex[:12]
    est = estimate_seconds(duration, quality, len(images))
    JOBS[jid] = {"id": jid, "pid": data["prompt_id"], "state": "queued", "started": time.time(),
                 "frames": frames_for(duration), "duration": duration, "mode": mode,
                 "quality": quality, "qualityLabel": QUALITY[quality]["label"],
                 "steps": QUALITY[quality]["steps"], "estimated": est, "video": video or "",
                 "prompt": prompt, "images": images}
    asyncio.create_task(job_worker(req.app, jid, data["prompt_id"]))
    save_jobs()
    return web.json_response({"job": jid, "pid": data["prompt_id"], "frames": frames_for(duration),
                              "steps": QUALITY[quality]["steps"], "estimated": est, "video": video or "",
                              "quality": quality})


async def api_job(req):
    job = JOBS.get(req.match_info["id"])
    if not job:
        raise web.HTTPNotFound()
    return web.json_response({k: v for k, v in job.items() if k != "pid"})


async def api_jobs(_req):
    items = sorted(JOBS.values(), key=lambda j: j["started"], reverse=True)[:30]
    return web.json_response({"items": [{k: v for k, v in j.items() if k != "pid"} for j in items]})


async def api_gallery_video(req):
    p = GALLERY / req.match_info["name"]
    if not p.exists():
        raise web.HTTPNotFound()
    return web.FileResponse(p)


async def api_health(_req):
    try:
        async with ClientSession() as s:
            async with s.get(f"{COMFY}/system_stats", timeout=5) as r:
                ok = r.status == 200
        return web.json_response({"comfy": ok, "port": PORT})
    except Exception:
        return web.json_response({"comfy": False, "port": PORT})


async def on_startup(app):
    app["ws_task"] = asyncio.create_task(ws_progress_loop())
    load_jobs()
    resumed = 0
    for jid, job in list(JOBS.items()):
        if job.get("state") in ("queued", "running") and job.get("pid"):
            asyncio.create_task(job_worker(app, jid, job["pid"]))
            resumed += 1
    if JOBS:
        print(f"[启动] 恢复 {len(JOBS)} 条任务记录，续跟 {resumed} 条")


def main():
    app = web.Application()
    app.router.add_get("/", index)
    app.router.add_static("/static", HERE / "static")
    app.router.add_get("/api/health", api_health)
    app.router.add_get("/api/outputs", api_outputs)
    app.router.add_get("/api/video", api_video)
    app.router.add_get("/api/thumb", api_thumb)
    app.router.add_get("/api/lastframe", api_lastframe)
    app.router.add_get("/api/uploaded/{name}", api_uploaded)
    app.router.add_get("/api/inputimg/{name}", api_inputimg)
    app.router.add_post("/api/upload", api_upload)
    app.router.add_post("/api/upload_video", api_upload_video)
    app.router.add_post("/api/generate", api_generate)
    app.router.add_get("/api/job/{id}", api_job)
    app.router.add_get("/api/jobs", api_jobs)
    app.router.add_get("/api/gallery/{name}", api_gallery_video)
    app.on_startup.append(on_startup)
    print(f"H3 Studio 已启动: http://127.0.0.1:{PORT}")
    web.run_app(app, host="127.0.0.1", port=PORT, print=None)


if __name__ == "__main__":
    main()
