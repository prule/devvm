"""Generate the voiceover for youtube-script.md, one WAV per section.

Reads every `## M:SS — Title` / `### M:SS — Title` heading and the `> ` lines
under its **VO:** markers, rewrites code terms into speakable words
(pronunciations.tsv), synthesises each section, and reports its length
against the time the script budgets for it (the gap to the next heading).

Engines:
  piper       local, free; the voice model downloads on first use
  openai      needs OPENAI_API_KEY
  elevenlabs  needs ELEVENLABS_API_KEY and --voice <voice id> (e.g. your clone)
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import urllib.request
import wave
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "youtube-script.md"
WORDS = HERE / "pronunciations.tsv"
STUDIO = HERE.parent / "voiceover-elevenlabs.txt"

HEADING = re.compile(r"^#{2,3} (\d+):(\d\d) — (.+?) \(([^)]+)\)\s*$")
PARAGRAPH_GAP_S = 0.6
SECTION_GAP_S = 1.0


@dataclass
class Section:
    start_s: int
    title: str
    budget_s: int
    paragraphs: list[str] = field(default_factory=list)


def parse_duration(text: str) -> int:
    """'2 min 30s' -> 150, '60s' -> 60, '4 min' -> 240."""
    minutes = re.search(r"(\d+)\s*min", text)
    seconds = re.search(r"(\d+)\s*s\b", text)
    return (int(minutes.group(1)) * 60 if minutes else 0) + (int(seconds.group(1)) if seconds else 0)


def parse_script(path: Path) -> list[Section]:
    sections: list[Section] = []
    in_vo = False
    paragraph: list[str] = []

    def flush() -> None:
        if paragraph and sections:
            sections[-1].paragraphs.append(" ".join(paragraph))
        paragraph.clear()

    for line in path.read_text().splitlines():
        if m := HEADING.match(line):
            flush()
            in_vo = False
            sections.append(Section(int(m[1]) * 60 + int(m[2]), m[3], parse_duration(m[4])))
        elif line.strip() == "**VO:**":
            in_vo = True
        elif in_vo and line.startswith(">"):
            text = line[1:].strip()
            if text:
                paragraph.append(text)
            else:
                flush()
        elif in_vo and line.strip():
            flush()
            in_vo = False
    flush()

    # A section's budget is the gap to the next heading; the last keeps its own.
    for this, nxt in zip(sections, sections[1:]):
        this.budget_s = nxt.start_s - this.start_s
    return [s for s in sections if s.paragraphs]


def load_words(path: Path) -> list[tuple[str, str]]:
    pairs = []
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        written, spoken = line.split("\t", 1)
        pairs.append((written, spoken.strip()))
    # Longest first, so `ssh -O exit lima-dev` wins over `lima-dev`.
    return sorted(pairs, key=lambda p: len(p[0]), reverse=True)


def speakable(text: str, words: list[tuple[str, str]]) -> str:
    for written, spoken in words:
        # Whole words only, so `OS` never matches inside `iOS` or `POST`.
        pattern = re.escape(written)
        if written[0].isalnum():
            pattern = r"(?<!\w)" + pattern
        if written[-1].isalnum():
            pattern += r"(?!\w)"
        text = re.sub(pattern, lambda _: spoken, text)
    text = re.sub(r"(\w)_(\w)", r"\1 \2", text)  # node_modules -> node modules
    return re.sub(r"[`*]", "", text)


# --- Engines: each returns (16-bit mono PCM bytes, sample rate) -------------

class Piper:
    def __init__(self, voice: str, speed: float):
        from piper import PiperVoice, SynthesisConfig

        voices = HERE / "voices"
        model = voices / f"{voice}.onnx"
        if not model.exists():
            voices.mkdir(exist_ok=True)
            subprocess.run(
                [sys.executable, "-m", "piper.download_voices", "--data-dir", str(voices), voice],
                check=True,
            )
        self.voice = PiperVoice.load(model)
        self.config = SynthesisConfig(length_scale=1 / speed)

    def __call__(self, text: str) -> tuple[bytes, int]:
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wav:
            self.voice.synthesize_wav(text, wav, syn_config=self.config)
        buf.seek(0)
        with wave.open(buf, "rb") as wav:
            return wav.readframes(wav.getnframes()), wav.getframerate()


def post(url: str, headers: dict, body: dict) -> bytes:
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=300) as res:
        return res.read()


class OpenAI:
    RATE = 24000  # response_format=pcm is 24 kHz 16-bit mono

    def __init__(self, voice: str, speed: float, model: str):
        self.key = os.environ["OPENAI_API_KEY"]
        self.voice, self.speed, self.model = voice, speed, model

    def __call__(self, text: str) -> tuple[bytes, int]:
        body = {"model": self.model, "voice": self.voice, "input": text, "response_format": "pcm", "speed": self.speed}
        pcm = post("https://api.openai.com/v1/audio/speech", {"Authorization": f"Bearer {self.key}"}, body)
        return pcm, self.RATE


class ElevenLabs:
    RATE = 24000

    def __init__(self, voice: str, speed: float, model: str):
        self.key = os.environ["ELEVENLABS_API_KEY"]
        self.voice, self.speed, self.model = voice, speed, model

    def __call__(self, text: str) -> tuple[bytes, int]:
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{self.voice}?output_format=pcm_{self.RATE}"
        body = {"text": text, "model_id": self.model, "voice_settings": {"speed": self.speed}}
        return post(url, {"xi-api-key": self.key}, body), self.RATE


DEFAULTS = {
    "piper": {"voice": "en_US-lessac-medium", "model": None},
    "openai": {"voice": "alloy", "model": "gpt-4o-mini-tts"},
    "elevenlabs": {"voice": None, "model": "eleven_multilingual_v2"},
}


def make_engine(args):
    voice = args.voice or DEFAULTS[args.engine]["voice"]
    model = args.model or DEFAULTS[args.engine]["model"]
    if args.engine == "piper":
        return Piper(voice, args.speed)
    if args.engine == "openai":
        return OpenAI(voice, args.speed, model)
    if not voice:
        sys.exit("elevenlabs needs --voice <voice id>")
    return ElevenLabs(voice, args.speed, model)


# --- Output -----------------------------------------------------------------

def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40]


def silence(seconds: float, rate: int) -> bytes:
    return b"\x00\x00" * int(seconds * rate)


def write_wav(path: Path, pcm: bytes, rate: int) -> None:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(pcm)


def mmss(seconds: float) -> str:
    return f"{int(seconds // 60)}:{seconds % 60:04.1f}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", choices=DEFAULTS, default="piper")
    parser.add_argument("--voice", help="voice name (piper, openai) or voice id (elevenlabs)")
    parser.add_argument("--model", help="model for openai or elevenlabs")
    parser.add_argument("--speed", type=float, default=1.0, help="1.1 = 10%% faster")
    parser.add_argument("--only", help="only sections whose number or title contains this")
    parser.add_argument("--dry-run", action="store_true", help="write the spoken text, synthesise nothing")
    parser.add_argument("--studio", action="store_true",
                        help=f"write {STUDIO.name}, plain narration to paste into ElevenLabs Studio, and exit")
    parser.add_argument("--out", type=Path, default=HERE / "out")
    args = parser.parse_args()

    sections = parse_script(SCRIPT)
    words = load_words(WORDS)

    if args.studio:
        # No headings or markup: Studio reads everything it is given aloud.
        # A blank line between paragraphs gives a natural pause.
        text = "\n\n".join(speakable(p, words) for s in sections for p in s.paragraphs)
        STUDIO.write_text(text + "\n")
        print(f"wrote {STUDIO} ({len(text.split())} words, {len(text)} characters)")
        return

    args.out.mkdir(exist_ok=True)
    engine = None if args.dry_run else make_engine(args)

    full, full_rate = [], None
    total_budget = total_actual = 0.0
    print(f"{'#':>2}  {'section':<44} {'words':>5}  {'budget':>6}  {'actual':>6}  {'diff':>6}")
    for n, section in enumerate(sections, 1):
        name = f"{n:02d}-{slug(section.title)}"
        if args.only and args.only not in name and args.only.lower() not in section.title.lower():
            continue
        spoken = [speakable(p, words) for p in section.paragraphs]
        (args.out / f"{name}.txt").write_text("\n\n".join(spoken) + "\n")
        word_count = sum(len(p.split()) for p in spoken)
        total_budget += section.budget_s

        if engine is None:
            print(f"{n:>2}  {section.title[:44]:<44} {word_count:>5}  {mmss(section.budget_s):>6}")
            continue

        pcm, rate = b"", None
        for i, paragraph in enumerate(spoken):
            audio, rate = engine(paragraph)
            pcm += (silence(PARAGRAPH_GAP_S, rate) if i else b"") + audio
        write_wav(args.out / f"{name}.wav", pcm, rate)

        actual = len(pcm) / 2 / rate
        total_actual += actual
        diff = actual - section.budget_s
        flag = "  over" if diff > 0 else ""
        print(f"{n:>2}  {section.title[:44]:<44} {word_count:>5}  {mmss(section.budget_s):>6}  "
              f"{mmss(actual):>6}  {diff:+6.1f}{flag}")

        if full_rate in (None, rate):
            full.append(pcm)
            full_rate = rate

    if engine is not None and full and not args.only:
        joined = silence(SECTION_GAP_S, full_rate).join(full)
        write_wav(args.out / "voiceover-full.wav", joined, full_rate)
        print(f"\ntotal: budget {mmss(total_budget)}, spoken {mmss(total_actual)} "
              f"(sections only, without the gaps in voiceover-full.wav)")
    print(f"files: {args.out}")


if __name__ == "__main__":
    main()
