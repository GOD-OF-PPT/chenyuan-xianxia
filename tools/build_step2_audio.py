#!/usr/bin/env python3
"""
Step 2 Traditional Chinese Chamber Music & Layered Acoustic Foley SFX Pipeline.
Strictly implements docs/design/22-audio-direction.md:
- Renders multi-track Chinese pentatonic/yayue chamber scores via FluidSynth + MIT-licensed FluidR3_GM.sf2
  real acoustic instrument samples (Koto/Guzheng, Shakuhachi/Dongxiao, Flute/Dizi, Shamisen/Pipa, Viola/Erhu,
  Tubular Bells/Bianzhong, Taiko/Tanggu) with ffmpeg EBU R128 (-14 LUFS) loudness normalization.
- Guarantees exact sample-locked 96 BPM 40.000s stem alignment between bgm_qinglan_calm.ogg and bgm_qinglan_combat.ogg.
- Synthesizes & filters organic acoustic Foley / bronze / jade / paper / elemental SFX in .ogg format.
"""
import json
import math
import os
import struct
import subprocess
import wave
import numpy as np
from scipy import signal

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SF2_PATH = "/usr/share/sounds/sf2/FluidR3_GM.sf2"
SR = 44100


# ===================== Minimal Standard MIDI File Builder =====================
def _vlq(val: int) -> bytes:
    val = max(0, int(val))
    out = [val & 0x7F]
    val >>= 7
    while val > 0:
        out.append((val & 0x7F) | 0x80)
        val >>= 7
    out.reverse()
    return bytes(out)


def write_midi_file(path: str, bpm: float, tracks_events: list[list[tuple[int, bytes]]], tpq: int = 480) -> None:
    """Write Format-1 MIDI file from absolute-tick event lists [(tick, raw_midi_bytes), ...]."""
    tempo_us = int(round(60_000_000.0 / bpm))
    tempo_track = [
        (0, b"\xFF\x51\x03" + tempo_us.to_bytes(3, "big")),
    ]
    all_tracks = [tempo_track] + tracks_events
    chunks = []
    for trk in all_tracks:
        sorted_ev = sorted(trk, key=lambda x: x[0])
        buf = bytearray()
        prev_t = 0
        for tick, msg in sorted_ev:
            dt = max(0, tick - prev_t)
            prev_t = tick
            buf.extend(_vlq(dt))
            buf.extend(msg)
        buf.extend(_vlq(0))
        buf.extend(b"\xFF\x2F\x00")
        chunks.append(b"MTrk" + struct.pack(">I", len(buf)) + bytes(buf))

    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(all_tracks), tpq)
    with open(path, "wb") as fh:
        fh.write(header)
        for ch in chunks:
            fh.write(ch)


def prog_change(ch: int, prog: int) -> bytes:
    return bytes([0xC0 | (ch & 0x0F), prog & 0x7F])


def cc(ch: int, ctrl: int, val: int) -> bytes:
    return bytes([0xB0 | (ch & 0x0F), ctrl & 0x7F, max(0, min(127, int(val)))])


def note_on(ch: int, pitch: int, vel: int) -> bytes:
    return bytes([0x90 | (ch & 0x0F), max(0, min(127, int(pitch))), max(1, min(127, int(vel)))])


def note_off(ch: int, pitch: int) -> bytes:
    return bytes([0x80 | (ch & 0x0F), max(0, min(127, int(pitch))), 0])


def add_note(ev_list: list, ch: int, pitch: int, start_tick: int, dur_tick: int, vel: int = 85) -> None:
    ev_list.append((start_tick, note_on(ch, pitch, vel)))
    ev_list.append((start_tick + max(20, dur_tick), note_off(ch, pitch)))


