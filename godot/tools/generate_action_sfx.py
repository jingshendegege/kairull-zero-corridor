"""独立用途音效：只向 action_v1 写入，旧 WAV/MP3 不覆盖。

python godot/tools/generate_action_sfx.py --write --check
python godot/tools/generate_action_sfx.py --preview <项目外的 audition.wav>
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import wave
from pathlib import Path

import numpy as np

# 仅复用低通/带限噪声的通用DSP，不复用史莱姆音频或其音色配方。
from generate_slime_sfx import SAMPLE_RATE, band_noise, chirp, lowpass

OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx" / "action_v1"
VARIANTS = 4
SPECS = {
    "bat_swing": (0.19, -9.0, 2, 2),
    "body_hit": (0.19, -8.0, 4, 3),
    "enemy_kill": (0.34, -7.0, 6, 3),
    "cargo_launch": (0.27, -8.0, 4, 2),
    "cargo_impact": (0.35, -8.0, 5, 3),
    "time_stop_start": (0.42, -8.0, 8, 1),
    "time_stop_end": (0.28, -8.0, 8, 1),
    "rewind": (1.05, -10.0, 10, 1),
    "player_death": (0.60, -6.0, 10, 1),
    "player_hurt": (0.17, -7.0, 7, 2),
    "player_dash": (0.14, -12.0, 2, 2),
    "enemy_shot": (0.19, -12.0, 3, 3),
    "metal_impact": (0.26, -12.0, 2, 2),
    "glass_break": (0.36, -12.0, 3, 2),
    "door_unlock": (0.30, -11.0, 4, 1),
    "checkpoint": (0.53, -11.0, 6, 1),
    "explosion": (0.62, -9.0, 7, 2),
    # 追加到末尾，旧事件的稳定种子编号完全不变。
    "tv_fault": (0.32, -14.0, 9, 1),
}


def pulse(t: np.ndarray, when: float, decay: float, attack: float = 0.001) -> np.ndarray:
    elapsed = np.maximum(t - when, 0.0)
    return (t >= when) * (1.0 - np.exp(-elapsed / attack)) * np.exp(-elapsed / decay)


def make_event(event: str, variant: int) -> np.ndarray:
    event_id = list(SPECS).index(event)
    rng = np.random.default_rng(50905 + event_id * 100 + variant)
    duration = SPECS[event][0] * (0.94 + variant * 0.035)
    t = np.arange(round(duration * SAMPLE_RATE), dtype=np.float64) / SAMPLE_RATE
    n = len(t)
    pitch = 0.91 + variant * 0.06
    low = lowpass(rng.standard_normal(n), 300)
    mid = band_noise(rng, n, 180, 2300)
    high = band_noise(rng, n, 2200, 7800)
    tone = lambda hz: np.sin(2 * np.pi * hz * pitch * t)
    thud = chirp(t, 160 * pitch, 49 * pitch, duration)
    x = np.zeros(n)
    if event == "bat_swing":
        # 短促破风，没有击肉低频或枪械爆点；强拍留给命中事件。
        env = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 2.8
        x = (mid * 0.95 + high * (t / duration) * 0.26) * env
        x += high * pulse(t, duration * 0.68, 0.012) * 0.16
    elif event == "body_hit":
        x = thud * pulse(t, 0, 0.037) * 0.9 + mid * pulse(t, 0, 0.016) * 0.48
        for at in (0.018, 0.039, 0.069):
            x += low * pulse(t, at * rng.uniform(0.85, 1.15), 0.012) * 0.45
    elif event == "enemy_kill":
        # 干脆重击＋装备碎响；无史莱姆咕噜长尾，连杀时仍能辨认每次确认。
        x = chirp(t, 190 * pitch, 42, duration) * pulse(t, 0, 0.064) * 1.0
        x += mid * pulse(t, 0, 0.022) * 0.8
        x += tone(87) * pulse(t, 0.055, 0.052) * 0.35
        for at in (0.022, 0.052, 0.087):
            x += high * pulse(t, at * rng.uniform(0.8, 1.2), 0.005) * 0.14
    elif event == "cargo_launch":
        x = tone(235) * pulse(t, 0, 0.026) * 0.3 + mid * pulse(t, 0, 0.021) * 0.7
        x += (tone(780) + tone(1187) * 0.25) * pulse(t, 0.011, 0.053) * 0.15
        x += mid * np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 2 * 0.19
    elif event == "cargo_impact":
        x = (tone(95) * 0.7 + low * 0.6) * pulse(t, 0, 0.052)
        x += mid * pulse(t, 0, 0.027) * 0.75
        for at in (0.018, 0.058, 0.096, 0.151):
            x += (high * 0.19 + tone(385 + rng.uniform(-80, 80)) * 0.10) * pulse(t, at, 0.017)
    elif event == "time_stop_start":
        env = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 0.85
        x = chirp(t, 890 * pitch, 86, duration) * env * 0.28
        x += mid * env * 0.19 + tone(180) * pulse(t, duration * 0.82, 0.022) * 0.5
    elif event == "time_stop_end":
        x = chirp(t, 135, 1120 * pitch, duration) * np.exp(-t * 11) * 0.3
        x += high * pulse(t, 0.018, 0.058) * 0.4
        x += tone(1060) * pulse(t, 0, 0.012) * 0.25
    elif event == "rewind":
        # 独立倒带机理：反向齿轮节拍＋磁带起伏，不降调复用时停提示音。
        flutter = (0.55 + 0.45 * np.sin(2 * np.pi * (11 * t + 17 * t * t))) ** 4
        env = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 0.55
        x = (mid * 0.2 + tone(155) * 0.12 + tone(311) * 0.06) * flutter * env
        x += chirp(t, 150, 820 * pitch, duration) * env * 0.08
    elif event == "player_death":
        # 玩家倒下：低沉失力＋衣物/落地，不与敌人击杀共享打击确认声。
        x = low * pulse(t, 0, 0.22, 0.018) * 0.8
        x += chirp(t, 96 * pitch, 35, duration) * pulse(t, 0, 0.19) * 0.35
        x += mid * pulse(t, 0.16, 0.068) * 0.2
        x += tone(70) * pulse(t, 0.19, 0.09) * 0.23
    elif event == "player_hurt":
        x = low * pulse(t, 0, 0.048) * 0.9 + tone(130) * pulse(t, 0, 0.037) * 0.5
        x += mid * pulse(t, 0, 0.01) * 0.2
    elif event == "player_dash":
        env = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 1.2
        x = high * env * 0.30 + chirp(t, 1300, 270, duration) * env * 0.05
    elif event == "enemy_shot":
        # 短枪口爆点＋机械枪机；不是肉体命中声，也没有玩家可持枪的含义。
        x = high * pulse(t, 0, 0.013) * 0.8 + mid * pulse(t, 0, 0.027) * 0.75
        x += chirp(t, 170, 66, duration) * pulse(t, 0, 0.023) * 0.7
        x += tone(1290) * pulse(t, 0.042, 0.006) * 0.11
    elif event == "metal_impact":
        for hz, gain in [(430, 0.3), (713, 0.2), (1297, 0.12), (1970, 0.05)]:
            x += tone(hz) * pulse(t, 0, 0.043 + 24 / hz) * gain
        x += high * pulse(t, 0, 0.009) * 0.25
    elif event == "glass_break":
        x = high * pulse(t, 0, 0.028) * 0.65
        for _ in range(12):
            at = rng.uniform(0.006, 0.25)
            x += tone(rng.uniform(1800, 6200)) * pulse(t, at, rng.uniform(0.004, 0.018)) * 0.065
    elif event == "door_unlock":
        x = mid * pulse(t, 0, 0.016) * 0.45 + tone(185) * pulse(t, 0.08, 0.046) * 0.27
        x += (tone(870) * 0.14 + high * 0.07) * pulse(t, 0.11, 0.026)
    elif event == "checkpoint":
        for at, hz in [(0, 440), (0.09, 554.37), (0.18, 659.25)]:
            x += tone(hz) * pulse(t, at, 0.105, 0.008) * 0.17
        x += mid * pulse(t, 0, 0.010) * 0.08
    elif event == "explosion":
        x = low * pulse(t, 0, 0.18) * 1.5 + mid * pulse(t, 0, 0.082) * 0.55
        x += chirp(t, 92, 30, duration) * pulse(t, 0, 0.13) * 0.7
        x += high * pulse(t, 0, 0.018) * 0.18
    elif event == "tv_fault":
        # 短电路噼啪＋同步失锁：带限杂音分段断续，无长高频尖叫或击杀低频冲击。
        crackle = band_noise(rng, n, 220, 2850)
        for at in (0.006, 0.033, 0.073, 0.119, 0.162, 0.211, 0.265):
            when = at * rng.uniform(0.9, 1.06)
            decay = rng.uniform(0.006, 0.016)
            x += crackle * pulse(t, when, decay, 0.0015) * rng.uniform(0.18, 0.38)
            x += tone(rng.uniform(620, 940)) * pulse(t, when, 0.003, 0.0008) * 0.035
        loss_gate = (0.5 + 0.5 * np.sin(2 * np.pi * (15 * t + 31 * t * t))) ** 5
        envelope = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 0.8
        x += (tone(60) * 0.10 + tone(178) * 0.035 + low * 0.08) * loss_gate * envelope
        # 三阶带宽收敛只作用于新故障音，抑制高频尖刺，不改变旧68条音色。
        for _ in range(3):
            x = lowpass(x, 2400)
    else:
        raise ValueError(event)
    # 去直流、温和软限幅，统一留出约3dB峰值空间；首尾短淡化避免切片咔嗒。
    x -= np.mean(x)
    x = np.tanh(x * 1.25)
    fade = min(round(0.003 * SAMPLE_RATE), n // 8)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    x *= 0.70 / max(float(np.max(np.abs(x))), 1e-9)
    return x


def encode_wav(samples: np.ndarray) -> bytes:
    memory = io.BytesIO()
    pcm = np.round(samples * 32767).astype("<i2")
    with wave.open(memory, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(pcm.tobytes())
    return memory.getvalue()


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encode_wav(samples))


def generate(write: bool = True, refresh_events: set[str] | None = None) -> None:
    refresh_events = refresh_events or set()
    manifest = {"version": 1, "sample_rate": SAMPLE_RATE, "events": {}}
    pending = []
    preserved = 0
    refreshed = 0
    for event, (_, gain, priority, cap) in SPECS.items():
        clips = []
        for variant in range(VARIANTS):
            path = OUT / f"{event}_{variant + 1:02d}.wav"
            samples = make_event(event, variant)
            payload = encode_wav(samples)
            if path.exists():
                # 先完成全部旧文件的确定性核对，任何不同都中止，绝不覆盖用户已有音频。
                if path.read_bytes() == payload:
                    preserved += 1
                else:
                    assert event in refresh_events, f"已存在音频与生成结果不同，拒绝覆盖: {path}"
                    pending.append((path, payload))
                    refreshed += 1
            else:
                pending.append((path, payload))
            clips.append({"file": path.name, "duration": len(samples) / SAMPLE_RATE,
                          "peak": float(np.max(np.abs(samples))),
                          "rms": float(np.sqrt(np.mean(samples * samples))),
                          "sha256": hashlib.sha256(payload).hexdigest()})
        manifest["events"][event] = {"gain_db": gain, "priority": priority,
                                     "voice_cap": cap, "clips": clips}
    if write:
        OUT.mkdir(parents=True, exist_ok=True)
        for path, payload in pending:
            path.write_bytes(payload)
        text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
        manifest_path = OUT / "manifest.json"
        if not manifest_path.exists() or manifest_path.read_text(encoding="utf-8") != text:
            manifest_path.write_text(text, encoding="utf-8")
    print(f"AUDIO_{'GENERATE' if write else 'PLAN'} preserved={preserved} "
          f"{'added' if write else 'pending'}={len(pending) - refreshed} refreshed={refreshed}")


def check() -> None:
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    hashes = set()
    total = 0
    for event in SPECS:
        clips = manifest["events"][event]["clips"]
        assert len(clips) == VARIANTS
        for clip in clips:
            path = OUT / clip["file"]
            assert hashlib.sha256(path.read_bytes()).hexdigest() == clip["sha256"]
            assert clip["sha256"] not in hashes, f"音频被跨用途复用: {path.name}"
            hashes.add(clip["sha256"])
            with wave.open(str(path), "rb") as wav:
                assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
                assert wav.getframerate() == SAMPLE_RATE
                samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(float) / 32767
            assert 0.68 <= np.max(np.abs(samples)) <= 0.701
            assert abs(samples[0]) < 1e-4 and abs(samples[-1]) < 1e-4
            assert abs(np.mean(samples)) < 0.008
            if event == "tv_fault":
                assert 0.28 <= len(samples) / SAMPLE_RATE <= 0.36
                energy = np.abs(np.fft.rfft(samples)) ** 2
                frequencies = np.fft.rfftfreq(len(samples), 1 / SAMPLE_RATE)
                assert float(energy[frequencies >= 6000].sum() / energy.sum()) < 0.01
            total += path.stat().st_size
    print(f"AUDIO_CHECK PASS events={len(SPECS)} clips={len(hashes)} bytes={total} MiB={total / 1048576:.3f}")


def preview(path: Path) -> None:
    # 每类两个变体，中间短停顿；完整顺序表与合成文件放项目外，供真正播放听验。
    tracks = []
    timings = []
    cursor = 0.0
    for event in SPECS:
        timings.append({"event": event, "starts_at": round(cursor, 3)})
        for variant in (0, 2):
            sample = make_event(event, variant) * 10 ** (SPECS[event][1] / 20)
            tracks.extend([sample, np.zeros(round(SAMPLE_RATE * 0.20))])
            cursor += len(sample) / SAMPLE_RATE + 0.20
        tracks.append(np.zeros(round(SAMPLE_RATE * 0.40)))
        cursor += 0.40
    write_wav(path, np.concatenate(tracks))
    path.with_suffix(".json").write_text(json.dumps(timings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"AUDITION {path} duration={cursor:.2f}s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--verify-existing", action="store_true", help="只比对已有音频与确定性生成结果，不写文件")
    parser.add_argument("--refresh-event", action="append", choices=list(SPECS), default=[],
                        help="只允许显式指定用途更新已存在音频；其他用途必须逐字节保持不变")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    if args.verify_existing:
        generate(write=False, refresh_events=set(args.refresh_event))
    if args.write:
        generate(refresh_events=set(args.refresh_event))
    if args.check:
        check()
    if args.preview:
        preview(args.preview)
    if not (args.write or args.check or args.preview or args.verify_existing):
        parser.print_help()
