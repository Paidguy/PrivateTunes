# PrivateTunes - Project Instructions

Foundational mandates for the PrivateTunes project.

## Project Overview
PrivateTunes is a self-hosted music streaming server (Navidrome) with a premium CLI workflow for music acquisition and server management.

- **Stack:** Docker, Docker Compose, Navidrome, Caddy, Syncthing, SpotiFLAC-CLI.
- **Environment:** Linux (Ubuntu/Debian recommended).

## Architecture
The project uses a modular architecture for its CLI management tools, located in `scripts/lib/`.

### Core Modules (`scripts/lib/`)
- `ui.sh`: Handles colors, box-drawing, spinners, progress bars, and badges. Provides a premium CLI experience using 256-color palettes and ANSI escape codes.
- `permissions.sh`: Automates file permission fixes for the entire project structure. Invoked automatically on every startup of `privatetunes.sh`.
- `updater.sh`: Manages git-based self-updates. Handles version comparison (SemVer) and safe rollbacks.
- `api_resolver.sh`: Tracks API health and handles rotation for downloads across multiple backends (Tidal, Qobuz, etc.).
- `downloader.sh`: Orchestrates the download process using `spotiflac-cli`. Features:
  - Smart retries with exponential backoff.
  - Failure analysis (DNS, Gateway, Rate Limits, Timeouts).
  - High-quality FLAC (24-bit) and cover art acquisition.
- `history.sh`: Manages the persistent download history in `data/download_history.json`. Tracks track status, original/normalized URLs, and timestamps. Prefers `jq` for JSON manipulation with a minimal grep fallback.
- `docker.sh`: Wraps Docker Compose commands, provides service health monitoring, and handles stack-specific actions (e.g., restarting Navidrome).
- `config.sh`: Manages `.env` files, backups, and environment validation. Handles the domain wizard and path resolution.
- `onboarding.sh`: Provides the guided setup wizard and comprehensive help documentation.

### Main Entry Points
- `scripts/setup.sh`: Automated host bootstrap. Installs Docker, system dependencies, and initializes the project environment.
- `scripts/privatetunes.sh`: The primary interactive CLI interface. Handles flag parsing (`--debug`), module loading, and the main menu loop.

## Engineering Standards

### Shell Scripting (Bash)
- **Shebang:** Always use `#!/bin/bash`.
- **Modularity:** Use the double-source guard at the top of every module:
  ```bash
  [ -n "${_PT_MODULENAME_LOADED:-}" ] && return 0
  _PT_MODULENAME_LOADED=1
  ```
- **Error Handling:**
  - Use `set -euo pipefail` in main entry scripts (e.g., `setup.sh`, `privatetunes.sh`) to ensure scripts exit on errors, unset variables, and pipe failures.
  - Check command exit codes (`$?` or `PIPESTATUS`) and provide meaningful feedback via UI functions.
- **Logging:**
  - Use `debug_msg "message"` for verbose output (active only with `--debug`).
  - Use `err "message"` for error reporting.
  - Use `info_box`, `status_badge`, and other `ui.sh` functions for user-facing feedback.
- **Dependency Management:**
  - Always check for required binaries using `ensure_cmd`.
  - Core dependencies: `docker`, `jq`, `curl` or `wget`, `git`, `sed`, `awk`.
- **UI & Output:**
  - Never use raw `echo` for user-facing messages; use `ui.sh` helpers.
  - Maintain the "premium" feel: use spinners for long tasks and color-coded status badges.
- **Error Handling:** Check command exit codes (`$?` or `PIPESTATUS`) and provide meaningful feedback via UI functions.

### Docker & Infrastructure
- **Indentation:** Use 2 spaces for YAML files.
- **Health Checks:** Every service in `docker-compose.yml` MUST have a health check.
- **Service Dependencies:** Use `depends_on` with `condition: service_healthy` to ensure proper startup order.
- **Permissions:** Rely on `lib/permissions.sh` for fixing permissions. Do not use manual `chmod` in scripts.
- **Volume Mapping:** Keep persistent data in `data/` and `music/`. Use `:ro` for read-only volumes where appropriate.

## Development Workflows

### Setup & Bootstrapping
1. Run `./scripts/setup.sh` to initialize the environment.
2. The setup script handles dependency installation, directory creation, and initial configuration.

### Testing & Validation
- **Linting:** Run `shellcheck` on all shell scripts: `shellcheck scripts/*.sh scripts/lib/*.sh`.
- **Syntax Check:** Validate bash syntax with `bash -n scripts/privatetunes.sh`.
- **Docker Validation:** Run `docker compose config` to verify YAML changes.
- **Runtime Testing:** Test new features with the `--debug` flag enabled: `./scripts/privatetunes.sh --debug`.

### Versioning & Updates
- Follow SemVer (e.g., `3.0.0`).
- Update the `VERSION` variable in `scripts/privatetunes.sh` for every release.
- The update system relies on `origin/main` by default.

## Troubleshooting
- Use `./scripts/privatetunes.sh --debug` for verbose logs.
- Check service logs: `docker compose logs -f <service_name>`.
- Use the "Stack status" (option `7`) in the CLI menu for a quick health overview.
