"""High-quality alarm sound synthesis for Arunoday and Nivaat.

Design goals:
- Arunoday 'dawn bells': warm kalimba/bell tines over a soft sunrise pad,
  D-major pentatonic rising motif, gentle crescendo. Wake like light, not war.
- Nivaat 'court call': bright marimba pluck groove, rhythmic and sporty,
  with a soft wood-tick backbeat. Energetic but not harsh.

Both < 30s (AlarmKit limit), 44.1 kHz 16-bit mono, loop-safe edges,
normalized to -1 dBFS.
"""
import numpy as np
import wave

SR = 44100


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(t, attack, decay, curve=5.0):
    """Pluck envelope: fast attack, exponential decay."""
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-curve * t / decay)


def kalimba(freq, dur=2.6, bright=0.5):
    """Kalimba/music-box tine: inharmonic partials, soft thumb attack."""
    t = t_axis(dur)
    tone = (
        1.00 * np.sin(2 * np.pi * freq * t) * env(t, 0.004, 1.6)
        + 0.45 * bright * np.sin(2 * np.pi * freq * 2.02 * t) * env(t, 0.003, 0.7)
        + 0.18 * bright * np.sin(2 * np.pi * freq * 5.43 * t) * env(t, 0.002, 0.25)
        + 0.06 * np.sin(2 * np.pi * freq * 8.9 * t) * env(t, 0.002, 0.12)
    )
    # subtle detuned double for warmth (chorus)
    tone += 0.35 * np.sin(2 * np.pi * freq * 1.003 * t) * env(t, 0.005, 1.4)
    return tone


def marimba(freq, dur=0.9, punch=1.0):
    """Marimba bar: strong fundamental, 4x partial, brief mallet noise."""
    t = t_axis(dur)
    tone = (
        1.00 * np.sin(2 * np.pi * freq * t) * env(t, 0.003, 0.55)
        + 0.50 * np.sin(2 * np.pi * freq * 3.98 * t) * env(t, 0.002, 0.16)
        + 0.20 * np.sin(2 * np.pi * freq * 9.1 * t) * env(t, 0.002, 0.07)
    )
    noise = np.random.default_rng(int(freq)).standard_normal(len(t))
    tone += 0.05 * punch * noise * env(t, 0.0005, 0.015)
    return tone


def wood_tick(dur=0.12):
    t = t_axis(dur)
    rng = np.random.default_rng(7)
    body = np.sin(2 * np.pi * 1850 * t) + 0.5 * rng.standard_normal(len(t))
    return 0.5 * body * env(t, 0.0005, 0.03)


def pad(freqs, dur, gain=1.0):
    """Slow sunrise pad: detuned sines, very soft attack."""
    t = t_axis(dur)
    out = np.zeros_like(t)
    for f in freqs:
        for det in (0.997, 1.0, 1.004):
            out += np.sin(2 * np.pi * f * det * t + hash((f, det)) % 7)
    out /= 3 * len(freqs)
    swell = np.clip(t / 2.5, 0, 1) * (1 - np.clip((t - (dur - 2.0)) / 2.0, 0, 1))
    return gain * out * swell


def place(canvas, sound, at, gain=1.0):
    i = int(at * SR)
    j = min(i + len(sound), len(canvas))
    canvas[i:j] += gain * sound[: j - i]


def echo(x, delay=0.28, feedback=0.32, taps=3):
    out = x.copy()
    d = int(delay * SR)
    for k in range(1, taps + 1):
        g = feedback ** k
        out[k * d:] += g * x[: len(x) - k * d]
    return out


def finish(x, out_path, crescendo=None):
    if crescendo is not None:
        g0, g1 = crescendo
        x = x * np.linspace(g0, g1, len(x))
    x = echo(x)
    x = x / np.max(np.abs(x)) * 0.891  # -1 dBFS
    # loop-safe edges
    f_in, f_out = int(0.01 * SR), int(0.35 * SR)
    x[:f_in] *= np.linspace(0, 1, f_in)
    x[-f_out:] *= np.linspace(1, 0, f_out)
    pcm = (x * 32767).astype("<i2")
    with wave.open(out_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(out_path, f"{len(x)/SR:.1f}s")


# ---------- Arunoday: dawn bells (D major pentatonic, 24s) ----------
D4, E4, Fs4, A4, B4 = 293.66, 329.63, 369.99, 440.0, 493.88
D5, E5, Fs5, A5, B5, D6 = 587.33, 659.25, 739.99, 880.0, 987.77, 1174.66

dur = 24.0
canvas = np.zeros(int(SR * dur))
place(canvas, pad([D4 / 2, A4 / 2, D4], dur, gain=0.16), 0)

motif = [
    (0.0, D5), (0.7, Fs5), (1.4, A5), (2.1, B5), (2.8, D6),
    (4.2, A5), (4.9, D6),
]
for rep in range(4):  # 4 phrases x 6s
    base = rep * 6.0
    for at, f in motif:
        place(canvas, kalimba(f, bright=0.45 + 0.1 * rep), base + at, gain=0.8)
    place(canvas, kalimba(D4, dur=3.0, bright=0.3), base + 0.0, gain=0.35)

finish(canvas, "arunoday_dawn.wav", crescendo=(0.55, 1.0))

# ---------- Nivaat: court call (A minor pentatonic groove, 16s) ----------
A4n, C5, D5n, E5n, G5, A5n = 440.0, 523.25, 587.33, 659.25, 783.99, 880.0

dur = 16.0
canvas = np.zeros(int(SR * dur))
beat = 60 / 126  # 126 BPM

pattern = [  # (beat, note-or-None tick, gain)
    (0.0, E5n, 1.0), (0.5, None, 0.5), (1.0, G5, 0.9), (1.5, None, 0.5),
    (2.0, A5n, 1.0), (2.5, G5, 0.7), (3.0, E5n, 0.9), (3.5, None, 0.5),
    (4.0, D5n, 0.9), (4.5, None, 0.5), (5.0, E5n, 1.0), (5.5, None, 0.5),
    (6.0, C5, 0.8), (6.5, D5n, 0.7), (7.0, E5n, 1.0), (7.5, None, 0.5),
]
bar_len = 8 * beat
for rep in range(int(dur // bar_len)):
    base = rep * bar_len
    for b, note, g in pattern:
        at = base + b * beat
        if at >= dur - 1.0:
            continue
        if note is None:
            place(canvas, wood_tick(), at, gain=g * 0.6)
        else:
            place(canvas, marimba(note), at, gain=g)
            place(canvas, marimba(note / 2, dur=0.5, punch=0.4), at, gain=0.25)

finish(canvas, "nivaat_ring.wav", crescendo=(0.7, 1.0))
