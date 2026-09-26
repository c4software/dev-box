# shellcheck shell=bash
# devbox dev-env network: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
nmap + tcpdump + iperf3 + mtr + doggo, to scan and debug a network (devbox pkg and mise)

Scan, capture, measure and debug a network. Through `devbox pkg`, put back
after a rebuild: nmap, tcpdump, iperf3, mtr, socat, ethtool and ipcalc (the
mise registry has none of them, the Arch packages work on amd64 and ARM).
Through mise: doggo, a DNS client with a readable output. The image already
has dig, nslookup and host (bind), nc (openbsd-netcat), whois, traceroute,
ping, ip and ss. More in `devbox tui`: trippy, gping, termshark.

The box runs with NET_RAW and NET_ADMIN (Tailscale needs them) and sudo asks
no password, so what wants root works with sudo: `sudo nmap -sS`,
`sudo nmap -O`, `sudo tcpdump -i any`. Without sudo, nmap falls back to a
connect scan (-sT); mtr and ping work as they are.
The box is a container: tcpdump sees its own interfaces only (eth0, lo,
tailscale0), not the traffic of the host or of the LAN, and it reaches the LAN
through the NAT of Docker, so an ARP scan or a MAC address never shows the
real network. For that, a VM or a real machine. A removal takes all of it out
and leaves the image's tools in place.
TXT
}

# Functions rather than arrays: a file runs nothing at the top level.
network_packages() { echo nmap tcpdump iperf3 mtr socat ethtool ipcalc; }

is_installed() { declared doggo && command -v nmap >/dev/null 2>&1; }

install() {
  local packages
  read -ra packages <<<"$(network_packages)"
  dev-box-pkg add "${packages[@]}"
  mise use -g doggo@latest
  log "$(nmap --version | awk 'NR == 1 {print $1, $3}'), doggo $(mise x doggo -- doggo --version 2>&1 | awk 'NR == 1 {print $1}')"
  log "network is ready: nmap -sT 192.168.1.0/24, sudo tcpdump -i any port 80, doggo example.org MX, iperf3 -s"
}

uninstall() {
  local packages
  read -ra packages <<<"$(network_packages)"
  unuse doggo
  dev-box-pkg drop "${packages[@]}"
  log "dig, nc, whois, traceroute, ping, ip and ss stay: they come with the image."
}
