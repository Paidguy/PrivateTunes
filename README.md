<div align="center">

# 🎵 PrivateTunes

**Your private, self-hosted music streaming server with a premium CLI workflow.**

No VM. No GUI desktop app. Just your music, your server, your rules.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Navidrome](https://img.shields.io/badge/Powered%20by-Navidrome-00C9FF)](https://www.navidrome.org/)
[![Version](https://img.shields.io/badge/version-3.0.0-brightgreen)]()
[![Author](https://img.shields.io/badge/by-%40Paidguy-blueviolet)](https://github.com/Paidguy)

**Created and maintained by [@Paidguy](https://github.com/Paidguy)**

</div>

---

## What is PrivateTunes?

PrivateTunes runs a personal music server ([Navidrome](https://www.navidrome.org/)) behind [Caddy](https://caddyserver.com/) (automatic HTTPS), backed by a `./music` folder you control.

For music acquisition, it integrates a powerful backend via [`SpotiFLAC-CLI`](https://github.com/lahiruchinthana/SpotiFLAC-CLI) and provides a **premium interactive CLI** (`scripts/privatetunes.sh`) to download music directly into your library — including batch downloads with progress tracking, smart retries, a download queue, and download history.

### ✨ v3.0.0 Highlights

- **Premium CLI UI** — 256-color palette, animated spinners, progress bars, status badges
- **Modular architecture** — 10 focused modules instead of one monolith
- **Auto-update system** — Git-based with semver comparison and safe rollback
- **Permission auto-fix** — Never manually `chmod` again
- **Smart downloads** — Automated API rotation across Tidal/Qobuz/Amazon, error analysis, queue management, and retry workflows
- **Debug mode** — `--debug` flag for verbose troubleshooting

## Architecture

| Service | Role |
|---|---|
| **Caddy** | Reverse proxy + automatic TLS certificates |
| **Navidrome** | Music server with Subsonic API + web player |
| **Syncthing** *(optional)* | Sync your `./music` folder across devices |
| **SpotiFLAC-CLI** | CLI downloader (runs on the host, saves into `./music`) |

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
#   → Downloads SpotiFLAC-CLI into ./bin/
#   → Copies .env.example → .env and runs the domain wizard
#   → Starts the Docker stack
#   → Waits for Navidrome to be healthy
sudo ./scripts/setup.sh

# Then use the interactive menu to download music & manage everything:
./scripts/privatetunes.sh
```

> **Note:** Permissions are auto-fixed on every startup — no manual `chmod` needed.

## CLI Menu

Run:

```bash
./scripts/privatetunes.sh           # Normal mode
./scripts/privatetunes.sh --debug   # Verbose debug output
```

### Menu Actions

| Key | Action | Description |
|-----|--------|-------------|
| `s` | **Setup wizard** | Guided 5-step onboarding (domain, tools, Docker, admin) |
| `u` | **Check for updates** | Git-based auto-update with version comparison |
| `h` | **Help & docs** | Comprehensive help screen |
| `1` | **Install/Update SpotiFLAC** | Download the latest binary |
| `2` | **Download from URL (Now)** | Paste a track/album/playlist URL → FLAC into `./music` |
| `3` | **Queue URL** | Add URL to `links.txt` for batch processing later |
| `m` | **Track metadata** | Inspect metadata for any Spotify track URL |
| `b` | **Batch process queue** | Download all URLs from `links.txt` with progress tracking |
| `d` | **Download history** | View, clear, or queue failed tracks for retry |
| `4` | **Start stack** | `docker compose up -d` with health monitoring |
| `5` | **Stop stack** | `docker compose down` |
| `6` | **View logs** | Follow live container logs |
| `7` | **Stack status** | Health checks + disk usage |
| `8` | **Restart Navidrome** | Restart only the music server |
| `9` | **Domain wizard** | Configure DOMAIN, UID, GID |
| `c` | **Backup config** | Archive `.env`, `Caddyfile`, `docker-compose.yml` |
| `p` | **Paths & environment** | Display paths, stats, and `.env` contents |
| `0` | **Exit** | Quit |

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

PrivateTunes tracks every download in a persistent JSON database (`data/download_history.json`):

- **No duplicate downloads** — Automatically skips previously downloaded content
- **Filesystem-aware** — Scans `music/` for existing files on first run
- **Resume interrupted batches** — Re-run picks up exactly where it left off
- **Smart retries** — Exponential backoff (5s → 15s → 45s) with rate-limit detection
- **Error analysis** — Detects DNS failures, 502 errors, timeouts, and adjusts strategy
- **Atomic tracking** — Each download is recorded immediately via tmp+mv writes
- **URL normalization** — Same track won't re-download even with different `?si=...` params

### Managing History

Use menu option `d` to:
- View download statistics and recent downloads
- Clear failed entries (so they get retried on next batch)
- Clear all history (to force re-downloading)
- Scan existing music into the history database

> **Note:** `jq` is recommended for the best experience. Without `jq`, a simpler log fallback is used.

## File Structure

```
PrivateTunes/
├── Caddyfile                  # Caddy reverse proxy config
├── Caddyfile.example          # Template Caddyfile
├── docker-compose.yml         # Docker stack definition
├── .env.example               # Environment template
├── links.txt                  # Batch download URLs (one per line)
├── music/                     # Your music library (Navidrome reads here)
├── data/                      # Persistent state
│   └── download_history.json  # Download tracking (auto-created)
├── bin/                       # Local tools (git-ignored)
└── scripts/
    ├── privatetunes.sh        # Main CLI entry point
    ├── setup.sh               # Host bootstrap wizard
    └── lib/                   # Modular components
        ├── ui.sh              # UI: colors, boxes, spinners, progress
        ├── permissions.sh     # Auto-fix file permissions
        ├── updater.sh         # Git-based auto-update system
        ├── api_resolver.sh    # API health tracking & fallback
        ├── downloader.sh      # Download engine with retries
        ├── history.sh         # Persistent download history
        ├── docker.sh          # Docker stack management
        ├── config.sh          # .env management & backup
        └── onboarding.sh      # Setup wizard & help
```

## Updating

PrivateTunes checks for updates automatically on startup. You can also check manually:

```bash
./scripts/privatetunes.sh
# → Press [u] to check for updates
```

To update containers:

```bash
docker compose pull
docker compose up -d
```

## Troubleshooting

### Debug Mode

Run with verbose output to diagnose issues:

```bash
./scripts/privatetunes.sh --debug
```

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

### Permission Issues

Permissions are auto-fixed on every startup. If you still have issues:

```bash
chmod +x scripts/*.sh scripts/lib/*.sh
```

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
