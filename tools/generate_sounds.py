"""
Generate clean procedural chess sound effects (move, capture, check) as 16-bit WAV files.
No external dependencies required (uses standard library math and wave).
"""
import os
import wave
import struct
import math

SOUNDS_DIR = r"c:\Dev\RodChessXD\assets\sounds"
os.makedirs(SOUNDS_DIR, exist_ok=True)

SAMPLE_RATE = 44100

def write_wav(filename, samples):
    filepath = os.path.join(SOUNDS_DIR, filename)
    with wave.open(filepath, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        packed = struct.pack(f"<{len(samples)}h", *samples)
        wf.writeframes(packed)
    print(f"Generated {filename}")

def generate_move():
    # Soft wood knock: 80ms, rapid pitch drop from 280Hz to 80Hz with exponential decay
    duration = 0.09
    n_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 55.0)
        freq = 260.0 * math.exp(-t * 30.0) + 70.0
        val = math.sin(2.0 * math.pi * freq * t)
        val += 0.3 * math.sin(4.0 * math.pi * freq * t)
        sample = int(val * env * 24000)
        samples.append(max(-32767, min(32767, sample)))
    write_wav("move.wav", samples)

def generate_capture():
    # Crisp double impact knock: 120ms
    duration = 0.12
    n_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        # primary knock
        env1 = math.exp(-t * 60.0)
        freq1 = 340.0 * math.exp(-t * 40.0) + 90.0
        val1 = math.sin(2.0 * math.pi * freq1 * t)
        
        # secondary click at 25ms
        val2 = 0.0
        if t > 0.025:
            t2 = t - 0.025
            env2 = math.exp(-t2 * 80.0)
            val2 = math.sin(2.0 * math.pi * 520.0 * t2) * env2

        combined = val1 * env1 + val2 * 0.7
        sample = int(combined * 26000)
        samples.append(max(-32767, min(32767, sample)))
    write_wav("capture.wav", samples)

def generate_check():
    # Subtle chime / harmonic ping: 250ms at 880Hz + 1760Hz
    duration = 0.28
    n_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 14.0)
        val = 0.7 * math.sin(2.0 * math.pi * 880.0 * t) + 0.3 * math.sin(2.0 * math.pi * 1760.0 * t)
        sample = int(val * env * 20000)
        samples.append(max(-32767, min(32767, sample)))
    write_wav("check.wav", samples)

if __name__ == "__main__":
    generate_move()
    generate_capture()
    generate_check()
