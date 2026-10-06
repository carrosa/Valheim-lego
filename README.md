# Valheim server: setup guide

This kit takes a **fresh Ubuntu 24.04 server** all the way to a running vanilla Valheim server that:

- starts on boot and restarts if it crashes (systemd)
- uses **crossplay mode**, so friends can join behind a university/NAT firewall without port forwarding
- backs up the worlds every day at 04:45 Norwegian time (kept 14 days)
- installs game updates and restarts every night at 05:00 Norwegian time
- turns on the `ufw` firewall with only SSH and Valheim allowed
- keeps Ubuntu itself updated and blocks SSH password guessing (`prepare-server.sh`)

---

## Step 1 – At the server itself (keyboard and screen)

On a fresh install you need to type a few commands at the server's own keyboard and screen. After this you can do everything from your PC.

1. Log in with the user you created when you installed Ubuntu.
2. Make sure the SSH server is installed (it's a tick box in the Ubuntu installer, so it may be there already):
   ```bash
   sudo apt update && sudo apt install -y openssh-server
   ```
3. Note the server's IP address:
   ```bash
   hostname -I
   ```
   On the university network this address can change, because the network hands it out (DHCP) and you can't safely set a static IP yourself. Your friends never need it, since they join through crossplay. Only you need it, for SSH. You have two options:
   - **Tailscale (recommended).** Run step 4 with `--tailscale`. The server then always answers to the name `valheim` from your PC, at home or on campus, whatever IP it has. It's free for personal use. Install Tailscale on your PC too (`curl -fsSL https://tailscale.com/install.sh | sh`, then `sudo tailscale up`) and log in with the same account.
   - **Ask NTNU IT** to reserve a fixed IP address for the server. They'll want its MAC address, which you can see with `ip link`.

## Step 2 – Create the world with seed `vaoxsr` (on your PC)

The dedicated server has no "seed" option. It reads the seed from a world's `.fwl` file instead, so you create the world in the game once and copy that file over.

1. Start Valheim → **Start Game** → pick any character → **New World**.
2. Name it `Ginnung` and set the seed to **`vaoxsr`**. Then click **Start**.
3. Once you've loaded in, quit to the menu. This makes the game save the file.
4. Find `Ginnung.fwl`:
   - Linux (Steam): `~/.config/unity3d/IronGate/Valheim/worlds_local/`
   - Windows: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local\`

You only need the `.fwl` file. Leave the `.db` file behind, and the server will generate a fresh world from the seed.

## Step 3 – Set up an SSH key and copy the kit (on your PC)

Replace `you` with your server username and `SERVER` with the IP address from step 1.

```bash
# Make a key if you don't have one yet (press Enter to accept the defaults)
[ -f ~/.ssh/id_ed25519.pub ] || ssh-keygen -t ed25519

# Put the key on the server (asks for your server password one last time)
ssh-copy-id you@SERVER

# Copy the kit and the world file
scp -r ~/Programming/valheim-lego  ~/.config/unity3d/IronGate/Valheim/worlds_local/Ginnung.fwl  you@SERVER:~/
```

## Step 4 – Prepare the server

```bash
ssh you@SERVER
cd ~/valheim-lego
sudo bash prepare-server.sh --tailscale   # or without --tailscale
```

With `--tailscale`, the script prints a login link. Open it on your PC and approve the server. From then on, use `ssh you@valheim` instead of the IP.

This installs all updates and sets the timezone to Europe/Oslo. It also turns on automatic security updates, with a reboot at 04:15 when one is needed. It installs fail2ban, which blocks repeated password guessing over SSH, and it switches SSH to key-only login.

**Before you close the window,** open a second terminal and check that `ssh you@SERVER` still works. If the script says a reboot is needed, run `sudo reboot` and log in again.

## Step 5 – Install the Valheim server

```bash
cd ~/valheim-lego
sudo bash install.sh --world-file ~/Ginnung.fwl
```

It asks for a server name and a password. The password must be at least 5 characters and must not contain the server name. The first download takes a few minutes.

## Step 6 – Get the join code

About 1–2 minutes after startup:

```bash
valheim-code
```

## How friends join

In Valheim: **Start Game → pick character → Join Game**. Then either:

- **Search the community list.** Tick **"Show crossplay servers"** and search for the server name. This works even after a restart.
- **Use the join code.** Click **Add server**, enter the 6-digit code, then the password.

> ⚠️ The join code **changes every time the server restarts**, including the nightly 05:00 update. Searching by server name is the easiest option for everyday play. Run `valheim-code` if someone needs the new code.

---

## Everyday commands

| What | Command |
|---|---|
| Status | `systemctl status valheim` |
| Live log | `journalctl -u valheim -f` |
| Join code | `valheim-code` |
| Restart / stop | `sudo systemctl restart valheim` / `sudo systemctl stop valheim` |
| Change name/password | `sudo nano /etc/valheim/valheim.env` → restart |
| Manual backup | `sudo valheim-backup` |
| Update now | `sudo systemctl restart valheim` (updates on every start) |
| List timers | `systemctl list-timers 'valheim*'` |

**Make yourself admin.** Add your SteamID64 (or Xbox `Xbox_…` ID) on its own line to `/srv/valheim/data/adminlist.txt`. Then restart the server. `bannedlist.txt` and `permittedlist.txt` are in the same folder.

**Restore a backup:**

```bash
sudo systemctl stop valheim
sudo tar -xzf /var/backups/valheim/valheim-YYYY-MM-DD_HHMM.tar.gz -C /srv/valheim/data
sudo chown -R valheim:valheim /srv/valheim/data
sudo systemctl start valheim
```

Valheim also keeps its own rolling `.old` and backup copies in `/srv/valheim/data/worlds_local`.

## Where things live

| Path | Contents |
|---|---|
| `/srv/valheim/server` | Game server files (SteamCMD) |
| `/srv/valheim/data/worlds_local` | World saves (`.fwl` + `.db`) |
| `/etc/valheim/valheim.env` | Settings (name, world, password, crossplay) |
| `/var/backups/valheim` | Daily backups |

## Troubleshooting

- **No join code appears / crossplay fails.** Crossplay needs outbound internet access, including UDP. Look for PlayFab errors with `journalctl -u valheim -f`. If the network blocks it, that network's IT team would need to allow it.
- **"Incompatible version".** The client and server are on different versions. Restart the server to pull the update, and make sure your friends' games are updated too.
- **The world was generated with the wrong seed.** The `.fwl` name must match `WORLD_NAME` in `/etc/valheim/valheim.env`, and there must be no `.db` file next to it before the first start.
- **Very slow server.** Valheim needs about 2–4 GB of RAM and a decent CPU for 2–10 players.

> Note: if this server is on the NTNU network, check that running a public game server is allowed under NTNU's IT rules.
