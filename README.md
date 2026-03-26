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
sudo ./mtail setup work
sudo ./mtail run work
```
In another terminal, log in once:
```bash
sudo ./mtail login work
```

Shortcut (background run):
```bash
sudo ./mtail up work
sudo ./mtail login work
```

To stop and clean up:
```bash
sudo ./mtail down work
```

`mtail up/down` run setup/cleanup directly and start/stop the systemd
`mtail@.service` unit. If your host does not use systemd, use the manual
`setup/run/down` commands instead.

## systemd (recommended)
Helper install script:
```bash
sudo ./install.sh
```

`install.sh` installs the CLI, default config, and systemd unit.

### Two equal instances (quickstart)
This runs two independent tailnets (`work` and `personal`) with identical UX.
```bash
sudo ./install.sh
sudo mtail create work
sudo mtail create personal
sudo $EDITOR /etc/multi-tailnet/instances/work.conf
sudo $EDITOR /etc/multi-tailnet/instances/personal.conf

sudo mtail up work
sudo mtail up personal

sudo mtail login work
sudo mtail login personal
```
Status:
```bash
sudo mtail status work
sudo mtail status personal
```
Stop and cleanup per instance:
```bash
sudo mtail down work
sudo mtail down personal
```

## Firewall backends
- `auto` picks `ufw` if active, otherwise `nftables`, otherwise `iptables`.
- `ufw` backend adds route rules and inserts a MASQUERADE rule into `/etc/ufw/before.rules` under a `# mtail` marker block. It reloads ufw. Review that file if you have custom policies.

## Notes
- This is not an officially supported Tailscale configuration.
- DNS inside the namespace may need manual setup depending on your distro.

## License
MIT
