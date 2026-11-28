#!/usr/bin/env bash
# Writes a page with one link per http://<name>.devvm in provision/caddy.sh.
# It is a styled page to open (or set as Safari's homepage) and still a
# Netscape bookmarks file for File → Import From → Bookmarks HTML File.
# Run on the Mac:
#
#   ./make-bookmarks.sh [out-file]   # default ~/Desktop/devvm-bookmarks.html
set -euo pipefail
out="${1:-$HOME/Desktop/devvm-bookmarks.html}"
caddy="$(dirname "$0")/provision/caddy.sh"
{
  cat <<'HEAD'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<META NAME="viewport" CONTENT="width=device-width, initial-scale=1">
<META NAME="color-scheme" CONTENT="light dark">
<TITLE>devvm</TITLE>
<STYLE>
  :root { --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --line: #e3e3e8; --accent: #0071e3; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #161618; --card: #232326; --text: #f5f5f7; --muted: #9a9aa0; --line: #34343a; --accent: #2997ff; }
  }
  body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--text);
    font: 16px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  h1 { max-width: 960px; margin: 0 auto; padding: 72px 24px 8px; font-size: 34px; font-weight: 700; letter-spacing: -0.02em; }
  h1::after { content: "Dev servers in the VM, through Caddy on port 8000"; display: block;
    margin-top: 6px; font-size: 15px; font-weight: 400; letter-spacing: 0; color: var(--muted); }
  dl { max-width: 960px; margin: 0 auto; padding: 24px 24px 72px; display: grid; gap: 14px;
    grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); }
  dt { margin: 0; }
  dl > p { display: none; } /* the bookmarks format's <p>, which would take a grid cell */
  a { display: block; height: 100%; box-sizing: border-box; padding: 18px 20px; border-radius: 14px;
    background: var(--card); border: 1px solid var(--line); color: var(--text); text-decoration: none;
    font-size: 17px; font-weight: 600; transition: transform .15s ease, box-shadow .15s ease, border-color .15s ease; }
  /* The host is an attribute, so the link text stays the bare name the importer uses as the title. */
  a::after { content: attr(data-host); display: block; margin-top: 4px; font: 12px ui-monospace, "SF Mono", Menlo, monospace;
    color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  a:hover { transform: translateY(-2px); border-color: var(--accent); box-shadow: 0 8px 24px rgb(0 0 0 / .08); }
  a:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
  @media (prefers-reduced-motion: reduce) { a { transition: none; } a:hover { transform: none; } }
</STYLE>
<H1>devvm</H1>
<DL><p>
HEAD
  # Names are [a-z0-9-] only, so they need no HTML escaping.
  grep -o 'http://[a-z0-9-]*\.devvm' "$caddy" | sort -u \
    | sed 's#^http://\(.*\)\.devvm$#<DT><A HREF="http://\1.devvm:8000/" DATA-HOST="\1.devvm">\1</A>#'
  echo '</DL><p>'
} > "$out"
echo "Wrote $out"
