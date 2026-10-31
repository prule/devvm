# Voiceover

Generates the voiceover for [youtube-script.md](../youtube-script.md): one WAV per timed section, plus `voiceover-full.wav` with all of them joined by a 1 s gap.

```bash
./voiceover.sh --dry-run    # spoken text in out/*.txt, word counts, no audio
./voiceover.sh              # Piper, local and free
```

The first run creates `.venv/` and downloads the Piper voice into `voices/`. Both are gitignored, and so is `out/`. Needs `python3-venv`, which `dev.yaml` installs.

## What it reads

- **Sections:** every `## M:SS — Title (duration)` or `### …` heading in the script.
- **Narration:** the `> ` lines after a `**VO:**` marker. A bare `>` line starts a new paragraph, and the clip gets a 0.6 s pause there.
- **Budget:** the time to the next heading. The report prints each clip's length against it. A clip under budget is normal, because the screen demo fills the rest. A clip marked `over` needs cutting or a slower edit.

Edit the script, not the generated text. Re-run with `--only <word>` to regenerate one section, for example `--only electron`.

## ElevenLabs Studio

```bash
./voiceover.sh --studio
```

This writes [voiceover-elevenlabs.txt](../voiceover-elevenlabs.txt): the whole narration as plain text, with the word list applied, and no headings, timestamps or markup, because Studio reads everything it is given. Paragraphs are separated by blank lines, which Studio turns into natural pauses. Paste it into a new Studio project as one chapter. To regenerate one section, find its opening line in the file; each section starts with the first line of its VO block in the script.

The file is generated, so edit the script and re-run instead of editing it. It is committed so you can paste it without running anything.

## Pronunciation

`pronunciations.tsv` turns code into speakable words: `lima-dev` → "lima dev", `localhost:5173` → "localhost fifty-one seventy-three". The replacements are literal, case-sensitive and applied longest first. When something sounds wrong, check `out/NN-*.txt` to see exactly what the voice read, then add a line.

## Engines

| | Command | Notes |
|---|---|---|
| Piper | `./voiceover.sh` | Default voice `en_US-lessac-medium`. Others: `--voice en_GB-alan-medium`, list at [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices). It reads fast; try `--speed 0.85`. |
| OpenAI | `OPENAI_API_KEY=… ./voiceover.sh --engine openai --voice onyx` | Default model `gpt-4o-mini-tts`. |
| ElevenLabs | `ELEVENLABS_API_KEY=… ./voiceover.sh --engine elevenlabs --voice <voice id>` | Use the voice id of a clone of your own voice. Default model `eleven_multilingual_v2`. |

Only Piper has been run. The OpenAI and ElevenLabs paths are written against their documented REST APIs (raw 24 kHz PCM, wrapped in WAV here) but are untested.

If you upload with a cloned or synthetic voice, check YouTube's altered-content disclosure rules first.
