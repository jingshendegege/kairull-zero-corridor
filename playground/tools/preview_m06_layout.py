"""M06 布局预览图：碰撞、房间框、实体与机关（每格 N 像素）。只读生成器数据，不写地图文件。"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_m06_exhaust_ridge as g  # noqa: E402

K = 6
doc = g.seed_document()
level = doc["levels"][0]
layers = {l["__identifier"]: l["intGridCsv"] for l in level["layerInstances"]}
W, H = g.W, g.H
img = Image.new("RGB", (W * K, H * K + 40), (22, 28, 38))
d = ImageDraw.Draw(img)
col = layers["Collision"]
for y in range(H):
    for x in range(W):
        v = col[y * W + x]
        if v == 1:
            d.rectangle([x * K, y * K, x * K + K - 1, y * K + K - 1], fill=(70, 86, 108))
        elif v == 2:
            d.rectangle([x * K, y * K, x * K + K - 1, y * K + 1], fill=(143, 217, 232))
        if layers["Architecture"][y * W + x] == 6:
            d.rectangle([x * K, y * K + K // 2, x * K + K - 1, y * K + K - 1], fill=(145, 162, 181))
for r in g.ROOMS:
    x, y, w, h = r["rect"]
    d.rectangle([x * K, y * K, (x + w) * K - 1, (y + h) * K - 1], outline=(120, 150, 170))
    d.text((x * K + 3, y * K + 2), r["room_id"], fill=(200, 210, 220))
colors = {1: (255, 255, 255), 2: (255, 209, 102), 3: (40, 215, 229), 4: (255, 79, 163), 5: (255, 193, 106), 6: (231, 89, 99)}
for x, row, v in g.ENTITIES:
    d.rectangle([x * K, (row - 2) * K, x * K + K - 1, row * K + K - 1], fill=colors[v])
for item in g.tactical_metadata():
    t = item["type"]
    if t == "updraft_fan":
        cx, fy = item["pos"]
        d.rectangle([(cx - 32) / 32 * K, fy / 32 * K - 2, (cx + 32) / 32 * K, fy / 32 * K + 1], fill=(120, 255, 170))
        d.line([cx / 32 * K, fy / 32 * K, cx / 32 * K, (fy - item["launch_height"]) / 32 * K], fill=(80, 200, 130))
    elif t == "glass_panel":
        gx, gy, gw, gh = item["rect"]
        d.rectangle([gx / 32 * K, gy / 32 * K, (gx + gw) / 32 * K - 1, (gy + gh) / 32 * K - 1], fill=(150, 220, 255))
    elif t == "dash_node":
        cx, cy = item["pos"]
        d.ellipse([cx / 32 * K - 3, cy / 32 * K - 3, cx / 32 * K + 3, cy / 32 * K + 3], fill=(120, 240, 255))
    elif t == "auto_sniper":
        cx, cy = item["pos"]
        d.rectangle([cx / 32 * K - 4, cy / 32 * K - 12, cx / 32 * K + 4, cy / 32 * K], fill=(255, 80, 90))
    elif t in ("laser_gate", "press"):
        cx, cy = item["pos"]
        wdt = item.get("span", item.get("width", 64))
        d.rectangle([cx / 32 * K, cy / 32 * K, (cx + wdt) / 32 * K, cy / 32 * K + 3], fill=(255, 150, 60))
    elif t == "smoke_pickup":
        cx, cy = item["pos"]
        d.ellipse([cx / 32 * K - 3, cy / 32 * K - 6, cx / 32 * K + 3, cy / 32 * K], fill=(200, 200, 200))
d.text((6, H * K + 8), "白=出生 金=出口 青=近战 品红=枪手 橙=货箱 红=房门 | 浅蓝块=玻璃 绿=弹射扇(竖线=弹射高度) 青点=冲刺节点 橙条=光栅/压机 红=狙击",
       fill=(220, 228, 240), font=ImageFont.truetype("msyh.ttc", 16))
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("m06_layout.png")
img.save(out)
print("saved", out, img.size)
