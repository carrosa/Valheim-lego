# Valheim server: setup guide

This kit sets up a vanilla Valheim dedicated server on Ubuntu 24.04 that:

- starts on boot and restarts if it crashes (systemd)
- uses **crossplay mode**, so friends can join behind a university/NAT firewall without port forwarding
- backs up the worlds every day at 04:45 Norwegian time (kept 14 days)
- installs game updates and restarts every night at 05:00 Norwegian time
- turns on the `ufw` firewall with only SSH and Valheim allowed

---

## Step 1 – Create the world with seed `vaoxsr` (on your PC)

The dedicated server has no "seed" option. It reads the seed from a world's `.fwl` file instead, so you create the world in the game once and copy that file over.

1. Start Valheim → **Start Game** → pick any character → **New World**.
2. Name it `Ginnung` and set the seed to **`vaoxsr`**. Then click **Start**.
3. Once you've loaded in, quit to the menu. This makes the game save the file.
4. Find `Ginnung.fwl`:
   - Linux (Steam): `~/.config/unity3d/IronGate/Valheim/worlds_local/`
   - Windows: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local\`

You only need the `.fwl` file. Leave the `.db` file behind, and the server will generate a fresh world from the seed.

## Step 2 – Copy the kit to the server

```bash
scp -r ~/Programming/valheim-lego  ~/.config/unity3d/IronGate/Valheim/worlds_local/Ginnung.fwl  you@SERVER:~/
```

## Step 3 – Run the installer (on the server)

```bash
ssh you@SERVER
cd ~/valheim-lego
sudo ./install.sh --world-file ~/Ginnung.fwl
```

It asks for a server name and a password. The password must be at least 5 characters and must not contain the server name. The first download takes a few minutes.

## Step 4 – Get the join code

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
