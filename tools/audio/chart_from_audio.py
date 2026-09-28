"""从任意成品音频（如 Suno 生成的摇滚曲）自动生成节拍 Boss 谱面（numpy + ffmpeg，无需 librosa）。

用法：python chart_from_audio.py <音频文件> [--bpm 150] [--out godot/assets/boss/beat_warden_chart.json]
流程：
  1. ffmpeg 解码为 22050Hz 单声道 → STFT。
  2. 分频段谱通量：低频（底鼓，40–150Hz）、中高频（军鼓/镲，1.5–8kHz）、全频能量。
  3. 速度：全频起音包络自相关，在 --bpm 附近（±15%）找峰；相位：按拍网格累加起音强度取最大。
  4. 段落：每 4 小节的 RMS 能量排序 → 低能量=intro/verse，渐强=build，高能量=drop，最后一段高能量=finale。
  5. 音符：只在真实打击处放——FFT 分频 3ms 包络找瞬态，量化到十六分网格（偏差 ≤40ms），
     底鼓 → ground，军鼓/镲 → air，只有吉他重音时交替；每小节按段落设上限（不凑数）；
     每两小节首拍的强起音 → heavy（运行时为上下同时按的双键音符，同拍其他音符让位）；drop/finale 的空拍按固定图样放 bomb（与前后音符留出换层时间）。
  6. 谱面合同与 beat_warden_song.py 相同（bpm/offset_sec/sections/notes/loop/boss_hp…），运行时无需改动。
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SR = 22050
HOP = 256
NFFT = 2048
## 谱通量在瞬态进入窗口时就上升，帧起点时间系统性偏早；用已知网格的 128BPM 合成曲校准（偏早 68ms）
ONSET_LATENCY = 0.068


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def stft_mag(x: np.ndarray) -> np.ndarray:
    win = np.hanning(NFFT).astype(np.float32)
    frames = 1 + (len(x) - NFFT) // HOP
    idx = np.arange(NFFT)[None, :] + HOP * np.arange(frames)[:, None]
    return np.abs(np.fft.rfft(x[idx] * win, axis=1))


def flux(mag: np.ndarray, lo: float, hi: float) -> np.ndarray:
    freqs = np.fft.rfftfreq(NFFT, 1.0 / SR)
    band = np.log1p(mag[:, (freqs >= lo) & (freqs < hi)] * 10.0)
    d = np.maximum(0.0, np.diff(band, axis=0)).sum(axis=1)
    d = np.concatenate([[0.0], d])
    d -= np.convolve(d, np.ones(16) / 16, mode="same")      # 去掉慢变化，只留起音
    d = np.maximum(d, 0.0)
    return d / (np.percentile(d, 99) + 1e-9)


def tempo(env: np.ndarray, guess: float) -> float:
    fps = SR / HOP
    ac = np.correlate(env - env.mean(), env - env.mean(), mode="full")[len(env) - 1:]
    best, best_bpm = -1e18, guess
    for bpm in np.arange(guess * 0.85, guess * 1.15, 0.05):
        lag = 60.0 / bpm * fps
        score = sum(np.interp(lag * k, np.arange(len(ac)), ac) / k for k in (1, 2, 4))
        if score > best:
            best, best_bpm = score, bpm
    return float(best_bpm)


def refine(env: np.ndarray, bpm: float) -> tuple[float, float]:
    """在粗估速度 ±1 BPM（步长 0.01）× 全相位（步长 2ms）上联合搜索，使拍网格上的起音总和最大——
    长曲子里 0.3% 的速度误差就会累积成几百毫秒漂移，必须精细对齐。"""
    fps = SR / HOP
    grid = np.arange(len(env))
    best = (-1.0, bpm, 0.0)
    for cand in np.arange(bpm - 1.0, bpm + 1.0, 0.01):
        period = 60.0 / cand
        n = int((len(env) / fps) / period) - 1
        offs = np.arange(0.0, period, 0.002)
        t = offs[:, None] + np.arange(n)[None, :] * period
        score = np.interp(t * fps, grid, env).sum(axis=1)
        k = int(np.argmax(score))
        if score[k] > best[0]:
            best = (float(score[k]), float(cand), float(offs[k]))
    return best[1], best[2]


def phase(env: np.ndarray, bpm: float) -> float:
    fps = SR / HOP
    period = 60.0 / bpm
    best, best_off = -1.0, 0.0
    for off in np.arange(0.0, period, 0.002):
        t = np.arange(off, len(env) / fps, period)
        s = np.interp(t * fps, np.arange(len(env)), env).sum()
        if s > best:
            best, best_off = s, off
    return float(best_off)


def transients(x: np.ndarray, lo: float, hi: float) -> tuple[np.ndarray, np.ndarray]:
    """整段 FFT 分频 → 3ms 包络 → 上升沿峰值（0.73ms 分辨率）；阈值按 1 秒块内最大值自适应，
    返回 (真实时刻秒, 相对强度 0..1)。用于"只在真的有打击的位置放音符"。"""
    X = np.fft.rfft(x.astype(np.float64))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    y = np.fft.irfft(X * ((f >= lo) & (f < hi)), n=len(x))
    env = np.convolve(np.abs(y), np.ones(64) / 64, mode="same")
    step = 16
    d = np.maximum(0.0, np.diff(env[::step]))
    d = np.convolve(d, np.ones(8) / 8, mode="same")
    blk = int(SR / step)                                 # 1 秒一块
    nb = int(np.ceil(len(d) / blk))
    bmax = np.array([d[i * blk:(i + 1) * blk].max() for i in range(nb)])
    local = np.maximum(np.interp(np.arange(len(d)), np.arange(nb) * blk + blk / 2, bmax), 1e-12)
    floor = np.percentile(d, 90)
    peaks = np.where((d[1:-1] > d[:-2]) & (d[1:-1] >= d[2:]) & (d[1:-1] > 0.3 * local[1:-1])
                     & (d[1:-1] > floor))[0] + 1
    times, strength = [], []
    for i in peaks:
        t = i * step / SR
        if times and t - times[-1] < 0.07:
            if d[i] / local[i] > strength[-1]:
                times[-1], strength[-1] = t, float(d[i] / local[i])
            continue
        times.append(t)
        strength.append(float(min(1.0, d[i] / local[i])))
    return np.array(times), np.array(strength)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--bpm", type=float, default=150.0)
    ap.add_argument("--out", default=str(ROOT / "godot/assets/boss/beat_warden_chart.json"))
    ap.add_argument("--music", default="res://assets/bgm/beat_warden.ogg")
    ap.add_argument("--hp-ratio", type=float, default=0.85,
                    help="Boss 血量 = 单遍可造成伤害 × 该系数；0.85 让打得准的玩家在终段（露核 ×2）完成击杀")
    args = ap.parse_args()
    x = decode(Path(args.audio))
    dur = len(x) / SR
    mag = stft_mag(x)
    fps = SR / HOP
    full, kick, snare = flux(mag, 30, 11000), flux(mag, 40, 150), flux(mag, 1500, 8000)
    bpm, off = refine(full, tempo(full, args.bpm))   # off 在起音包络时间轴上；写谱面时再补 ONSET_LATENCY
    spb = 60.0 / bpm
    # 让第 0 拍 = 第一个小节首拍：在 4 个候选相位里选首拍起音最强的
    beats_total = int((dur - off) / spb)
    def at(env, t):
        return float(np.interp(t * fps, np.arange(len(env)), env))
    down = max(range(4), key=lambda k: sum(at(kick, off + (k + 4 * b) * spb) for b in range(beats_total // 4)))
    off += down * spb
    beats_total = int((dur - off) / spb) - 1
    bars = beats_total // 4
    # 段落：每 4 小节一块的能量
    rms = np.sqrt(np.convolve(x ** 2, np.ones(HOP) / HOP, mode="same")[::HOP] + 1e-12)
    blocks = []
    for b0 in range(0, bars, 4):
        t0, t1 = off + b0 * 4 * spb, off + min(bars, b0 + 4) * 4 * spb
        blocks.append(float(rms[int(t0 * fps):int(t1 * fps)].mean()))
    blocks = np.array(blocks)
    hi, lo = np.percentile(blocks, 65), np.percentile(blocks, 30)
    labels = []
    for i, e in enumerate(blocks):
        if i == 0 or e <= lo:
            labels.append("intro" if i == 0 or labels[-1] == "intro" else "verse")
        elif e >= hi:
            labels.append("drop")
        else:
            labels.append("build" if i + 1 < len(blocks) and blocks[i + 1] >= hi else "verse")
    high = [i for i, l in enumerate(labels) if l == "drop"]
    if high:   # 最后一个高能量连续段 = finale
        k = high[-1]
        while k - 1 in high:
            k -= 1
        for i in range(k, high[-1] + 1):
            labels[i] = "finale"
    sections = []
    for i, l in enumerate(labels):
        if not sections or sections[-1]["name"] != l:
            sections.append({"name": l, "from_beat": i * 16})
    # 音符：只放在真实打击处（用户反馈"有的卡点没做好"：旧版按密度硬凑，45% 音符附近没有鼓点）。
    # 瞬态量化到十六分音符网格（偏差 ≤ 40ms 才算）；底鼓 → 下层，军鼓/镲 → 上层，吉他重音作补充。
    grid0 = off + ONSET_LATENCY                          # 真实时间轴上的第 0 拍
    q = spb / 4.0
    bands = {"kick": transients(x, 40, 120), "snare": transients(x, 1500, 6000),
             "cymbal": transients(x, 6000, 11000), "guitar": transients(x, 200, 1200)}
    # 每首歌自动校准首拍：鼓点瞬态相对网格偏差的中位数（分析窗造成的系统偏移因曲而异）
    devs = []
    for name in ("kick", "snare"):
        for t in bands[name][0]:
            k = int(round((t - grid0) / q))
            if abs(t - (grid0 + k * q)) <= 0.04:
                devs.append(t - (grid0 + k * q))
    if devs:
        grid0 += float(np.median(devs))
    slot_hits: dict[int, dict[str, float]] = {}
    for name, (times, strength) in bands.items():
        for t, st in zip(times, strength):
            k = int(round((t - grid0) / q))
            if k >= 0 and abs(t - (grid0 + k * q)) <= 0.04:
                cur = slot_hits.setdefault(k, {})
                cur[name] = max(cur.get(name, 0.0), st)
    cap = {"intro": 4, "verse": 6, "build": 7, "drop": 8, "finale": 10}
    sixteenth_ok = {"intro": 1.1, "verse": 1.1, "build": 0.9, "drop": 0.7, "finale": 0.45}   # 十六分位所需强度
    notes = []
    last_heavy_bar = -9
    for bar in range(bars):
        sec = labels[min(len(labels) - 1, bar // 4)]
        cands = []
        for e in range(16):
            k = bar * 16 + e
            h = slot_hits.get(k, {})
            if not h:
                continue
            beat = bar * 4 + e / 4.0
            g = h.get("kick", 0.0)
            a = max(h.get("snare", 0.0), h.get("cymbal", 0.0) * 0.9)
            gt = h.get("guitar", 0.0)
            if e % 2 == 1 and max(g, a) < sixteenth_ok[sec]:
                continue                                  # 十六分位只收足够强的打击
            bonus = 0.15 if e % 4 == 0 else 0.05 if e % 2 == 0 else 0.0
            if e == 0 and sec != "intro" and bar - last_heavy_bar >= 2 and g >= 0.55 and h.get("cymbal", 0.0) >= 0.5:
                cands.append((9.0, beat, "dual"))         # 镲 + 底鼓同时砸下的小节首拍 → 双键
                continue
            if g >= 0.35:
                cands.append((g + bonus, beat, "ground"))
            if a >= 0.35:
                cands.append((a + bonus, beat, "air"))
            if g < 0.35 and a < 0.35 and gt >= 0.6:       # 只有吉他重音：按拍位交替上下层
                cands.append((gt * 0.8 + bonus, beat, "ground" if e % 8 < 4 else "air"))
        cands.sort(key=lambda c: -c[0])
        chosen = cands[:cap[sec]]
        for _score, beat, lane in chosen:
            if lane == "dual":
                notes.append({"beat": beat, "lane": "ground", "kind": "heavy"})
                last_heavy_bar = bar
            else:
                notes.append({"beat": beat, "lane": lane, "kind": "normal"})
        if sec in ("drop", "finale") and bar % 2 == 1:
            # 炸弹放在"没有打击"的八分音符空位（不打的东西就放在没声音的地方），上下层交替，同层前后十六分位无音符
            lane = "air" if (bar // 2) % 2 else "ground"
            for e in (14, 10, 6, 2, 15, 11, 7, 3):
                k = bar * 16 + e
                beat = bar * 4 + e / 4.0
                h = slot_hits.get(k, {})
                quiet = max(h.get("kick", 0.0), h.get("snare", 0.0), h.get("cymbal", 0.0)) < 0.3   # 没有鼓点（吉他声不算）
                clear = all(not (n["lane"] == lane and abs(n["beat"] - beat) <= 0.25) and n["beat"] != beat
                            for n in notes if abs(n["beat"] - beat) < 1)
                if quiet and clear:
                    notes.append({"beat": beat, "lane": lane, "kind": "bomb"})
                    break
    # 同层十六分音符连打只保留在 finale；其他段落同层间隔 < 八分音符的去掉较弱的后一个
    notes.sort(key=lambda n: (n["beat"], n["lane"]))
    kept = []
    for n in notes:
        sec = labels[min(len(labels) - 1, int(n["beat"] // 16))]
        prev = next((m for m in reversed(kept) if m["lane"] == n["lane"] or m["kind"] == "heavy"), None)
        if prev and sec != "finale" and n["beat"] - prev["beat"] < 0.5 and n["kind"] == "normal":
            continue
        kept.append(n)
    notes = kept
    # 双键音符：同拍及前后八分音符位的其他音符让位（炸弹除外离得够远）
    heavy_beats = {n["beat"] for n in notes if n["kind"] == "heavy"}
    notes = [n for n in notes if n["kind"] == "heavy" or all(abs(n["beat"] - hb) > 0.5 for hb in heavy_beats)]
    notes.sort(key=lambda n: (n["beat"], n["lane"]))
    drop_from = next((s["from_beat"] for s in sections if s["name"] == "drop"), 0)
    # 循环终点 = 最后一个 finale 块的末尾（不把歌曲收尾的急停段落循环进去）
    finale_blocks = [i for i, l in enumerate(labels) if l == "finale"]
    loop_to = (finale_blocks[-1] + 1) * 16 if finale_blocks else beats_total - (beats_total % 4)
    loop_to = min(loop_to, beats_total - (beats_total % 4))
    damage = sum(3 if n["kind"] == "heavy" else 0 if n["kind"] == "bomb" else 1 for n in notes)
    chart = {"bpm": round(bpm, 3), "offset_sec": round(grid0, 4), "beats_per_bar": 4, "note_speed_px": 520,
             "sections": sections, "notes": notes, "loop_from_beat": drop_from, "loop_to_beat": loop_to,
             "song_seconds": round(dur, 3), "boss_hp": int(round(damage * args.hp_ratio)),
             "note_damage": {"normal": 1, "heavy": 3, "bomb": 0}, "finale_core_multiplier": 2,
             "music": args.music,
             "source": f"tools/audio/chart_from_audio.py 由 {Path(args.audio).name} 自动生成（节拍/段落/音符均来自音频分析）"}
    Path(args.out).write_text(json.dumps(chart, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    kinds = {k: sum(1 for n in notes if n["kind"] == k) for k in ("normal", "heavy", "bomb")}
    print(f"CHART_OK bpm={bpm:.2f} offset={grid0:.3f}s dur={dur:.1f}s beats={beats_total} notes={len(notes)} {kinds} "
          f"boss_hp={chart['boss_hp']} sections={[(s['name'], s['from_beat']) for s in sections]}")


if __name__ == "__main__":
    main()
