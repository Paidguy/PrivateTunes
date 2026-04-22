<div align="center">

## Cloud Music Stack (CMS)

Self-hosted music streaming with a **pure CLI download workflow** (no VM, no GUI desktop).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Navidrome](https://img.shields.io/badge/Powered%20by-Navidrome-00C9FF)](https://www.navidrome.org/)

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

# Host bootstrap (installs spotiflac-cli into ./bin and prepares folders)
chmod +x scripts/setup.sh scripts/cms.sh
sudo ./scripts/setup.sh

# Start the stack
docker compose up -d

# Download music into ./music (interactive menu)
./scripts/cms.sh
```

## Downloading music (CLI menu)

Run:

```bash
./scripts/cms.sh
```

Menu actions include:

- **Install/Update spotiflac-cli**
- **Download from Spotify URL** (saves into `./music`)
- **Start/Stop the stack** (`docker compose up -d` / `docker compose down`)
- **Logs**

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

