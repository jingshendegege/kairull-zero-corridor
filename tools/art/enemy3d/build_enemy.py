"""构建敌人图集：调用 Blender 渲染 → 像素合成 → 图集 PNG/JSON + 动态预览 GIF。

用法：python build_enemy.py rifleman|loader|hound|beat_warden
依赖：Blender 4.5.3（D:/ProgramData/Blender/...）、Pillow、numpy。幂等：同输入重复运行结果一致。
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BLENDER = Path(r"D:/ProgramData/Blender/blender-4.5.3-windows-x64/blender.exe")
sys.path.insert(0, str(HERE))
import palettes  # noqa: E402
import post  # noqa: E402

SPECS = {
    "rifleman": {
        "model": "rifleman.py", "palette": palettes.RIFLEMAN,
        "out": ROOT / "godot/assets/enemy/rifleman",
        "cell": (128, 112), "baseline": 105, "columns": 8,
        "anims": {
            "idle": {"frames": 3, "loop": True, "fps_hint": 2},
            "alert": {"frames": 4, "loop": False, "fps_hint": 8},
            "run": {"frames": 8, "loop": True, "fps_hint": 10},
            "aim": {"frames": 5, "loop": False, "fps_hint": 8},
            "fire": {"frames": 4, "loop": False, "fps_hint": 14},
            "death": {"frames": 6, "loop": False, "fps_hint": 8},
        },
        "ground_snap": "all",   # 所有帧最低像素贴脚底线：跑步不飘、倒地以脚为支点不腾空
        "extra": {"aim_recovery": "reuse_idle", "fire_recovery": "reuse_idle",
                  "source": "tools/art/enemy3d/rifleman.py（原创 Blender 基本体模型，3D→像素）"},
    },
    "loader": {
        "model": "loader.py", "palette": palettes.LOADER,
        "out": ROOT / "godot/assets/enemy/loader",
        "cell": (160, 128), "baseline": 121, "columns": 8,
        "anims": {
            "idle": {"frames": 4, "loop": True, "fps_hint": 2},
            "alert": {"frames": 5, "loop": False, "fps_hint": 12},
            "run": {"frames": 8, "loop": True, "fps_hint": 10},
            "windup": {"frames": 4, "loop": False, "fps_hint": 12},
            "attack": {"frames": 6, "loop": False, "fps_hint": 24},
            "recover": {"frames": 4, "loop": False, "fps_hint": 10},
            "death": {"frames": 6, "loop": False, "fps_hint": 9},
        },
        "ground_snap": "all",
        "extra": {"source": "tools/art/enemy3d/loader.py（原创 Blender 基本体模型，3D→像素）",
                  "attack_active_frames": [1, 2, 3, 4, 5]},
    },
    "hound": {
        "model": "hound.py", "palette": palettes.HOUND,
        "out": ROOT / "godot/assets/enemy/hound",
        "cell": (160, 96), "baseline": 89, "columns": 8,
        "anims": {
            "idle": {"frames": 4, "loop": True, "fps_hint": 2},
            "alert": {"frames": 4, "loop": False, "fps_hint": 10},
            "run": {"frames": 6, "loop": True, "fps_hint": 12},
            "windup": {"frames": 4, "loop": False, "fps_hint": 10},
            "pounce": {"frames": 4, "loop": False, "fps_hint": 12},
            "recover": {"frames": 4, "loop": False, "fps_hint": 8},
            "death": {"frames": 6, "loop": False, "fps_hint": 9},
        },
        "ground_snap": "all",   # 飞扑的高度由实体位置抛物线承担，精灵帧脚底贴线
        "extra": {"source": "tools/art/enemy3d/hound.py（原创 Blender 基本体模型，3D→像素）"},
    },
    "beat_warden": {
        "model": "beat_warden.py", "palette": palettes.BEAT_WARDEN,
        "out": ROOT / "godot/assets/boss/beat_warden",
        "cell": (288, 272), "baseline": 262, "columns": 6,
        "anims": {
            "idle": {"frames": 4, "loop": True, "fps_hint": 8},        # 运行时按拍相位选帧，0 = 拍点
            "fire_ground": {"frames": 3, "loop": False, "fps_hint": 16},
            "fire_air": {"frames": 3, "loop": False, "fps_hint": 16},
            "hurt": {"frames": 3, "loop": False, "fps_hint": 14},
            "expose": {"frames": 4, "loop": False, "fps_hint": 6},
            "core": {"frames": 4, "loop": True, "fps_hint": 8},        # 露核状态下的随拍呼吸
            "death": {"frames": 6, "loop": False, "fps_hint": 6},
        },
        "ground_snap": "all",
        "extra": {"source": "tools/art/enemy3d/beat_warden.py（原创 Blender 基本体模型，3D→像素）",
                  "lanes_above_ground": {"ground": 36, "air": 108}},
    },
}


def render(spec: dict, raw: Path) -> dict:
    cmd = [str(BLENDER), "-b", "--factory-startup", "-P", str(HERE / spec["model"]), "--", str(raw)]
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if "_RENDER_DONE" not in res.stdout:
        raise RuntimeError(res.stdout[-2000:] + res.stderr[-2000:])
    return json.loads((raw / "parts.json").read_text(encoding="utf-8"))


def preview_gif(atlas_png: Path, meta: dict, out: Path, scale: int = 3) -> None:
    atlas = Image.open(atlas_png)
    cw, ch = meta["cell_size"]
    names = list(meta["animations"])
    length = 16
    frames = []
    bg = (39, 50, 63, 255)
    for t in range(length):
        sheet = Image.new("RGBA", (cw * scale * len(names), ch * scale), bg)
        for k, name in enumerate(names):
            a = meta["animations"][name]
            n = a["frames"]
            i = t % n if a["loop"] else min(n - 1, t % (n + 4))
            cell = atlas.crop((i * cw, a["row"] * ch, (i + 1) * cw, (a["row"] + 1) * ch))
            sheet.alpha_composite(cell.resize((cw * scale, ch * scale), Image.NEAREST), (k * cw * scale, 0))
        frames.append(sheet.convert("P", palette=Image.ADAPTIVE, colors=255))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=125, loop=0, disposal=2)


def main() -> None:
    name = sys.argv[1]
    spec = SPECS[name]
    out = spec["out"]
    out.mkdir(parents=True, exist_ok=True)
    raw = Path(tempfile.mkdtemp(prefix=f"enemy_{name}_"))
    try:
        parts = render(spec, raw)
        extra = dict(spec["extra"])
        if "fire_0_px" in parts:
            mx, my = parts["fire_0_px"]
            ox = (spec["cell"][0] - parts["res"][0]) // 2
            extra["muzzle_world"] = [round(mx + ox - spec["cell"][0] / 2, 1), round(my - parts["baseline"] - 1, 1)]  # 相对地面（像素下沿）
        for key in ("horn_ground_px", "horn_air_px", "core_px"):   # Boss 号角口/核心：相对脚底中点的世界偏移
            if key in parts:
                mx, my = parts[key]
                ox = (spec["cell"][0] - parts["res"][0]) // 2
                extra[key.replace("_px", "_world")] = [round(mx + ox - spec["cell"][0] / 2, 1),
                                                       round(my - parts["baseline"] - 1, 1)]
        gs = spec.get("ground_snap", [])
        snap = {"all"} if gs == "all" else set(gs)

        def ground(name: str, _i: int, img: Image.Image) -> Image.Image:
            if snap != {"all"} and name not in snap:
                return img
            bb = img.getbbox()
            dy = parts["baseline"] + 1 - bb[3] if bb else 0
            out_img = Image.new("RGBA", img.size, (0, 0, 0, 0))
            out_img.alpha_composite(img, (0, dy))
            return out_img

        meta = post.build_atlas(raw, spec["palette"], spec["anims"], spec["cell"], spec["baseline"],
                                spec["columns"], out / "atlas.png", out / "atlas.json", extra, post_frame=ground)
        previews = HERE / "previews"
        previews.mkdir(exist_ok=True)
        preview_gif(out / "atlas.png", meta, previews / f"{name}.gif")   # 预览不放进游戏素材目录，避免进 Web 包
        print("BUILD_OK", name, meta["canvas_size"], extra.get("muzzle_world"))
    finally:
        shutil.rmtree(raw, ignore_errors=True)


if __name__ == "__main__":
    main()
