"""节拍 Boss 战统一击打音效（numpy 合成，固定种子，幂等）。

v1（2026-09-28）：军鼓脆响 + 低频冲击，用户反馈"不够清爽"——低频和摇滚底鼓/贝斯混在一起发闷。
v2：只保留高频：瞬态咔嗒 + 短促噪声"啪" + 两个高音泛音"叮"，0.09s，无低频、无饱和失真，
    在重型混音里也能清楚地听到"打中了"。双键音符运行时只略降调、加音量，不换音色。
输出：godot/assets/sfx/beat_hit.wav（44.1kHz 单声道 16-bit）
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/assets/sfx/beat_hit.wav"
SR = 44100


def main() -> None:
    rng = np.random.default_rng(42)
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    hp1 = noise - np.concatenate([[0.0], noise[:-1]])
    hp2 = hp1 - np.concatenate([[0.0], hp1[:-1]])               # 二阶差分：只剩高频
    click = hp2 * np.exp(-t / 0.0015) * 0.5                      # 瞬态咔嗒
    snap = hp1 * np.exp(-t / 0.014) * 0.35                       # 短促"啪"
    ping = (np.sin(2 * np.pi * 3150 * t) * 0.6 + np.sin(2 * np.pi * 4725 * t) * 0.4) * np.exp(-t / 0.016) * 0.45
    body = np.sin(2 * np.pi * 1050 * t) * np.exp(-t / 0.008) * 0.25   # 一点点实感，不进低频
    x = click + snap + ping + body
    fade = np.clip((n - np.arange(n)) / (0.01 * SR), 0, 1)
    x *= fade
    x = x / np.max(np.abs(x)) * 0.89
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("SFX_OK", OUT.name, f"{n / SR:.2f}s")


if __name__ == "__main__":
    main()
