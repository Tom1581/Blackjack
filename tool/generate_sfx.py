#!/usr/bin/env python3
"""Generate the app's sound effects.

These are synthesised rather than sampled so they can be tuned and rebuilt
without hunting for licensed audio. Run:

    python3 tool/generate_sfx.py

Everything is deliberately short, quiet, and clean — UI feedback should be
felt more than heard. If you replace a file by hand, keep the same name and
format (44.1 kHz, 16-bit mono WAV) and the app picks it up unchanged.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def envelope(n, attack=0.004, decay=None, tau=0.12):
    """Short linear attack into an exponential decay, so nothing clicks."""
    a = max(1, int(attack * RATE))
    out = []
    for i in range(n):
        t = i / RATE
        amp = math.exp(-t / tau)
        if i < a:
            amp *= i / a
        if decay is not None and t > decay:
            # Hard fade to silence at the tail so files stay tiny.
            amp *= max(0.0, 1 - (t - decay) / 0.02)
        out.append(amp)
    return out


def sine(freq, n, phase=0.0):
    return [math.sin(2 * math.pi * freq * (i / RATE) + phase) for i in range(n)]


def noise(n, seed=7):
    rng = random.Random(seed)
    return [rng.uniform(-1, 1) for _ in range(n)]


def lowpass(sig, cutoff):
    """One-pole lowpass; cutoff may be a number or a per-sample list."""
    out, prev = [], 0.0
    for i, s in enumerate(sig):
        fc = cutoff[i] if isinstance(cutoff, list) else cutoff
        alpha = 1 - math.exp(-2 * math.pi * fc / RATE)
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def write(name, samples, peak=0.5):
    high = max(abs(s) for s in samples) or 1.0
    scale = peak / high
    frames = b"".join(
        struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples
    )
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(frames)
    print(f"  {name:16} {len(samples)/RATE*1000:5.0f} ms  {len(frames)//1024:3d} KB")


def chime(notes, note_ms=140, tau=0.18, peak=0.5):
    """A short arpeggio: each note a sine plus a quiet octave for sparkle."""
    step = int(note_ms / 1000 * RATE)
    total = step * (len(notes) - 1) + int(0.5 * RATE)
    out = [0.0] * total
    for k, freq in enumerate(notes):
        start = k * step
        n = total - start
        env = envelope(n, tau=tau)
        body = sine(freq, n)
        shimmer = sine(freq * 2, n)
        for i in range(n):
            out[start + i] += env[i] * (body[i] * 0.75 + shimmer[i] * 0.18)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Generating sound effects:")

    # A chip landing on felt: a click with a little body under it.
    n = int(0.09 * RATE)
    env = envelope(n, tau=0.022)
    click = [env[i] * v for i, v in enumerate(lowpass(noise(n, 11), 5200))]
    body = [env[i] * 0.5 * v for i, v in enumerate(sine(1150, n))]
    write("chip.wav", mix(click, body), peak=0.42)

    # A card sliding across the table: filtered noise with the cutoff sweeping
    # down, which reads as a swish rather than a hiss.
    n = int(0.16 * RATE)
    sweep = [7000 - 5200 * (i / n) for i in range(n)]
    env = envelope(n, attack=0.012, tau=0.05)
    card = [env[i] * v for i, v in enumerate(lowpass(noise(n, 23), sweep))]
    write("card.wav", card, peak=0.32)

    # Button: a soft, very short tick.
    n = int(0.045 * RATE)
    env = envelope(n, tau=0.012)
    write("button.wav", [env[i] * v for i, v in enumerate(sine(880, n))], peak=0.3)

    # Win: a rising two-note chime (A4 -> E5).
    write("win.wav", chime([440.0, 659.25]), peak=0.46)

    # Blackjack: brighter three-note arpeggio (A4 -> C#5 -> E5).
    write("blackjack.wav", chime([440.0, 554.37, 659.25], note_ms=120), peak=0.5)

    # Push: one flat, neutral note.
    n = int(0.3 * RATE)
    env = envelope(n, tau=0.1)
    write("push.wav", [env[i] * v for i, v in enumerate(sine(523.25, n))], peak=0.34)

    # Lose: a low note falling away. Quiet on purpose — losing a hand should
    # not be punished with volume.
    n = int(0.34 * RATE)
    env = envelope(n, attack=0.008, tau=0.12)
    drop = [293.66 - 60 * (i / n) for i in range(n)]
    phase, wave_out = 0.0, []
    for i in range(n):
        phase += 2 * math.pi * drop[i] / RATE
        wave_out.append(env[i] * math.sin(phase))
    write("lose.wav", wave_out, peak=0.3)


if __name__ == "__main__":
    main()
