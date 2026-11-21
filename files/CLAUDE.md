# User-wide instructions

<!-- Generated from devvm/files/CLAUDE.md on every boot. Edit it there; changes made here are lost on restart. -->

- When linking to an HTML page in a GitHub repo, prepend `https://htmlpreview.github.io/?` to the GitHub URL so the page renders instead of showing its source, e.g. `https://htmlpreview.github.io/?https://github.com/owner/repo/blob/main/page.html`.
- Never bypass a git hook with `--no-verify` (or `-n`) unless the user asks for it. If a hook blocks a commit, such as the betterleaks secret scan, fix the cause; if it looks like a false positive, tell the user and ask before adding a `betterleaks:allow` comment or a `.betterleaksignore` entry.
