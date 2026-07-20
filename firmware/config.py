"""Configuration for Dot firmware."""

from pathlib import Path

# Display
DISPLAY_WIDTH = 480
DISPLAY_HEIGHT = 480
TARGET_FPS = 60

# Paths (override with DOT_DATA env for production)
REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_ROOT = Path("/var/lib/dot")
if not DATA_ROOT.exists():
    DATA_ROOT = REPO_ROOT / "data"

MEDIA_DIR = DATA_ROOT / "media"
FRAMES_DIR = DATA_ROOT / "frames"
PREVIEW_DIR = DATA_ROOT / "previews"
BUILTIN_ASSETS = REPO_ROOT / "assets"
STATE_DIR = Path("/var/run/dot")
if not STATE_DIR.exists():
    STATE_DIR = DATA_ROOT / "state"

CURRENT_MEDIA_FILE = STATE_DIR / "current_media.json"
MANIFEST_FILE = DATA_ROOT / "manifest.json"

# API
API_HOST = "0.0.0.0"
API_PORT = 8080
DEVICE_NAME = "dot"

# Upload limits
MAX_UPLOAD_BYTES = 25 * 1024 * 1024
MAX_GIF_FRAMES = 360

# Wi-Fi AP defaults (see scripts/setup-wifi-ap.sh)
AP_SSID_PREFIX = "Dot"
AP_IP = "192.168.4.1"
