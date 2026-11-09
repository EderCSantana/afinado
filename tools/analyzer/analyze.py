"""Splits a song into instruments (Demucs) and transcribes each (Basic Pitch).

    python analyze.py <audio file> <output dir>

Writes <output dir>/analysis.json and one WAV per instrument, and prints
progress as JSON lines on stdout: {"progress": 0.4, "message": "..."}.

analysis.json:
    {"duration": 213.4, "sampleRate": 44100,
     "stems": {"vocals": "vocals.wav", ...},
     "parts": [{"stem": "vocals", "notes": [[start, end, midi, amplitude], ...]}]}
"""

import json
import os
import sys
import warnings

warnings.filterwarnings("ignore")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

MODEL = "htdemucs_6s"  # vocals, drums, bass, guitar, piano, other

# Basic Pitch settings per instrument: frequency range (Hz), minimum note
# length (ms) and thresholds. Monophonic instruments get a single line.
SETTINGS = {
    "vocals": dict(min_hz=70, max_hz=1100, min_ms=90, onset=0.5, frame=0.3, mono=True),
    "bass": dict(min_hz=30, max_hz=400, min_ms=90, onset=0.5, frame=0.3, mono=True),
    "guitar": dict(min_hz=70, max_hz=1500, min_ms=60, onset=0.5, frame=0.3, mono=False),
    "piano": dict(min_hz=27, max_hz=4200, min_ms=50, onset=0.5, frame=0.3, mono=False),
    "other": dict(min_hz=60, max_hz=2000, min_ms=80, onset=0.6, frame=0.35, mono=False),
}

# Below this share of the mix's energy a stem is considered absent.
MIN_ENERGY = 0.01


def report(progress, message):
    print(json.dumps({"progress": round(progress, 3), "message": message}), flush=True)


def load(path):
    """Audio as a (channels, samples) float32 array and its sample rate."""
    import numpy as np
    import soundfile as sf

    data, rate = sf.read(path, dtype="float32", always_2d=True)
    return np.ascontiguousarray(data.T), rate


def separate(path, out_dir):
    import numpy as np
    import soundfile as sf
    import torch
    from demucs.apply import apply_model
    from demucs.pretrained import get_model

    report(0.02, "Carregando o modelo de separação…")
    model = get_model(MODEL)
    model.eval()
    wav, rate = load(path)
    if rate != model.samplerate:
        import torchaudio.functional as F

        wav = F.resample(torch.from_numpy(wav), rate, model.samplerate).numpy()
        rate = model.samplerate
    if wav.shape[0] == 1:
        wav = np.concatenate([wav, wav])
    wav = wav[:2]
    duration = wav.shape[1] / rate

    mix = torch.from_numpy(wav)
    ref = mix.mean(0)
    mean, std = ref.mean(), ref.std() + 1e-8
    torch.set_num_threads(max(1, os.cpu_count() or 1))

    report(0.05, "Separando os instrumentos…")
    # Process in chunks to report progress (Demucs splits internally too).
    chunk = int(rate * 30)
    pieces = []
    total = mix.shape[1]
    with torch.no_grad():
        for start in range(0, total, chunk):
            # A little context on each side avoids clicks at the borders.
            pad = int(rate * 2)
            a, b = max(0, start - pad), min(total, start + chunk + pad)
            part = (mix[:, a:b] - mean) / std
            sources = apply_model(model, part[None], device="cpu", split=True, overlap=0.25, progress=False)[0]
            sources = sources * std + mean
            pieces.append(sources[:, :, start - a : start - a + min(chunk, total - start)])
            report(0.05 + 0.6 * min(1, (start + chunk) / total), "Separando os instrumentos…")
    sources = torch.cat(pieces, dim=2).numpy()

    stems = {}
    energy = {}
    mix_energy = float((wav**2).mean()) + 1e-12
    for name, source in zip(model.sources, sources):
        file = f"{name}.wav"
        sf.write(os.path.join(out_dir, file), source.T, rate, subtype="PCM_16")
        stems[name] = file
        energy[name] = float((source**2).mean()) / mix_energy
    return stems, energy, duration, rate


def mono_line(notes):
    """Keeps one note at a time: the loudest of any overlap, cut where the
    next note starts."""
    notes = sorted(notes, key=lambda n: (n[0], -n[3]))
    line = []
    for note in notes:
        if line and note[0] < line[-1][1]:
            last = line[-1]
            if note[0] - last[0] < 0.05:
                # Same onset: keep the louder.
                if note[3] > last[3]:
                    line[-1] = note
                continue
            line[-1] = (last[0], note[0], last[2], last[3])
        line.append(note)
    return [n for n in line if n[1] - n[0] >= 0.06]


def transcribe(out_dir, stems, energy):
    from basic_pitch import ICASSP_2022_MODEL_PATH
    from basic_pitch.inference import Model, predict

    model = Model(ICASSP_2022_MODEL_PATH)
    parts = []
    names = [n for n in SETTINGS if n in stems and energy.get(n, 0) >= MIN_ENERGY]
    for i, name in enumerate(names):
        report(0.67 + 0.3 * i / max(1, len(names)), f"Lendo as notas: {name}…")
        s = SETTINGS[name]
        _, _, events = predict(
            os.path.join(out_dir, stems[name]),
            model,
            onset_threshold=s["onset"],
            frame_threshold=s["frame"],
            minimum_note_length=s["min_ms"],
            minimum_frequency=s["min_hz"],
            maximum_frequency=s["max_hz"],
            melodia_trick=True,
        )
        notes = [(float(e[0]), float(e[1]), int(e[2]), float(e[3])) for e in events]
        if s["mono"]:
            notes = mono_line(notes)
        notes.sort()
        parts.append(
            {
                "stem": name,
                "energy": round(energy[name], 4),
                "notes": [[round(a, 3), round(b, 3), m, round(v, 3)] for a, b, m, v in notes],
            }
        )
    return parts


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    path, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    # The separation takes minutes: keep it, in case transcription fails.
    marker = os.path.join(out_dir, "separation.json")
    if os.path.exists(marker):
        with open(marker, encoding="utf-8") as f:
            saved = json.load(f)
        stems, energy, duration, rate = saved["stems"], saved["energy"], saved["duration"], saved["rate"]
    else:
        stems, energy, duration, rate = separate(path, out_dir)
        with open(marker, "w", encoding="utf-8") as f:
            json.dump({"stems": stems, "energy": energy, "duration": duration, "rate": rate}, f)
    parts = transcribe(out_dir, stems, energy)
    result = {
        "model": MODEL,
        "duration": round(duration, 3),
        "sampleRate": rate,
        "stems": stems,
        "energy": {k: round(v, 4) for k, v in energy.items()},
        "parts": parts,
    }
    # Written last and atomically: its presence means the analysis is done.
    tmp = os.path.join(out_dir, "analysis.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(result, f)
    os.replace(tmp, os.path.join(out_dir, "analysis.json"))
    report(1, "Pronto")


if __name__ == "__main__":
    main()
