<div align="center">

# 🎵 PrivateTunes

**Your private, self-hosted music streaming server with a pure CLI download workflow.**

No VM. No GUI desktop app. Just your music, your server, your rules.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Navidrome](https://img.shields.io/badge/Powered%20by-Navidrome-00C9FF)](https://www.navidrome.org/)
[![Author](https://img.shields.io/badge/by-%40Paidguy-blueviolet)](https://github.com/Paidguy)

**Created and maintained by [@Paidguy](https://github.com/Paidguy)**

</div>

---

## What is PrivateTunes?

PrivateTunes runs a personal music server ([Navidrome](https://www.navidrome.org/)) behind [Caddy](https://caddyserver.com/) (automatic HTTPS), backed by a `./music` folder you control.

For music acquisition, it integrates [`spotiflac-cli`](https://github.com/Superredstone/spotiflac-cli) and provides a beautiful interactive menu (`scripts/privatetunes.sh`) to download music directly into your library — including batch downloads from a link list.

## Architecture

| Service | Role |
|---|---|
| **Caddy** | Reverse proxy + automatic TLS certificates |
| **Navidrome** | Music server with Subsonic API + web player |
| **Syncthing** *(optional)* | Sync your `./music` folder across devices |
| **spotiflac-cli** | CLI downloader (runs on the host, saves into `./music`) |

## Prerequisites

- **Linux server** (Ubuntu/Debian recommended)
- **Docker** + Docker Compose plugin (`docker compose`)
- **Ports**: `80` and `443` exposed (for HTTPS)
- **A domain** pointing to the server (DuckDNS works well — it's free)

## Quick Start

```bash
git clone https://github.com/Paidguy/PrivateTunes.git
cd PrivateTunes

# Full automated setup:
#   → Installs Docker Engine + Docker Compose plugin (if missing)
#   → Installs system dependencies (curl, ca-certificates, git, gnupg)
#   → Creates required directories (music/, data/navidrome/, data/syncthing/)
#   → Downloads spotiflac-cli into ./bin/
#   → Copies .env.example → .env and runs the domain wizard
#   → Starts the Docker stack
#   → Waits for Navidrome to be healthy
chmod +x scripts/setup.sh scripts/privatetunes.sh
sudo ./scripts/setup.sh

# Then use the interactive menu to download music & manage everything:
./scripts/privatetunes.sh
```

## Downloading Music (CLI Menu)

Run:

```bash
./scripts/privatetunes.sh
```

### Menu Actions

| Key | Action | Description |
|-----|--------|-------------|
| `s` | **Full Setup** | Runs `setup.sh` end-to-end (Docker + deps + stack start) |
| `1` | **Install/Update spotiflac-cli** | Download the latest binary |
| `2` | **Download from Spotify URL** | Paste a track/album/playlist URL → downloads as FLAC into `./music` |
| `3` | **View track metadata** | Inspect metadata for any Spotify track URL |
| `b` | **Batch download** | Download all URLs listed in `links.txt` — skips already-downloaded |
| `d` | **Download history** | View, clear, or retry tracked downloads |
| `4` | **Start stack** | `docker compose up -d` + waits for health checks |
| `5` | **Stop stack** | `docker compose down` |
| `6` | **View logs** | Follow live logs from all containers |
| `7` | **Stack status** | Health checks for Navidrome & Syncthing + disk usage |
| `8` | **Restart Navidrome** | Restart only the Navidrome container |
| `9` | **Domain setup wizard** | Configure DOMAIN, UID, GID in `.env` |
| `c` | **Backup config** | Archive `.env` + `Caddyfile` + `docker-compose.yml` |
| `p` | **Show paths / .env** | Display all important paths and current config |
| `h` | **Help** | Detailed help screen |
| `0` | **Exit** | Quit the menu |

## Configuration

Create your `.env` file:

```bash
cp .env.example .env
```

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN` | Your domain name | `your-domain.duckdns.org` |
| `UID` | User ID for Syncthing | `1000` |
| `GID` | Group ID for Syncthing | `1000` |

## Download History & Fault Tolerance

PrivateTunes tracks every download in a persistent JSON database (`data/download_history.json`). This means:

- **No duplicate downloads** — If a track/album/playlist was already downloaded, it's automatically skipped
- **Resume interrupted batches** — If a batch download is interrupted (rate limits, crash, network error), re-running it picks up exactly where you left off
- **Exponential backoff retries** — Failed downloads are retried up to 3 times with increasing wait times (5s → 15s → 45s), with extended waits for rate limits
- **Atomic progress tracking** — Each successful download is recorded immediately, so even a hard crash preserves all progress
- **URL normalization** — The same track won't be re-downloaded even if the URL has different tracking parameters (`?si=...`)

### Managing History

Use menu option `d` to:
- View download statistics and recent downloads
- Clear failed entries (so they get retried on next batch)
- Clear all history (to force re-downloading everything)

The history file is stored at `data/download_history.json` and is git-ignored.

> **Note:** `jq` is recommended for the best history experience. Without `jq`, a simpler line-based log fallback is used.

## File Structure

```
PrivateTunes/
├── Caddyfile              # Caddy reverse proxy config
├── Caddyfile.example      # Template Caddyfile
├── docker-compose.yml     # Docker stack definition
├── .env.example           # Environment template
├── links.txt              # Batch download URLs (one per line)
├── music/                 # Your music library (Navidrome reads from here)
├── data/                  # Navidrome + Syncthing persistent state
│   └── download_history.json  # Download tracking database (auto-created)
├── bin/                   # Local tools like spotiflac-cli (git-ignored)
└── scripts/
    ├── setup.sh           # Host bootstrap wizard
    └── privatetunes.sh    # Interactive CLI menu
```

## Updating

```bash
# Update containers to latest versions
docker compose pull
docker compose up -d

# Update spotiflac-cli (via menu)
./scripts/privatetunes.sh
# → Select option [1]
```

## Troubleshooting

### Music not appearing in Navidrome

- Verify files are in `./music/`
- Restart Navidrome or trigger a scan in the UI:

```bash
docker compose restart navidrome
```

### Caddy / SSL Issues

```bash
docker compose logs -f caddy
```

Make sure:
- `DOMAIN` in `.env` is correct
- Ports `80/443` are reachable publicly
- Your DNS A/AAAA record points to the server

### Container Issues

```bash
# View all logs
docker compose logs -f

# Check health status
docker compose ps
```

---

## Credits

**PrivateTunes** is created and maintained by **[@Paidguy](https://github.com/Paidguy)**.

## License & Disclaimer

This project is for **personal use with legally obtained content**. You are responsible for compliance with local laws and the terms of services you use.

Licensed under the MIT License. See [`LICENSE`](LICENSE).