def render_midi_to_ogg(midi_path: str, ogg_path: str, duration_sec: float, target_lufs: float = -14.5) -> None:
    tmp_wav = midi_path + ".raw.wav"
    subprocess.run(
        ["fluidsynth", "-ni", "-g", "0.85", "-r", str(SR), "-F", tmp_wav, SF2_PATH, midi_path],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # Trim to exact duration_sec with smooth fade-in/out loop boundaries + EBU R128 loudnorm
    fade_out_st = max(0.5, duration_sec - 1.2)
    af_chain = (
        f"atrim=0:{duration_sec:.3f},asetpts=PTS-STARTPTS,"
        f"afade=t=in:st=0:d=0.35,afade=t=out:st={fade_out_st:.3f}:d=1.20,"
        f"loudnorm=I={target_lufs}:TP=-1.5:LRA=11"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-i", tmp_wav, "-af", af_chain, "-c:a", "libvorbis", "-q:a", "5", ogg_path],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if os.path.exists(tmp_wav):
        os.remove(tmp_wav)


def build_music_tracks() -> list[dict]:
    records = []
    tpq = 480  # 1 quarter = 480 ticks, 1 bar (4/4) = 1920 ticks

    # D Yu Pentatonic Minor: D(62), F(65), G(67), A(69), C(72), D5(74), F5(77), G5(79), A5(81)
    # 1. Title Theme: 《问道凡尘》 (72 BPM, 16 bars = 53.33s -> 48.0s solemn Guqin/Koto + Shakuhachi + Chimes)
    t_guqin = [(0, prog_change(0, 107)), (0, cc(0, 91, 105))]
    t_xiao = [(0, prog_change(1, 77)), (0, cc(1, 91, 110)), (0, cc(1, 11, 95))]
    t_cello = [(0, prog_change(2, 42)), (0, cc(2, 91, 95)), (0, cc(2, 7, 72))]
    t_chime = [(0, prog_change(3, 14)), (0, cc(3, 91, 115))]

    prog_roots = [50, 48, 45, 50, 53, 52, 45, 50] * 2  # D3, C3, A2, D3, F3, E3, A2, D3
    arp_offsets = [0, 7, 12, 15, 12, 7, 10, 7]
    melody_phrases = [
        [(0, 74, 3.5), (4, 72, 2.0), (6, 69, 2.0), (8, 67, 3.0), (11, 69, 1.0), (12, 62, 4.0)],
        [(0, 69, 2.5), (3, 72, 1.5), (4, 74, 3.0), (7, 77, 1.0), (8, 76, 2.0), (10, 72, 2.0), (12, 69, 4.0)],
        [(0, 77, 3.0), (3, 76, 1.0), (4, 74, 2.0), (6, 69, 2.0), (8, 67, 2.5), (11, 65, 1.5), (12, 69, 4.0)],
        [(0, 74, 2.0), (2, 77, 2.0), (4, 81, 3.5), (8, 79, 2.0), (10, 74, 2.0), (12, 62, 4.0)],
    ]
    for bar, root in enumerate(prog_roots):
        bt = bar * 4 * tpq
        add_note(t_cello, 2, root - 12, bt, 4 * tpq - 40, 62)
        if bar % 4 == 0:
            add_note(t_chime, 3, root + 12, bt, 3 * tpq, 58)
        for eighth in range(8):
            pitch = root + arp_offsets[eighth]
            add_note(t_guqin, 0, pitch, bt + eighth * (tpq // 2), tpq - 30, 72 if eighth % 2 == 0 else 56)

    for p_idx, phrase in enumerate(melody_phrases):
        base_beat = p_idx * 16
        for beat_off, mpitch, bdur in phrase:
            add_note(t_xiao, 1, mpitch, int((base_beat + beat_off) * tpq), int(bdur * tpq) - 40, 82)

    mid_title = os.path.join(REPO_ROOT, "assets_src/audio/bgm_title_wendao.mid")
    ogg_title = os.path.join(REPO_ROOT, "project/assets/audio/bgm/bgm_title_wendao.ogg")
    write_midi_file(mid_title, 72.0, [t_guqin, t_xiao, t_cello, t_chime], tpq)
    render_midi_to_ogg(mid_title, ogg_title, 48.0, -14.5)
    records.append({
        "path": "project/assets/audio/bgm/bgm_title_wendao.ogg",
        "source_path": "assets_src/audio/bgm_title_wendao.mid",
        "category": "bgm",
        "prompt": "Leitmotif A 《问道凡尘》 (Guqin/Koto + Dongxiao/Shakuhachi + Bronze Chimes + Low Strings, 72 BPM)",
        "refinement": "FluidSynth MIT FluidR3_GM.sf2 acoustic sample rendering + EBU R128 -14.5 LUFS mastering.",
    })

    # 2. Dual-Stem Qinglan Exploration & Combat Pair (EXACT 96.0 BPM, 16 bars = 40.000s sample-locked!)
    # Layer A: Calm_Explore (Dizi + Guzheng + Soft Strings)
    qa_zheng = [(0, prog_change(0, 107)), (0, cc(0, 91, 105))]
    qa_dizi = [(0, prog_change(1, 73)), (0, cc(1, 91, 110))]
    qa_pad = [(0, prog_change(2, 48)), (0, cc(2, 7, 58)), (0, cc(2, 91, 100))]

    # Layer B: Combat_Percussion (Pipa rapid lunzhi + Taiko/Tanggu war drums + Woodblock + Viola tension)
    qb_pipa = [(0, prog_change(3, 106)), (0, cc(3, 91, 75))]
    qb_taiko = [(0, prog_change(4, 116)), (0, cc(4, 91, 80))]
    qb_wood = [(0, prog_change(5, 115))]
    qb_viola = [(0, prog_change(6, 41)), (0, cc(6, 91, 85))]

    q_roots = [52, 55, 57, 50, 52, 55, 50, 57] * 2  # E3, G3, A3, D3 (E Yu / G Gong青岚烟雨调式)
    q_arp = [0, 7, 12, 14, 12, 7, 15, 12]
    pipa_pat = [0, 12, 7, 12, 15, 12, 7, 12, 0, 12, 10, 12, 14, 12, 7, 10]

    for bar, r_note in enumerate(q_roots):
        bt = bar * 4 * tpq
        add_note(qa_pad, 2, r_note, bt, 4 * tpq - 30, 54)
        add_note(qa_pad, 2, r_note + 7, bt, 4 * tpq - 30, 48)
        for e in range(8):
            add_note(qa_zheng, 0, r_note + q_arp[e], bt + e * (tpq // 2), tpq - 20, 68 if e % 2 == 0 else 52)
        if bar % 2 == 0:
            add_note(qa_dizi, 1, r_note + 24, bt, int(1.5 * tpq), 76)
            add_note(qa_dizi, 1, r_note + 22, bt + int(1.5 * tpq), int(1.0 * tpq), 72)
            add_note(qa_dizi, 1, r_note + 19, bt + int(2.5 * tpq), int(1.5 * tpq), 74)
        else:
            add_note(qa_dizi, 1, r_note + 19, bt + tpq // 2, int(2.0 * tpq), 72)
            add_note(qa_dizi, 1, r_note + 17, bt + int(2.5 * tpq), int(1.5 * tpq), 68)

        # Synchronized Combat Layer B on the EXACT same harmonic & rhythmic grid!
        for s16 in range(16):
            st = bt + s16 * (tpq // 4)
            add_note(qb_pipa, 3, r_note + 12 + pipa_pat[s16], st, tpq // 4 - 15, 86 if s16 % 4 == 0 else 66)
        # Tanggu war drum pattern
        for beat_off, d_pitch, d_vel in [(0.0, 40, 105), (0.75, 45, 78), (1.5, 40, 92), (2.0, 47, 88), (2.75, 42, 80), (3.5, 45, 95)]:
            add_note(qb_taiko, 4, d_pitch, bt + int(beat_off * tpq), tpq // 2, d_vel)
        for wb_beat in [1.0, 3.0]:
            add_note(qb_wood, 5, 76, bt + int(wb_beat * tpq), tpq // 4, 78)
        add_note(qb_viola, 6, r_note + 12, bt, 2 * tpq - 30, 74)
        add_note(qb_viola, 6, r_note + 15, bt + 2 * tpq, 2 * tpq - 30, 78)

    mid_calm = os.path.join(REPO_ROOT, "assets_src/audio/bgm_qinglan_calm.mid")
    mid_comb = os.path.join(REPO_ROOT, "assets_src/audio/bgm_qinglan_combat.mid")
    ogg_calm = os.path.join(REPO_ROOT, "project/assets/audio/bgm/bgm_qinglan_calm.ogg")
    ogg_comb = os.path.join(REPO_ROOT, "project/assets/audio/bgm/bgm_qinglan_combat.ogg")
    write_midi_file(mid_calm, 96.0, [qa_zheng, qa_dizi, qa_pad], tpq)
    write_midi_file(mid_comb, 96.0, [qb_pipa, qb_taiko, qb_wood, qb_viola], tpq)
    render_midi_to_ogg(mid_calm, ogg_calm, 40.0, -15.0)
    render_midi_to_ogg(mid_comb, ogg_comb, 40.0, -14.0)
    records.append({
        "path": "project/assets/audio/bgm/bgm_qinglan_calm.ogg",
        "source_path": "assets_src/audio/bgm_qinglan_calm.mid",
        "category": "bgm_stem",
        "prompt": "Qinglan Dual-Stem Layer A 《青岚烟雨·静》 (96.0 BPM exact 40.0s loop, Dizi + Guzheng)",
        "refinement": "Sample-locked 96 BPM stem rendering + -15.0 LUFS normalization.",
    })
    records.append({
        "path": "project/assets/audio/bgm/bgm_qinglan_combat.ogg",
        "source_path": "assets_src/audio/bgm_qinglan_combat.mid",
        "category": "bgm_stem",
        "prompt": "Qinglan Dual-Stem Layer B 《青岚烟雨·战》 (96.0 BPM exact 40.0s loop, Pipa lunzhi + Tanggu war drums)",
        "refinement": "Sample-locked 96 BPM combat stem aligned to Layer A + -14.0 LUFS normalization.",
    })

    # 3. Campfire Night Talk Theme: 《青莲听雨》 (68 BPM warm Harp/Guzheng + Dizi)
    nt_harp = [(0, prog_change(0, 46)), (0, cc(0, 91, 112))]
    nt_flute = [(0, prog_change(1, 73)), (0, cc(1, 91, 115))]
    n_roots = [53, 57, 50, 48, 53, 55, 57, 53] * 2  # F major / D minor warm pentatonic
    for bar, nr in enumerate(n_roots):
        bt = bar * 4 * tpq
        for e in range(8):
            off = [0, 4, 7, 12, 14, 12, 7, 4][e]
            add_note(nt_harp, 0, nr + off, bt + e * (tpq // 2), tpq, 64 if e % 2 == 0 else 50)
        if bar % 2 == 0:
            add_note(nt_flute, 1, nr + 19, bt + tpq, 2 * tpq, 72)
            add_note(nt_flute, 1, nr + 16, bt + 3 * tpq, tpq, 68)
        else:
            add_note(nt_flute, 1, nr + 14, bt, 3 * tpq, 70)

    mid_night = os.path.join(REPO_ROOT, "assets_src/audio/bgm_night_qinglian.mid")
    ogg_night = os.path.join(REPO_ROOT, "project/assets/audio/bgm/bgm_night_qinglian.ogg")
    write_midi_file(mid_night, 68.0, [nt_harp, nt_flute], tpq)
    render_midi_to_ogg(mid_night, ogg_night, 42.0, -15.5)
    records.append({
        "path": "project/assets/audio/bgm/bgm_night_qinglian.ogg",
        "source_path": "assets_src/audio/bgm_night_qinglian.mid",
        "category": "bgm",
        "prompt": "Leitmotif B 《青莲听雨》 campfire & pharmacy gentle melody (68 BPM)",
        "refinement": "FluidSynth acoustic rendering + -15.5 LUFS warm mastering.",
    })

    # 4. Boss Theme: 《腐木狼啸》 (132 BPM intense Pipa + Erhu/Fiddle + Bianzhong + Taiko)
    bs_pipa = [(0, prog_change(0, 106)), (0, cc(0, 91, 85))]
    bs_erhu = [(0, prog_change(1, 110)), (0, cc(1, 91, 95))]
    bs_bell = [(0, prog_change(2, 14)), (0, cc(2, 91, 110))]
    bs_drum = [(0, prog_change(3, 116)), (0, cc(3, 91, 90))]
    bs_bass = [(0, prog_change(4, 43)), (0, cc(4, 7, 92))]

    b_roots = [50, 50, 53, 52, 50, 48, 46, 45] * 3  # 24 bars @ 132 BPM = 43.6s
    for bar, br in enumerate(b_roots):
        bt = bar * 4 * tpq
        add_note(bs_bass, 4, br - 12, bt, 2 * tpq - 20, 92)
        add_note(bs_bass, 4, br - 12, bt + 2 * tpq, 2 * tpq - 20, 92)
        if bar % 4 == 0:
            add_note(bs_bell, 2, br + 12, bt, 2 * tpq, 96)
        for s16 in range(16):
            p_off = [0, 7, 12, 7, 15, 12, 7, 10][s16 % 8]
            add_note(bs_pipa, 0, br + 12 + p_off, bt + s16 * (tpq // 4), tpq // 4 - 10, 95 if s16 % 4 == 0 else 75)
        for db in [0.0, 0.5, 1.0, 1.75, 2.0, 2.5, 3.0, 3.5]:
            add_note(bs_drum, 3, 38 if int(db * 2) % 2 == 0 else 45, bt + int(db * tpq), tpq // 3, 104)
        # Fierce Erhu melody
        add_note(bs_erhu, 1, br + 24, bt, int(1.5 * tpq), 94)
        add_note(bs_erhu, 1, br + 27, bt + int(1.5 * tpq), int(1.0 * tpq), 96)
        add_note(bs_erhu, 1, br + 22, bt + int(2.5 * tpq), int(1.5 * tpq), 92)

    mid_boss = os.path.join(REPO_ROOT, "assets_src/audio/bgm_boss_wolf_king.mid")
    ogg_boss = os.path.join(REPO_ROOT, "project/assets/audio/bgm/bgm_boss_wolf_king.ogg")
    write_midi_file(mid_boss, 132.0, [bs_pipa, bs_erhu, bs_bell, bs_drum, bs_bass], tpq)
    render_midi_to_ogg(mid_boss, ogg_boss, 42.0, -13.8)
    records.append({
        "path": "project/assets/audio/bgm/bgm_boss_wolf_king.ogg",
        "source_path": "assets_src/audio/bgm_boss_wolf_king.mid",
        "category": "bgm",
        "prompt": "Chapter 1 Boss Theme 《腐木狼啸》 (132 BPM Pipa + Erhu + Bianzhong + Tanggu)",
        "refinement": "FluidSynth multi-instrument rendering + -13.8 LUFS mastering.",
    })

    return records


def save_float_to_ogg(samples: np.ndarray, wav_src_path: str, ogg_path: str, peak_db: float = -3.0) -> None:
    peak_lin = 10.0 ** (peak_db / 20.0)
    max_abs = max(1e-5, float(np.max(np.abs(samples))))
    normed = np.clip(samples * (peak_lin / max_abs), -0.99, 0.99)
    pcm16 = (normed * 32767.0).astype(np.int16)
    with wave.open(wav_src_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm16.tobytes())
    subprocess.run(
        ["ffmpeg", "-y", "-i", wav_src_path, "-c:a", "libvorbis", "-q:a", "5", ogg_path],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def modal_bell(freqs: list[float], decays: list[float], dur: float) -> np.ndarray:
    t = np.linspace(0.0, dur, int(SR * dur), endpoint=False)
    out = np.zeros_like(t)
    for f, d in zip(freqs, decays):
        out += np.sin(2.0 * np.pi * f * t) * np.exp(-t * d)
    # Soft strike transient
    rng = np.random.default_rng(7)
    strike = rng.normal(0.0, 0.35, len(t)) * np.exp(-t * 85.0)
    b, a = signal.butter(2, [400 / (SR / 2), 4500 / (SR / 2)], btype="band")
    out += signal.lfilter(b, a, strike)
    return out


def build_ambience_and_sfx() -> list[dict]:
    records = []
    rng = np.random.default_rng(2026)

    # 1. Seamless 20s Qinglan Autumn Rain & Bamboo Wind Ambience
    dur_rain = 20.0
    n_rain = int(SR * dur_rain)
    white = rng.normal(0.0, 1.0, n_rain)
    b_p, a_p = signal.butter(3, [280 / (SR / 2), 4200 / (SR / 2)], btype="band")
    rain_bed = signal.lfilter(b_p, a_p, white) * 0.45
    # Add individual water droplets on eaves/bamboo leaves
    for _ in range(260):
        pos = int(rng.integers(0, n_rain - 2200))
        f_drop = float(rng.uniform(750.0, 2100.0))
        dt = np.linspace(0, 0.045, int(SR * 0.045), endpoint=False)
        drop = np.sin(2.0 * np.pi * f_drop * (1.0 + 0.35 * dt * 12.0) * dt) * np.exp(-dt * 75.0) * float(rng.uniform(0.08, 0.24))
        rain_bed[pos:pos + len(drop)] += drop
    # Crossfade loop seam
    xf = int(SR * 1.5)
    w_in = np.linspace(0.0, 1.0, xf)
    rain_bed[:xf] = rain_bed[:xf] * w_in + rain_bed[-xf:] * (1.0 - w_in)
    rain_src = os.path.join(REPO_ROOT, "assets_src/audio/amb_qinglan_rain.wav")
    rain_ogg = os.path.join(REPO_ROOT, "project/assets/audio/bgm/amb_qinglan_rain.ogg")
    save_float_to_ogg(rain_bed[:-xf], rain_src, rain_ogg, peak_db=-12.0)
    records.append({
        "path": "project/assets/audio/bgm/amb_qinglan_rain.ogg",
        "source_path": "assets_src/audio/amb_qinglan_rain.wav",
        "category": "ambience",
        "prompt": "Qinglan autumn rain & eaves droplets seamless ambience loop",
        "refinement": "Bandpass acoustic rain synthesis + droplet Foley + crossfaded seamless loop.",
    })

    # 2. 22 Tiered Combat, Elemental, Boss & Classical UI Foley SFX
    sfx_defs = []

    # Tier S (0 dB -> -1.2 dB safe ceiling)
    sfx_defs.append((
        "sfx_boss_cast_chime", -1.2,
        modal_bell([523.25, 784.0, 1174.6, 1568.0, 2110.0], [2.2, 2.8, 3.6, 4.5, 6.0], 1.35),
        "Tier S Boss Amber-Gold cast bronze Bianzhong warning chime"
    ))
    t_int = np.linspace(0, 0.55, int(SR * 0.55), endpoint=False)
    shatter = modal_bell([880.0, 1320.0, 1980.0, 2790.0], [9.0, 11.0, 14.0, 18.0], 0.55)
    noise_burst = signal.lfilter(*signal.butter(2, [1200 / (SR / 2), 6800 / (SR / 2)], btype="band"), rng.normal(0, 0.8, len(t_int))) * np.exp(-t_int * 24.0)
    sfx_defs.append(("sfx_interrupt_shatter", -1.2, shatter + noise_burst, "Tier S crisp meridian-seal interrupt shatter"))

    t_wb = np.linspace(0, 1.1, int(SR * 1.1), endpoint=False)
    sub_boom = np.sin(2.0 * np.pi * (95.0 * np.exp(-t_wb * 2.2) + 38.0) * t_wb) * np.exp(-t_wb * 3.5)
    jade_crack = modal_bell([1046.5, 1480.0, 2217.0, 3136.0], [6.0, 8.0, 10.0, 12.0], 1.1) * 0.7
    sfx_defs.append(("sfx_ward_break_thunder", -1.2, sub_boom + jade_crack, "Tier S Five-Element Ward break thunder & jade shatter"))

    t_ult = np.linspace(0, 1.6, int(SR * 1.6), endpoint=False)
    ult_sig = np.zeros_like(t_ult)
    for idx_n, fn in enumerate([587.3, 698.5, 880.0, 1174.6, 1396.9]):
        st = int(idx_n * 0.09 * SR)
        seg = modal_bell([fn, fn * 2.0], [2.4, 3.8], 1.6 - idx_n * 0.09)
        ult_sig[st:st + len(seg)] += seg * 0.5
    sfx_defs.append(("sfx_bond_ult_qinglian", -1.2, ult_sig, "Tier S Dual Bond Ultimate 【青莲引剑】 harmonic sword-lotus resonance"))

    # Tier A (-3 dB): Five Elements + Synergy + Heal + Pill
    t_m = np.linspace(0, 0.45, int(SR * 0.45), endpoint=False)
    whoosh_m = signal.lfilter(*signal.butter(2, [900 / (SR / 2), 5200 / (SR / 2)], btype="band"), rng.normal(0, 0.7, len(t_m))) * np.exp(-t_m * 16.0)
    sfx_defs.append(("sfx_elem_metal", -3.0, modal_bell([987.7, 1480.0, 2489.0], [7.5, 9.5, 13.0], 0.45) + whoosh_m, "Tier A Metal dragon-blade ring"))

    t_wd = np.linspace(0, 0.50, int(SR * 0.50), endpoint=False)
    wood_whip = signal.lfilter(*signal.butter(2, [320 / (SR / 2), 1850 / (SR / 2)], btype="band"), rng.normal(0, 1.0, len(t_wd))) * np.sin(np.pi * np.clip(t_wd * 5.0, 0, 1)) * np.exp(-t_wd * 8.0)
    sfx_defs.append(("sfx_elem_wood", -3.0, wood_whip + modal_bell([392.0, 587.3], [9.0, 12.0], 0.50) * 0.4, "Tier A Wood vine & wind burst"))

    t_wa = np.linspace(0, 0.52, int(SR * 0.52), endpoint=False)
    water_splash = signal.lfilter(*signal.butter(2, [600 / (SR / 2), 4600 / (SR / 2)], btype="band"), rng.normal(0, 0.8, len(t_wa))) * np.exp(-t_wa * 9.5)
    sfx_defs.append(("sfx_elem_water", -3.0, water_splash + modal_bell([1318.5, 1760.0, 2637.0], [8.0, 10.0, 14.0], 0.52) * 0.5, "Tier A Water frost-spring surge"))

    t_fi = np.linspace(0, 0.55, int(SR * 0.55), endpoint=False)
    fire_roar = signal.lfilter(*signal.butter(2, [140 / (SR / 2), 1400 / (SR / 2)], btype="band"), rng.normal(0, 1.2, len(t_fi))) * np.exp(-t_fi * 6.5)
    sfx_defs.append(("sfx_elem_fire", -3.0, fire_roar, "Tier A Fire cinnabar ignition roar"))

    t_ea = np.linspace(0, 0.55, int(SR * 0.55), endpoint=False)
    earth_thud = np.sin(2.0 * np.pi * (120.0 * np.exp(-t_ea * 5.0) + 42.0) * t_ea) * np.exp(-t_ea * 6.0)
    rock_grit = signal.lfilter(*signal.butter(2, [180 / (SR / 2), 950 / (SR / 2)], btype="band"), rng.normal(0, 0.7, len(t_ea))) * np.exp(-t_ea * 10.0)
    sfx_defs.append(("sfx_elem_earth", -3.0, earth_thud + rock_grit, "Tier A Earth boulder cleave impact"))

    syn_bell = modal_bell([587.3, 880.0, 1174.6, 1760.0], [3.5, 4.2, 5.0, 6.5], 0.85)
    syn_fire = np.zeros_like(syn_bell)
    syn_fire[:len(fire_roar)] = fire_roar * 0.55
    sfx_defs.append(("sfx_synergy_burst", -2.5, syn_bell + syn_fire, "Tier A Five-Element Synergy detonation"))
    sfx_defs.append(("sfx_heal_chime", -3.5, modal_bell([659.25, 987.77, 1318.5], [4.0, 5.2, 6.8], 0.65), "Tier A Herbal jade heal chime"))
    sfx_defs.append(("sfx_pill_drink", -3.5, modal_bell([784.0, 1174.6], [7.0, 9.0], 0.40), "Tier A Instant pill uncork & qi breath"))

    # Tier C (-13 dB): Subdued Auto-Attack Slash
    t_aa = np.linspace(0, 0.24, int(SR * 0.24), endpoint=False)
    aa_swish = signal.lfilter(*signal.butter(2, [550 / (SR / 2), 3400 / (SR / 2)], btype="band"), rng.normal(0, 0.8, len(t_aa))) * np.sin(np.pi * (t_aa / 0.24)) * np.exp(-t_aa * 12.0)
    sfx_defs.append(("sfx_auto_slash", -13.0, aa_swish, "Tier C subdued blade swing auto-attack"))

    # Tactical Pause, Exploration & Artifact UI SFX (-6 dB to -9 dB)
    t_pe = np.linspace(0, 0.42, int(SR * 0.42), endpoint=False)
    pause_in = np.sin(2.0 * np.pi * (520.0 * np.exp(-t_pe * 3.2)) * t_pe) * np.exp(-t_pe * 6.5)
    pause_out = np.sin(2.0 * np.pi * (240.0 + 380.0 * t_pe) * t_pe) * np.exp(-t_pe * 7.5)
    sfx_defs.append(("sfx_pause_enter", -6.0, pause_in, "Tactical Pause ink-water submerge"))
    sfx_defs.append(("sfx_pause_exit", -6.0, pause_out, "Tactical Pause clear water ripple resume"))

    sfx_defs.append(("sfx_sword_box_hum", -6.5, modal_bell([440.0, 659.25, 880.0], [1.8, 2.4, 3.2], 1.10), "Broken Jade Sword Box warm jade resonance hum"))
    sfx_defs.append(("sfx_alchemy_fire", -7.0, fire_roar * 0.85, "Alchemy furnace fire adjustment whoosh"))
    sfx_defs.append(("sfx_alchemy_success", -4.5, modal_bell([587.3, 880.0, 1318.5, 1760.0], [2.5, 3.2, 4.0, 5.5], 1.15), "Alchemy cauldron flawless pill chime"))
    sfx_defs.append(("sfx_stele_activate", -5.0, modal_bell([293.66, 440.0, 587.33, 880.0], [1.6, 2.2, 2.8, 3.6], 1.40), "Wayfinding Stele stone-jade harmonic activation"))

    t_pg = np.linspace(0, 0.22, int(SR * 0.22), endpoint=False)
    paper_rustle = signal.lfilter(*signal.butter(2, [1100 / (SR / 2), 6200 / (SR / 2)], btype="band"), rng.normal(0, 0.7, len(t_pg))) * np.sin(np.pi * (t_pg / 0.22)) * np.exp(-t_pg * 9.0)
    sfx_defs.append(("sfx_ui_page_turn", -8.5, paper_rustle, "Aged Xuan-paper codex page turn"))

    sfx_defs.append(("sfx_ui_jade_click", -9.0, modal_bell([1174.6, 1760.0], [22.0, 28.0], 0.14), "Matte jade tile button click"))
    t_st = np.linspace(0, 0.32, int(SR * 0.32), endpoint=False)
    seal_thud = np.sin(2.0 * np.pi * (145.0 * np.exp(-t_st * 8.0) + 55.0) * t_st) * np.exp(-t_st * 11.0)
    sfx_defs.append(("sfx_ui_seal_stamp", -5.0, seal_thud, "Cinnabar stone ink-seal stamp thud"))

    for s_name, pk_db, arr_data, desc in sfx_defs:
        np_arr = np.asarray(arr_data, dtype=np.float64)
        wav_src = os.path.join(REPO_ROOT, f"assets_src/audio/{s_name}.wav")
        ogg_out = os.path.join(REPO_ROOT, f"project/assets/audio/sfx/{s_name}.ogg")
        save_float_to_ogg(np_arr, wav_src, ogg_out, peak_db=pk_db)
        records.append({
            "path": f"project/assets/audio/sfx/{s_name}.ogg",
            "source_path": f"assets_src/audio/{s_name}.wav",
            "category": "sfx",
            "prompt": desc,
            "refinement": f"Modal acoustic resonator & filtered Foley synthesis mastered at {pk_db} dBFS peak.",
        })

    return records


def main() -> None:
    all_audio = []
    all_audio.extend(build_music_tracks())
    all_audio.extend(build_ambience_and_sfx())
    out_meta = os.path.join(REPO_ROOT, "assets_src/audio_build_records.json")
    with open(out_meta, "w", encoding="utf-8") as fh:
        json.dump(all_audio, fh, ensure_ascii=False, indent=2)
    print(f"Step 2 Audio Pipeline complete: {len(all_audio)} BGM/Ambience/SFX assets written.")


if __name__ == "__main__":
    main()
