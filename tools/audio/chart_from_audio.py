"""从任意成品音频（如 Suno 生成的摇滚曲）自动生成节拍 Boss 谱面（numpy + ffmpeg，无需 librosa）。

用法：python chart_from_audio.py <音频文件> [--bpm 150] [--out godot/assets/boss/beat_warden_chart.json]
流程：
  1. ffmpeg 解码为 22050Hz 单声道 → STFT。
  2. 分频段谱通量：低频（底鼓，40–150Hz）、中高频（军鼓/镲，1.5–8kHz）、全频能量。
  3. 速度：全频起音包络自相关，在 --bpm 附近（±15%）找峰；相位：按拍网格累加起音强度取最大。
  4. 段落：每 4 小节的 RMS 能量排序 → 低能量=intro/verse，渐强=build，高能量=drop，最后一段高能量=finale。
  5. 音符：八分音符网格上，底鼓强 → ground，军鼓/镲强 → air，二者都强 → 同拍双音符（仅 drop/finale）；
     每小节首拍最强起音 → heavy；drop/finale 的空拍按固定图样放 bomb（与前后音符留出换层时间）。
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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--bpm", type=float, default=150.0)
    ap.add_argument("--out", default=str(ROOT / "godot/assets/boss/beat_warden_chart.json"))
    ap.add_argument("--music", default="res://assets/bgm/beat_warden.ogg")
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
    # 音符：每小节 8 个八分音符位，按段落目标密度挑起音最强的位置（拍点加权），底鼓→下层，军鼓/镲→上层
    density = {"intro": 3, "verse": 5, "build": 6, "drop": 7, "finale": 8}
    notes = []
    for bar in range(bars):
        sec = labels[min(len(labels) - 1, bar // 4)]
        dense = sec in ("drop", "finale")
        slots = []
        for e in range(8):
            beat = bar * 4 + e / 2.0
            t = off + beat * spb
            bonus = 0.12 if e % 2 == 0 else 0.0
            slots.append((beat, at(kick, t) + bonus, at(snare, t) + bonus))
        want = density[sec]
        n_ground = (want + 1) // 2
        ground = sorted(slots, key=lambda v: -v[1])[:n_ground]
        ground = [v for v in ground if v[1] > 0.18]
        taken = {v[0] for v in ground}
        air_pool = [v for v in slots if dense or v[0] not in taken]
        air = [v for v in sorted(air_pool, key=lambda v: -v[2])[:want - len(ground)] if v[2] > 0.18]
        strongest = max(slots[0][1], 0.0)
        for beat, k, _s in ground:
            heavy = beat == bar * 4 and sec != "intro" and strongest >= 0.75 and bar % 2 == 0
            notes.append({"beat": beat, "lane": "ground", "kind": "heavy" if heavy else "normal"})
        for beat, _k, _s2 in air:
            notes.append({"beat": beat, "lane": "air", "kind": "normal"})
        if dense and bar % 2 == 1:
            # 每两小节在第 4 拍反拍放一颗炸弹（上下层交替），并清掉该层前后八分音符位的音符，给换层留时间
            beat = bar * 4 + 3.5
            lane = "air" if (bar // 2) % 2 else "ground"
            notes = [n for n in notes if not (n["lane"] == lane and abs(n["beat"] - beat) <= 0.5)]
            notes.append({"beat": beat, "lane": lane, "kind": "bomb"})
    notes.sort(key=lambda n: (n["beat"], n["lane"]))
    finale_from = next((s["from_beat"] for s in sections if s["name"] == "finale"), beats_total)
    drop_from = next((s["from_beat"] for s in sections if s["name"] == "drop"), 0)
    loop_to = beats_total - (beats_total % 4)
    damage = sum(3 if n["kind"] == "heavy" else 0 if n["kind"] == "bomb" else 1 for n in notes)
    chart = {"bpm": round(bpm, 3), "offset_sec": round(off + ONSET_LATENCY, 4), "beats_per_bar": 4, "note_speed_px": 520,
             "sections": sections, "notes": notes, "loop_from_beat": drop_from, "loop_to_beat": loop_to,
             "song_seconds": round(dur, 3), "boss_hp": int(round(damage * 0.62)),
             "note_damage": {"normal": 1, "heavy": 3, "bomb": 0}, "finale_core_multiplier": 2,
             "music": args.music,
             "source": f"tools/audio/chart_from_audio.py 由 {Path(args.audio).name} 自动生成（节拍/段落/音符均来自音频分析）"}
    Path(args.out).write_text(json.dumps(chart, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    kinds = {k: sum(1 for n in notes if n["kind"] == k) for k in ("normal", "heavy", "bomb")}
    print(f"CHART_OK bpm={bpm:.2f} offset={off + ONSET_LATENCY:.3f}s dur={dur:.1f}s beats={beats_total} notes={len(notes)} {kinds} "
          f"boss_hp={chart['boss_hp']} sections={[(s['name'], s['from_beat']) for s in sections]}")


if __name__ == "__main__":
    main()
