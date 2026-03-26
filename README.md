# multi-tailscale

Run additional Tailscale daemons on Linux in separate network namespaces so one machine can reach multiple tailnets simultaneously. This mirrors the approach described by James Guthrie, but packages it as a single CLI with systemd units.

## What this does
- Creates a dedicated netns and veth pair per instance
- Starts a separate `tailscaled` inside each netns with its own state/socket
- Routes selected subnets from the tailnet instance through the namespace
- Adds NAT and forwarding rules via iptables, nftables, or ufw
- Optional per-namespace DNS config

## Requirements
- Linux host
- `tailscaled` and `tailscale` installed
- `iproute2`
- One of: `iptables`, `nftables`, or `ufw`
- Root privileges

## Configure
Create instance configs:
- `HOST_IFACE` (your Internet-facing interface)
- `WORK_SUBNETS` (subnets you need via the instance tailnet)
- `FIREWALL` (`auto`, `iptables`, `nftables`, `ufw`)
- `DNS_SERVERS` (optional; if set, writes `/etc/netns/<ns>/resolv.conf`)
- Optional: veth IPs and namespace name

## Usage (manual)
```bash
sudo ./mtail setup --instance work
sudo ./mtail run --instance work
```
In another terminal, log in once:
```bash
sudo ./mtail login --instance work
```

Shortcut (background run):
```bash
sudo ./mtail up --instance work
sudo ./mtail login --instance work
```

To stop and clean up:
```bash
sudo ./mtail down --instance work
```

## systemd (recommended)
Helper install script:
```bash
sudo ./install.sh
```

Or manually:
```bash
sudo install -m 0755 mtail /usr/local/bin/mtail
sudo install -d /etc/multi-tailnet
sudo install -m 0644 config.sh /etc/multi-tailnet/config.sh
```

Install units:
```bash
sudo install -m 0644 systemd/mtail-setup@.service /etc/systemd/system/mtail-setup@.service
sudo install -m 0644 systemd/mtail@.service /etc/systemd/system/mtail@.service
sudo systemctl daemon-reload
```

### Two equal instances (quickstart)
This runs two independent tailnets (`work` and `personal`) with identical UX.
```bash
sudo ./install.sh
sudo cp /etc/multi-tailnet/config.sh /etc/multi-tailnet/instances/work.conf
sudo cp /etc/multi-tailnet/config.sh /etc/multi-tailnet/instances/personal.conf
sudo $EDITOR /etc/multi-tailnet/instances/work.conf
sudo $EDITOR /etc/multi-tailnet/instances/personal.conf

sudo systemctl enable --now mtail-setup@work.service
sudo systemctl enable --now mtail@work.service
sudo systemctl enable --now mtail-setup@personal.service
sudo systemctl enable --now mtail@personal.service

sudo mtail login --instance work
sudo mtail login --instance personal
```
Status:
```bash
tailscale --socket /run/mtail/work/tailscaled.sock status
tailscale --socket /run/mtail/personal/tailscaled.sock status
```
Stop and cleanup per instance:
```bash
sudo systemctl stop mtail@work.service
sudo systemctl stop mtail@personal.service
```

## Firewall backends
- `auto` picks `ufw` if active, otherwise `nftables`, otherwise `iptables`.
- `ufw` backend adds route rules and inserts a MASQUERADE rule into `/etc/ufw/before.rules` under a `# mtail` marker block. It reloads ufw. Review that file if you have custom policies.

## Notes
- This is not an officially supported Tailscale configuration.
- DNS inside the namespace may need manual setup depending on your distro.

## License
MIT
