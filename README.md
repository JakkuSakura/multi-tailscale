# multi-tailscale

Run a second Tailscale daemon on Linux in a separate network namespace so one machine can reach two tailnets simultaneously. This mirrors the approach described by James Guthrie, but packages it as a single script with systemd units.

## What this does
- Creates a dedicated netns (`tailns`) and veth pair
- Starts a second `tailscaled` inside the netns with separate state/socket
- Routes selected subnets from the second tailnet through the namespace
- Adds NAT and forwarding rules via iptables, nftables, or ufw

## Requirements
- Linux host
- `tailscaled` and `tailscale` installed
- `iproute2`
- One of: `iptables`, `nftables`, or `ufw`
- Root privileges

## Configure
Edit `config.sh`:
- `HOST_IFACE` (your Internet-facing interface)
- `WORK_SUBNETS` (subnets you need via the second tailnet)
- `FIREWALL` (`auto`, `iptables`, `nftables`, `ufw`)
- Optional: veth IPs and namespace name

You can also override the config file path:
```bash
MULTI_TAILNET_CONFIG=/etc/multi-tailnet/config.sh
```

## Usage (manual)
```bash
sudo ./multi-tailnet.sh setup
sudo ./multi-tailnet.sh run
```
In another terminal, log in once:
```bash
sudo ./multi-tailnet.sh login
```

Shortcut (background run):
```bash
sudo ./multi-tailnet.sh up
sudo ./multi-tailnet.sh login
```

To stop and clean up:
```bash
sudo ./multi-tailnet.sh down
```

## systemd (recommended)
Install script + config:
```bash
sudo install -m 0755 multi-tailnet.sh /usr/local/bin/multi-tailnet.sh
sudo install -d /etc/multi-tailnet
sudo install -m 0644 config.sh /etc/multi-tailnet/config.sh
```
Set config path for systemd (drop-in or env):
```bash
sudo systemctl edit multi-tailnet.service
```
Add:
```ini
[Service]
Environment="MULTI_TAILNET_CONFIG=/etc/multi-tailnet/config.sh"
```

Install units:
```bash
sudo install -m 0644 systemd/multi-tailnet-setup.service /etc/systemd/system/multi-tailnet-setup.service
sudo install -m 0644 systemd/multi-tailnet.service /etc/systemd/system/multi-tailnet.service
sudo systemctl daemon-reload
sudo systemctl enable --now multi-tailnet-setup.service
sudo systemctl enable --now multi-tailnet.service
```
Log in once:
```bash
sudo /usr/local/bin/multi-tailnet.sh login
```

## Firewall backends
- `auto` picks `ufw` if active, otherwise `nftables`, otherwise `iptables`.
- `ufw` backend adds route rules and inserts a MASQUERADE rule into `/etc/ufw/before.rules` under a `# multi-tailnet` marker block. It reloads ufw. Review that file if you have custom policies.

## Notes
- This is not an officially supported Tailscale configuration.
- DNS inside the namespace may need manual setup depending on your distro.

## License
MIT
