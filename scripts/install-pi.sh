#!/usr/bin/env bash
# Install BMW Logo firmware on Raspberry Pi.
set -euo pipefail

INSTALL_DIR="/opt/bmw-logo"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing to ${INSTALL_DIR}..."

sudo mkdir -p "${INSTALL_DIR}"
sudo rsync -a --exclude '.git' --exclude 'ios' --exclude '.venv' \
  "${REPO_ROOT}/" "${INSTALL_DIR}/"

cd "${INSTALL_DIR}"
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r firmware/requirements.txt

sudo mkdir -p /var/lib/bmw-logo/{media,frames,previews,state}
sudo mkdir -p /var/run/bmw-logo
sudo chown -R pi:pi /var/lib/bmw-logo /var/run/bmw-logo "${INSTALL_DIR}"

python3 scripts/generate_assets.py

sudo cp firmware/systemd/bmw-logo-api.service /etc/systemd/system/
sudo cp firmware/systemd/bmw-logo-display.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable bmw-logo-api bmw-logo-display

echo "Install complete. Start services:"
echo "  sudo systemctl start bmw-logo-api bmw-logo-display"
