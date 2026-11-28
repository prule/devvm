#!/usr/bin/env bash
# Writes a bookmarks file with one link per http://<name>.devvm in
# provision/caddy.sh, for Safari's File → Import From → Bookmarks HTML File.
# Run on the Mac:
#
#   ./make-bookmarks.sh [out-file]   # default ~/Desktop/devvm-bookmarks.html
set -euo pipefail
out="${1:-$HOME/Desktop/devvm-bookmarks.html}"
caddy="$(dirname "$0")/provision/caddy.sh"
{
  echo '<!DOCTYPE NETSCAPE-Bookmark-file-1>'
  echo '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">'
  echo '<DL><p>'
  # Names are [a-z0-9-] only, so they need no HTML escaping.
  grep -o 'http://[a-z0-9-]*\.devvm' "$caddy" | sort -u \
    | sed 's#^http://\(.*\)\.devvm$#<DT><A HREF="http://\1.devvm:8000/">\1</A>#'
  echo '</DL><p>'
} > "$out"
echo "Wrote $out"
