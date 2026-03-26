# multi-tailscale

Run a second Tailscale daemon on Linux in a separate network namespace so one machine can reach two tailnets simultaneously. This mirrors the approach described by James Guthrie, but packages it as a single script.

## What this does
- Creates a dedicated netns (`tailns`) and veth pair
- Starts a second `tailscaled` inside the netns with separate state/socket
- Routes selected subnets from the second tailnet through the namespace
- Adds NAT and forwarding rules

## Requirements
- Linux host
- `tailscaled` and `tailscale` installed
- `iproute2` and `iptables`
- Root privileges

## Configure
Edit these in `multi-tailnet.sh`:
- `HOST_IFACE` (your Internet-facing interface)
- `WORK_SUBNETS` (subnets you need via the second tailnet)
- Optional: veth IPs and namespace name

## Usage
```bash
sudo ./multi-tailnet.sh up
sudo ./multi-tailnet.sh login
```
Follow the URL and authenticate to the second tailnet.

To stop and clean up:
```bash
sudo ./multi-tailnet.sh down
```

## Notes
- This is not an officially supported Tailscale configuration.
- DNS inside the namespace may need manual setup depending on your distro.

## License
MIT
