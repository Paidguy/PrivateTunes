<div align="center">

## Cloud Music Stack (CMS)

Self-hosted music streaming with a **pure CLI download workflow** (no VM, no GUI desktop).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Navidrome](https://img.shields.io/badge/Powered%20by-Navidrome-00C9FF)](https://www.navidrome.org/)
[![Author](https://img.shields.io/badge/by-%40Paidguy-blueviolet)](https://github.com/Paidguy)

**Created and maintained by [@Paidguy](https://github.com/Paidguy)**

</div>

---

## What this repo is

CMS runs a personal music server (Navidrome) behind Caddy (automatic HTTPS), backed by a `./music` folder you control.  
For acquisition, it integrates [`spotiflac-cli`](https://github.com/Superredstone/spotiflac-cli) and provides a simple interactive menu (`scripts/cms.sh`) to download music directly into your library.

## Architecture

- **Caddy**: reverse proxy + automatic TLS
- **Navidrome**: music server + Subsonic API
- **Syncthing** (optional): sync your `./music` folder across devices
- **spotiflac-cli**: CLI downloader (runs on the host, saves into `./music`)

## Prerequisites

- **Linux server** (Ubuntu/Debian recommended)
- **Docker** + Docker Compose plugin (`docker compose`)
- **Ports**: `80` and `443` exposed (for HTTPS)
- **A domain** pointing to the server (DuckDNS works well)

## Quick start

```bash
git clone https://github.com/Paidguy/music-stack.git
cd music-stack

# Full automated setup:
# - Installs Docker Engine + Docker Compose plugin (if missing)
# - Installs system dependencies (curl, ca-certificates, git, gnupg)
# - Creates required directories (music/, data/navidrome/, data/syncthing/)
# - Downloads spotiflac-cli into ./bin/
# - Copies .env.example → .env
# - Starts the Docker stack
# - Waits for Navidrome to be healthy
chmod +x scripts/setup.sh scripts/cms.sh
sudo ./scripts/setup.sh

# Download music / manage the stack interactively
./scripts/cms.sh
```

## Downloading music (CLI menu)

Run:

```bash
./scripts/cms.sh
```

Menu actions include:

- **s) Full setup** — runs `setup.sh` end-to-end (Docker + deps + stack start)
- **1) Install/Update spotiflac-cli**
- **2) Download from Spotify URL** (saves into `./music`)
- **3) View track metadata**
- **4–6) Start / Stop / Logs** (`docker compose` wrappers)
- **7) Stack status** — health check for Navidrome & Syncthing
- **8) Restart Navidrome**
- **9) Edit .env** — configure DOMAIN, UID, GID

## Configuration

Create your `.env` file:

```bash
cp .env.example .env
```

Variables:

- **`DOMAIN`**: your domain name (e.g. `your-domain.duckdns.org`)
- **`UID` / `GID`**: user/group ids for Syncthing (defaults to `1000`)

## File structure

```
music-stack/
├── Caddyfile
├── docker-compose.yml
├── .env.example
├── music/                # your music library (Navidrome reads from here)
├── data/                 # Navidrome + Syncthing state
├── bin/                  # local tools (ignored by git)
└── scripts/
    ├── setup.sh          # host bootstrap (CLI edition)
    └── cms.sh            # interactive CLI menu
```

## Updating

```bash
# Update containers
docker compose pull
docker compose up -d

# Update spotiflac-cli (via menu)
./scripts/cms.sh
```

## Troubleshooting

### Music not appearing in Navidrome

- Verify files are in `./music`
- Restart Navidrome or trigger a scan in the UI

```bash
docker compose restart navidrome
```

### Caddy/SSL issues

```bash
docker compose logs -f caddy
```

Make sure:

- `DOMAIN` in `.env` is correct
- Ports `80/443` are reachable publicly
- Your DNS A/AAAA record points to the server

---

## License & disclaimer

This project is for **personal use with legally obtained content**. You are responsible for compliance with local laws and the terms of services you use.

Licensed under the MIT License. See [`LICENSE`](LICENSE).

