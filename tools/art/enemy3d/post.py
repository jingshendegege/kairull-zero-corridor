"""3D 渲染 → 像素画合成与图集打包（Pillow + numpy，Blender 外运行）。

输入：bl_rig.render_pair 产出的 id_*.png / nrm_*.png 与 parts.json。
合成规则（像素画师手法的程序化版本）：
1. ID 图逐像素匹配部件 → 材质；
2. 视图空间法线与固定主光做 Lambert，按阈值分 4 阶（高光/基色/阴影/深影）；
3. 外轮廓：接触透明的像素改为材质描边色（sel-out，自身色系）；
4. 部件分界：被更前（rank 更高）部件压住的一侧像素压到深影，形成内线；
5. 去斑：孤立单像素色阶并入邻域多数。
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

LIGHT = np.array([-0.55, 0.62, 0.56])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
RIM = np.array([0.92, 0.18, -0.35])   # 右后方轮廓光
RIM = RIM / np.linalg.norm(RIM)


def hx(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def load_parts(raw: Path) -> dict:
    return json.loads((raw / "parts.json").read_text(encoding="utf-8"))


def _decode(raw: Path, tag: str, parts: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    idim = np.asarray(Image.open(raw / f"id_{tag}.png").convert("RGBA")).astype(int)
    nim = np.asarray(Image.open(raw / f"nrm_{tag}.png").convert("RGBA")).astype(float)
    ids = np.array([p["id_rgb"] for p in parts])
    alpha = idim[..., 3] > 127
    flat = idim[..., :3].reshape(-1, 3)
    d = ((flat[:, None, :] - ids[None, :, :]) ** 2).sum(2)
    pid = np.argmin(d, 1).reshape(alpha.shape)
    pid[~alpha] = -1
    nx = (nim[..., 0] - 115.0) / 112.0
    ny = (nim[..., 1] - 113.0) / 110.0
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    lam = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
    # 半程向量高光（观察方向 +Z）
    half = LIGHT + np.array([0.0, 0.0, 1.0])
    half = half / np.linalg.norm(half)
    spec = nx * half[0] + ny * half[1] + nz * half[2]
    rim = nx * RIM[0] + ny * RIM[1] + nz * RIM[2]
    return pid, np.stack([lam, spec, rim], -1)


def compose(raw: Path, tag: str, parts: list[dict], palette: dict, thresholds=(0.62, 0.12, -0.38),
            ss: int = 1) -> Image.Image:
    pid_hi, shade_hi = _decode(raw, tag, parts)
    H, W = pid_hi.shape[0] // ss, pid_hi.shape[1] // ss
    small = {p["name"] for p in parts if palette[p["material"]].get("emissive")}
    pid = np.full((H, W), -1, int)
    lam = np.zeros((H, W))
    spc = np.zeros((H, W))
    rim = np.zeros((H, W))
    ranks = np.array([p["rank"] for p in parts])
    for y in range(H):
        for x in range(W):
            blk = pid_hi[y * ss:(y + 1) * ss, x * ss:(x + 1) * ss]
            opaque = blk >= 0
            n = int(opaque.sum())
            if n == 0:
                continue
            vals, counts = np.unique(blk[opaque], return_counts=True)
            order = np.argsort(-ranks[vals])
            pick = -1
            for k in order:   # 前景优先：覆盖率足够的最前部件
                v, c = vals[k], counts[k]
                need = 0.25 if parts[v]["name"] in small else 0.4
                if c >= need * ss * ss:
                    pick = v
                    break
            if pick < 0:
                if n < 0.5 * ss * ss:
                    continue
                pick = vals[np.argmax(counts)]
            sel = blk == pick
            pid[y, x] = pick
            sh = shade_hi[y * ss:(y + 1) * ss, x * ss:(x + 1) * ss]
            lam[y, x] = sh[..., 0][sel].mean()
            spc[y, x] = sh[..., 1][sel].max()
            rim[y, x] = sh[..., 2][sel].mean()
    h, w = H, W
    level = np.where(lam > thresholds[0], 0, np.where(lam > thresholds[1], 1, np.where(lam > thresholds[2], 2, 3)))
    ys, xs = np.nonzero(pid >= 0)
    # 去斑：同部件内孤立色阶
    lv = level.copy()
    for y, x in zip(ys, xs):
        if not (0 < y < h - 1 and 0 < x < w - 1):
            continue
        same = [level[yy, xx] for yy in (y - 1, y, y + 1) for xx in (x - 1, x, x + 1)
                if (yy, xx) != (y, x) and pid[yy, xx] == pid[y, x]]
        if len(same) >= 5 and same.count(level[y, x]) == 0:
            lv[y, x] = Counter(same).most_common(1)[0][0]
    level = lv
    out = np.zeros((h, w, 4), np.uint8)
    edge_map = np.zeros((h, w), bool)
    for y, x in zip(ys, xs):
        p = parts[pid[y, x]]
        mat = palette[p["material"]]
        if mat.get("emissive"):
            col = mat["ramp"][0]
        else:
            lv_ = int(level[y, x])
            if mat.get("grain") and lv_ < 3:
                # 稀疏颗粒：固定像素哈希（同位置各帧一致），暗一阶，给布料/甲片粗粝质感
                hsh = (x * 73856093 ^ y * 19349663) & 0xFFFF
                if hsh % (7 if lv_ else 9) == 0:
                    lv_ += 1
            col = mat["ramp"][lv_]
            if "spec" in mat and spc[y, x] > mat.get("spec_at", 0.93) and level[y, x] == 0:
                col = mat["spec"]
            elif rim[y, x] > 0.55 and level[y, x] >= 2:
                col = mat.get("rim", mat["ramp"][1])   # 背光面上的冷色轮廓光
        edge = False
        behind = False
        front_edge = False
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if not (0 <= yy < h and 0 <= xx < w) or pid[yy, xx] < 0:
                edge = True
            else:
                q = parts[pid[yy, xx]]
                if q["rank"] > p["rank"] and q["material"] != p["material"] or                         (q["rank"] >= p["rank"] + 3 and q["name"] != p["name"]):
                    behind = True
                elif mat.get("outline_front") and q["rank"] < p["rank"] and q["material"] != p["material"]:
                    front_edge = True   # 手/枪/袖压在别的部件上：沿交界画自身描边，各自成形
        if edge:
            edge_map[y, x] = True
            # 受光侧描边用本材质深影（sel-out），背光侧用描边色
            col = mat["line"] if (mat.get("emissive") or level[y, x] >= 1) else mat["ramp"][3]
        elif front_edge:
            col = mat["line"]
        elif behind and not mat.get("emissive"):
            col = mat["ramp"][3]
        out[y, x] = (*hx(col), 255)
    _pixel_perfect(out, edge_map)
    return Image.fromarray(out, "RGBA")


def _pixel_perfect(out: np.ndarray, edge: np.ndarray) -> None:
    """清除外轮廓上的"L 形"多余拐角像素，让斜向轮廓成为单像素阶梯。"""
    h, w = edge.shape
    alpha = out[..., 3] > 0
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if not edge[y, x]:
                continue
            for (dy1, dx1), (dy2, dx2) in (((0, -1), (1, 0)), ((0, -1), (-1, 0)), ((0, 1), (1, 0)), ((0, 1), (-1, 0))):
                a_ = (y + dy1, x + dx1)
                b_ = (y + dy2, x + dx2)
                opp1 = (y - dy1, x - dx1)
                opp2 = (y - dy2, x - dx2)
                if edge[a_] and edge[b_] and not alpha[opp1] and not alpha[opp2]:
                    out[y, x] = 0
                    alpha[y, x] = False
                    edge[y, x] = False
                    break


def build_atlas(raw: Path, palette: dict, anims: dict, cell: tuple[int, int], baseline: int,
                columns: int, out_png: Path, out_json: Path, extra: dict | None = None,
                post_frame=None) -> dict:
    meta_parts = load_parts(raw)
    parts = meta_parts["parts"]
    rows = list(anims.items())
    atlas = Image.new("RGBA", (cell[0] * columns, cell[1] * len(rows)), (0, 0, 0, 0))
    frames = []
    res_x, res_y = meta_parts["res"]
    ox = (cell[0] - res_x) // 2
    oy = baseline - 1 - meta_parts["baseline"]   # baseline = 脚底像素行 + 1（像素下沿贴地），与旧图集约定一致
    anim_meta = {}
    for row, (name, spec) in enumerate(rows):
        count = spec["frames"]
        anim_meta[name] = {**spec, "row": row}
        for i in range(count):
            img = compose(raw, f"{name}_{i}", parts, palette, ss=meta_parts.get("ss", 1))
            if post_frame:
                img = post_frame(name, i, img)
            tile = Image.new("RGBA", cell, (0, 0, 0, 0))
            tile.alpha_composite(img, (ox, oy))
            atlas.alpha_composite(tile, (i * cell[0], row * cell[1]))
            bb = tile.getbbox() or (0, 0, 0, 0)
            frames.append({"animation": name, "frame": i, "row": row,
                           "cell_bbox": [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]]})
    atlas.save(out_png)
    meta = {"canvas_size": list(atlas.size), "cell_size": list(cell), "columns": columns,
            "baseline_y": baseline, "pivot_x": cell[0] // 2, "facing": "right",
            "animations": anim_meta, "frames": frames, **(extra or {})}
    out_json.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return meta


def contact_sheet(raw: Path, palette: dict, tags: list[str], scale: int, out: Path, bg=(39, 50, 63)) -> None:
    mp = load_parts(raw)
    parts = mp["parts"]
    imgs = [compose(raw, t, parts, palette, ss=mp.get("ss", 1)) for t in tags]
    w, h = imgs[0].size
    sheet = Image.new("RGBA", (w * scale * len(imgs), h * scale), (*bg, 255))
    for k, im in enumerate(imgs):
        sheet.alpha_composite(im.resize((w * scale, h * scale), Image.NEAREST), (k * w * scale, 0))
    sheet.save(out)
