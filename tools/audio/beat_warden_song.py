"""节拍监察官 Boss 战：原创芯片风配乐 + 同源谱面（numpy 合成，幂等，固定随机种子）。

同一份编曲数据同时生成音频与谱面，拍点与音频采样级一致：
  godot/assets/bgm/beat_warden.ogg          单声道 44.1kHz Vorbis（先合成 WAV 临时文件，再用 ffmpeg 编码；无 ffmpeg 时保留 .wav）
  godot/assets/boss/beat_warden_chart.json  谱面（合同见 godot/maps/ENEMY-HOUND-AND-BEAT-BOSS.md §B）

曲式（128 BPM，4/4，A 小调 Am–F–C–G）：
  intro 8 小节 → verse 16 → build 4 → drop 16 → finale 8；Boss 未死时从 drop 循环到曲末。
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OGG_OUT = ROOT / "godot/assets/bgm/beat_warden.ogg"
CHART_OUT = ROOT / "godot/assets/boss/beat_warden_chart.json"
SR = 44100
BPM = 128.0
BEAT = 60.0 / BPM
SECTIONS = [("intro", 8), ("verse", 16), ("build", 4), ("drop", 16), ("finale", 8)]
RNG = np.random.default_rng(128)

# 和弦（根音 MIDI 号）与和弦内音：Am F C G，每和弦 1 小节
PROG = [(45, [57, 60, 64]), (41, [53, 57, 60]), (48, [55, 60, 64]), (43, [55, 59, 62])]
# 主旋律动机（A 小调五声），每项 (相对拍, 时长拍, MIDI)
MOTIF = [(0, 0.5, 76), (0.5, 0.5, 72), (1, 1, 74), (2, 0.5, 69), (2.5, 0.5, 72), (3, 1, 76),
         (4, 0.5, 79), (4.5, 0.5, 76), (5, 1, 74), (6, 1.5, 72), (7.5, 0.5, 69)]


def midi_hz(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def env(n: int, attack: float, decay: float) -> np.ndarray:
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


# ---------------------------------------------------------------- 乐器
def kick() -> np.ndarray:
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.035)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t / 0.16) * 0.95


def snare() -> np.ndarray:
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    noise = RNG.standard_normal(n)
    noise = noise - np.concatenate([[0], noise[:-1]]) * 0.6        # 粗略高通
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    return (noise * np.exp(-t / 0.07) * 0.45 + tone * 0.35)


def hat(open_: bool = False) -> np.ndarray:
    n = int((0.12 if open_ else 0.04) * SR)
    t = np.arange(n) / SR
    noise = RNG.standard_normal(n)
    noise = noise - np.concatenate([[0], noise[:-1]])
    return noise * np.exp(-t / (0.05 if open_ else 0.012)) * 0.16


def square(freq: float, dur: float, duty: float = 0.5, vol: float = 0.2, decay: float = 0.3,
           vibrato: float = 0.0) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.15, 0, 1))
    ph = np.cumsum(f) / SR % 1.0
    w = np.where(ph < duty, 1.0, -1.0)
    # 一阶低通让方波不刺耳
    out = np.empty_like(w)
    acc = 0.0
    k = 0.35
    for i in range(n):
        acc += k * (w[i] - acc)
        out[i] = acc
    return out * env(n, 0.004, decay) * vol


def tri(freq: float, dur: float, vol: float = 0.1) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = t * freq % 1.0
    w = 4 * np.abs(ph - 0.5) - 1
    e = np.clip(t / 0.08, 0, 1) * np.clip((dur - t) / 0.12, 0, 1)
    return w * e * vol


# ---------------------------------------------------------------- 编曲 + 谱面
def main() -> None:
    total_bars = sum(b for _, b in SECTIONS)
    total_beats = total_bars * 4
    track = np.zeros(int((total_beats * BEAT + 2.0) * SR))
    notes: list[dict] = []
    sections_meta = []

    def put(sample: np.ndarray, beat: float) -> None:
        i = int(round(beat * BEAT * SR))
        j = min(len(track), i + len(sample))
        track[i:j] += sample[: j - i]

    def note(beat: float, lane: str, kind: str = "normal") -> None:
        notes.append({"beat": round(beat, 3), "lane": lane, "kind": kind})

    K, S, H, HO = kick(), snare(), hat(), hat(True)
    bar0 = 0
    for name, bars in SECTIONS:
        sections_meta.append({"name": name, "from_beat": bar0 * 4})
        for b in range(bars):
            beat0 = (bar0 + b) * 4
            root, chord = PROG[(bar0 + b) % 4]
            phrase_bar = b % 8
            # ---- 鼓
            for q in range(4):
                if name != "build" or b >= 2:
                    put(K, beat0 + q)
                if name in ("verse", "drop", "finale") and q in (1, 3):
                    put(S, beat0 + q)
                for e in (0, 0.5):
                    if name != "intro" or b >= 2:
                        put(HO if (name == "drop" and e == 0.5) else H, beat0 + q + e)
            if name == "build":                                   # 军鼓渐密滚奏
                step = [1.0, 0.5, 0.25, 0.125][b]
                x = 0.0
                while x < 4:
                    put(S * (0.4 + 0.15 * b), beat0 + x)
                    x += step
            # ---- 贝斯（八分音符，drop 加八度跳）
            for e in range(8):
                oct_ = 12 if (name == "drop" and e % 2) else 0
                if name == "intro" and b < 2:
                    continue
                put(square(midi_hz(root + oct_), BEAT * 0.45, 0.5, 0.16, 0.12), beat0 + e * 0.5)
            # ---- 铺底和弦
            if name in ("verse", "drop", "finale"):
                for m in chord:
                    put(tri(midi_hz(m), BEAT * 4, 0.045), beat0)
            # ---- 主旋律（verse/finale）与琶音（drop）
            if name in ("verse", "finale"):
                for rb, dur, m in MOTIF:
                    if (phrase_bar % 2) * 4 <= rb < (phrase_bar % 2) * 4 + 4:
                        put(square(midi_hz(m), dur * BEAT * 0.9, 0.25, 0.12, 0.35, 0.006), beat0 + rb - (phrase_bar % 2) * 4)
            if name == "drop":
                arp = chord + [chord[0] + 12]
                for s in range(16):
                    put(square(midi_hz(arp[s % 4] + 12), BEAT * 0.22, 0.25, 0.07, 0.08), beat0 + s * 0.25)
            # ---- 谱面（与上面的鼓/旋律同源）
            if name == "intro" and b >= 2:
                note(beat0, "ground")
                note(beat0 + 2, "ground")
            elif name == "verse":
                note(beat0, "ground", "heavy" if b % 4 == 0 else "normal")
                note(beat0 + 1, "air")
                note(beat0 + 2, "ground")
                if b % 2 == 1:
                    note(beat0 + 3, "air")
                    note(beat0 + 3.5, "ground")
            elif name == "build":
                note(beat0, "ground")
                note(beat0 + 2, "ground", "bomb")
                if b >= 2:
                    note(beat0 + 3, "air")
            elif name == "drop":
                pattern = [(0, "ground", "normal"), (0.5, "ground", "normal"), (1, "air", "normal"),
                           (2, "ground", "normal"), (2.5, "air", "bomb"), (3, "ground", "normal"),
                           (3.5, "air", "normal")]
                if b % 4 == 3:
                    pattern = [(0, "ground", "heavy"), (1, "air", "normal"), (1.5, "air", "normal"),
                               (2, "ground", "bomb"), (3, "ground", "normal"), (3, "air", "normal")]
                for off, lane, kind in pattern:
                    note(beat0 + off, lane, kind)
            elif name == "finale":
                for off in (0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5):
                    lane = "ground" if int(off * 2) % 2 == 0 else "air"
                    kind = "heavy" if (off == 0 and b % 2 == 0) else "normal"
                    if b >= 6 and off in (1.5, 3.5):
                        kind = "bomb"
                    note(beat0 + off, lane, kind)
        bar0 += bars

    # 母带：归一化 + 软削波
    peak = np.max(np.abs(track)) or 1.0
    track = np.tanh(track / peak * 1.6) * 0.8
    pcm = (track * 32767).astype(np.int16)
    OGG_OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.gettempdir()) / "beat_warden_master.wav"
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "5",
                        str(OGG_OUT)], check=True)
        tmp.unlink()
    else:
        shutil.move(str(tmp), str(OGG_OUT.with_suffix(".wav")))
        print("WARN ffmpeg 不可用，输出 WAV：", OGG_OUT.with_suffix(".wav"))
    drop_from = next(s["from_beat"] for s in sections_meta if s["name"] == "drop")
    damage = sum(3 if n["kind"] == "heavy" else 0 if n["kind"] == "bomb" else 1 for n in notes)
    chart = {"bpm": BPM, "offset_sec": 0.0, "beats_per_bar": 4, "note_speed_px": 520,
             "sections": sections_meta, "notes": notes, "loop_from_beat": drop_from,
             "loop_to_beat": total_beats, "song_seconds": round(len(pcm) / SR, 3),
             "boss_hp": int(round(damage * 0.62)),
             "note_damage": {"normal": 1, "heavy": 3, "bomb": 0}, "finale_core_multiplier": 2,
             "source": "tools/audio/beat_warden_song.py（原创合成，同源生成音频与谱面）"}
    CHART_OUT.parent.mkdir(parents=True, exist_ok=True)
    CHART_OUT.write_text(json.dumps(chart, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    kinds = {k: sum(1 for n in notes if n["kind"] == k) for k in ("normal", "heavy", "bomb")}
    print(f"SONG_OK {len(pcm) / SR:.1f}s notes={len(notes)} {kinds} boss_hp={chart['boss_hp']} damage_total={damage}")


if __name__ == "__main__":
    main()
