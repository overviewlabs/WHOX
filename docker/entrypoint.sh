#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run whox.
set -e

WHOX_HOME="/opt/data"
INSTALL_DIR="/opt/whox"

# Create essential directory structure.  Cache and platform directories
# (cache/images, cache/audio, platforms/whatsapp, etc.) are created on
# demand by the application — don't pre-create them here so new installs
# get the consolidated layout from get_whox_dir().
mkdir -p "$WHOX_HOME"/{cron,sessions,logs,hooks,memories,skills}

# .env
if [ ! -f "$WHOX_HOME/.env" ]; then
    if [ -f "$INSTALL_DIR/config/examples/.env.example" ]; then
        cp "$INSTALL_DIR/config/examples/.env.example" "$WHOX_HOME/.env"
    else
        cp "$INSTALL_DIR/.env.example" "$WHOX_HOME/.env"
    fi
fi

# config.yaml
if [ ! -f "$WHOX_HOME/config.yaml" ]; then
    if [ -f "$INSTALL_DIR/config/examples/cli-config.yaml.example" ]; then
        cp "$INSTALL_DIR/config/examples/cli-config.yaml.example" "$WHOX_HOME/config.yaml"
    else
        cp "$INSTALL_DIR/cli-config.yaml.example" "$WHOX_HOME/config.yaml"
    fi
fi

# SOUL.md
if [ ! -f "$WHOX_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$WHOX_HOME/SOUL.md"
fi

# Sync bundled skills (manifest-based so user edits are preserved)
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

exec whox "$@"
