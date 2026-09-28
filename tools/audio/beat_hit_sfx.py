"""节拍 Boss 战统一击打音效（numpy 合成，固定种子，幂等）。

用户反馈旧击打声"怪"：普通音符随机取 hit6/7/8 三个采样，重音符又用另一种金属撞击声，音色忽高忽低。
改为唯一一个清脆的摇滚击打声——军鼓脆响 + 瞬态咔嗒 + 短促音高 + 低频冲击；重音符运行时只降一点音调、加音量。
输出：godot/assets/sfx/beat_hit.wav（44.1kHz 单声道 16-bit，约 0.2s）
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
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    hp = noise - np.concatenate([[0.0], noise[:-1]])            # 一阶高通：让噪声更"脆"
    click = hp * np.exp(-t / 0.0025) * 0.9                       # 瞬态咔嗒
    crack = hp * np.exp(-t / 0.04) * 0.55                        # 军鼓脆响
    f_body = 240 * (1 + 0.6 * np.exp(-t / 0.01))                 # 鼓皮音高快速下滑
    body = np.sin(2 * np.pi * np.cumsum(f_body) / SR) * np.exp(-t / 0.05) * 0.5
    ping = np.sin(2 * np.pi * 1760 * t) * np.exp(-t / 0.025) * 0.18   # 金属泛音，给"击中"的亮点
    f_low = 55 + 45 * np.exp(-t / 0.02)
    thump = np.sin(2 * np.pi * np.cumsum(f_low) / SR) * np.exp(-t / 0.07) * 0.7
    x = click + crack + body + ping + thump
    x = np.tanh(x * 1.4)
    fade = np.clip((n - np.arange(n)) / (0.02 * SR), 0, 1)       # 尾部 20ms 淡出，避免爆音
    x *= fade
    x = x / np.max(np.abs(x)) * 0.89
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("SFX_OK", OUT, f"{n / SR:.2f}s")


if __name__ == "__main__":
    main()
