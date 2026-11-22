#!/bin/bash
# SYSTEM: Caddy, so the Mac reaches each service by name on one port
# (http://hugo.devvm:8000; Caddy listens on 80 in the VM) instead of by port (devvm README, Names for services).
# Caddy runs in the VM, so a route can point at ANY VM port: adding a project
# is one line in the Caddyfile below, with no new portForwards entry. Each
# name also needs a line in the Mac's /etc/hosts; bootstrap.sh adds the ones
# it finds here. Best-effort, like the Hugo step.
set -uo pipefail
command -v caddy > /dev/null \
  || DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends caddy \
  || { echo "! caddy skipped — re-run ./update-vm.sh later"; exit 0; }
cat > /etc/caddy/Caddyfile <<'CADDY'
# One block per name: http://<name>.devvm { reverse_proxy localhost:<port> }
# localhost, not 127.0.0.1: Vite without host: true may listen on ::1 only,
# and Caddy tries both addresses.
# http:// means plain HTTP and no certificates. Edit devvm/provision/caddy.sh, not this file:
# every boot rewrites it.
{
	default_bind 127.0.0.1
}
http://hugo.devvm {
	redir / /pauls-blog/
	reverse_proxy localhost:1313
}
http://sonar.devvm {
	reverse_proxy localhost:9000
}
# Projects: each dev server's port is pinned in its own repo (Vite:
# server.port + strictPort + allowedHosts ['.devvm']).
http://home-fleet.devvm {
	reverse_proxy localhost:5173
}
http://intentionhorizon.devvm {
	reverse_proxy localhost:5181
}
http://rss-reader.devvm {
	reverse_proxy localhost:5182
}
http://strength2.devvm {
	reverse_proxy localhost:5183
}
http://strength.devvm {
	reverse_proxy localhost:5184
}
http://leave-planner.devvm {
	reverse_proxy localhost:5185
}
http://rubikscube.devvm {
	reverse_proxy localhost:5186
}
http://video-aggregator.devvm {
	reverse_proxy localhost:5200
}
http://portfolio.devvm {
	reverse_proxy localhost:8789
}
CADDY
caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile > /dev/null 2>&1 \
  || { echo "! Caddyfile invalid — run: caddy validate --config /etc/caddy/Caddyfile"; exit 0; }
systemctl enable caddy
systemctl restart caddy || echo "! caddy did not start — see: systemctl status caddy"
