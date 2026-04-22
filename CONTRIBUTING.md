# Contributing to PrivateTunes

Thank you for your interest in contributing to **PrivateTunes**! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Submitting Changes](#submitting-changes)
- [Style Guidelines](#style-guidelines)
- [Testing](#testing)

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for all contributors.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Environment details** (OS, Docker version, etc.)
- **Logs or error messages** if applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- Use a clear and descriptive title
- Provide a detailed description of the suggested enhancement
- Explain why this enhancement would be useful
- Include examples of how it would work

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Commit your changes (`git commit -m 'Add some amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## Development Setup

### Prerequisites

- Ubuntu/Debian Linux (20.04, 22.04, or 24.04)
- Docker and Docker Compose
- Git

### Setting Up Your Development Environment

1. Clone your fork:
   ```bash
   git clone https://github.com/YOUR-USERNAME/PrivateTunes.git
   cd PrivateTunes
   ```

2. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

3. Update `.env` with your development domain (can use localhost or a test domain)

4. Run the setup script:
   ```bash
   chmod +x scripts/setup.sh scripts/privatetunes.sh
   ./scripts/setup.sh
   ```

5. Start services:
   ```bash
   docker compose up -d
   ```

## Submitting Changes

### Commit Message Guidelines

- Use clear and descriptive commit messages
- Start with a verb in present tense (e.g., "Add", "Fix", "Update")
- Keep the first line under 50 characters
- Add a blank line followed by detailed description if needed

Examples:
```
Fix ND_SCANSCHEDULE format in docker-compose.yml

The scan schedule was missing the @every prefix, which caused
Navidrome to fail parsing the schedule configuration.
```

### Pull Request Guidelines

- Update documentation for any user-facing changes
- Add comments to complex code sections
- Ensure all CI checks pass
- Reference related issues in the PR description
- Keep PRs focused on a single feature or fix

## Style Guidelines

### Shell Scripts

- Use `#!/bin/bash` shebang
- Add comments for complex sections
- Use meaningful variable names
- Follow existing code style in the repository
- Run shellcheck before submitting

### YAML Files

- Use 2 spaces for indentation
- Keep lines under 120 characters when possible
- Add comments for non-obvious configurations
- Validate with `docker compose config` or yamllint

### Docker Compose

- Always include health checks for services
- Use environment variables for configurable values
- Add comments explaining environment variables
- Use restart policies appropriately

### Documentation

- Update README.md for user-facing changes
- Use clear, beginner-friendly language
- Include examples and code blocks
- Add troubleshooting tips for common issues

## Testing

### Validating Changes

Before submitting your PR, ensure:

1. **Docker Compose validates:**
   ```bash
   docker compose config --quiet
   ```

2. **Shell scripts pass shellcheck:**
   ```bash
   shellcheck scripts/*.sh
   ```

3. **Services start successfully:**
   ```bash
   docker compose up -d
   docker compose ps
   ```

4. **Health checks pass:**
   ```bash
   docker compose ps --format "table {{.Name}}\t{{.Status}}"
   ```

### Manual Testing

Test your changes in a clean environment:

1. Fresh clone of your fork
2. Run setup.sh
3. Start services with docker compose
4. Verify all services are healthy
5. Test the specific feature you changed

## Questions?

If you have questions about contributing, feel free to:

- Open an issue with your question
- Check existing documentation in README.md
- Review closed issues and PRs for similar questions

---

**PrivateTunes** is created and maintained by **[@Paidguy](https://github.com/Paidguy)** 🎵
