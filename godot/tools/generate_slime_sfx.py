from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44_100
OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sfx" / "slime"


def lowpass(signal: np.ndarray, cutoff_hz: float) -> np.ndarray:
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    out = np.empty_like(signal)
    state = 0.0
    for i, value in enumerate(signal):
        state += alpha * (float(value) - state)
        out[i] = state
    return out


def band_noise(rng: np.random.Generator, count: int, low_hz: float, high_hz: float) -> np.ndarray:
    noise = rng.standard_normal(count).astype(np.float64)
    return lowpass(noise, high_hz) - lowpass(noise, low_hz)


def chirp(t: np.ndarray, start_hz: float, end_hz: float, duration: float) -> np.ndarray:
    slope = (end_hz - start_hz) / max(duration, 1e-6)
    phase = 2.0 * np.pi * (start_hz * t + 0.5 * slope * t * t)
    return np.sin(phase)


def add_bubble(track: np.ndarray, when: float, duration: float, start_hz: float,
               end_hz: float, amplitude: float) -> None:
    start = int(when * SAMPLE_RATE)
    count = min(int(duration * SAMPLE_RATE), len(track) - start)
    if count <= 0:
        return
    local_t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    envelope = np.sin(np.pi * np.clip(local_t / duration, 0.0, 1.0)) ** 1.6
    track[start:start + count] += chirp(local_t, start_hz, end_hz, duration) * envelope * amplitude


def finish(track: np.ndarray) -> np.ndarray:
    # 软削波保留湿润瞬态，避免硬截幅产生数字爆音。
    track = np.tanh(track * 1.18)
    fade = min(320, len(track) // 8)
    track[:fade] *= np.linspace(0.0, 1.0, fade)
    track[-fade:] *= np.linspace(1.0, 0.0, fade)
    peak = float(np.max(np.abs(track)))
    if peak > 0.0:
        track = track / peak * 0.93
    return track


def make_hit() -> np.ndarray:
    duration = 0.24
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    rng = np.random.default_rng(9301)
    slap = band_noise(rng, count, 180.0, 2_800.0) * np.exp(-t * 34.0) * 1.25
    wet_body = lowpass(rng.standard_normal(count), 520.0) * np.exp(-t * 11.0) * 0.72
    pitch = 165.0 - 95.0 * np.clip(t / duration, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(pitch) / SAMPLE_RATE
    squelch = np.sin(phase + 0.55 * np.sin(2.0 * np.pi * 31.0 * t)) * np.exp(-t * 15.0) * 0.42
    track = slap + wet_body + squelch
    add_bubble(track, 0.058, 0.055, 310.0, 115.0, 0.22)
    return finish(track)


def make_death() -> np.ndarray:
    duration = 0.68
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count, dtype=np.float64) / SAMPLE_RATE
    rng = np.random.default_rng(9302)
    slap = band_noise(rng, count, 130.0, 3_100.0) * np.exp(-t * 25.0) * 1.45
    viscous = lowpass(rng.standard_normal(count), 430.0) * np.exp(-t * 5.1) * 0.82
    low_pitch = 112.0 - 54.0 * np.clip(t / 0.42, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(low_pitch) / SAMPLE_RATE
    gurgle = np.sin(phase + 1.05 * np.sin(2.0 * np.pi * 17.0 * t)) * np.exp(-t * 5.6) * 0.58
    spray = band_noise(rng, count, 650.0, 5_600.0) * np.exp(-t * 8.5) * 0.34
    track = slap + viscous + gurgle + spray
    add_bubble(track, 0.105, 0.080, 360.0, 105.0, 0.30)
    add_bubble(track, 0.205, 0.095, 275.0, 82.0, 0.25)
    add_bubble(track, 0.355, 0.100, 220.0, 68.0, 0.18)
    add_bubble(track, 0.500, 0.075, 185.0, 62.0, 0.11)
    return finish(track)


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.round(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm.tobytes())
    rms = float(np.sqrt(np.mean(samples * samples)))
    print(f"{path.name}: {len(samples) / SAMPLE_RATE:.3f}s peak={np.max(np.abs(samples)):.3f} rms={rms:.3f}")


def main() -> None:
    write_wav(OUT_DIR / "slime_hit_wet.wav", make_hit())
    write_wav(OUT_DIR / "slime_death_burst.wav", make_death())


if __name__ == "__main__":
    main()
