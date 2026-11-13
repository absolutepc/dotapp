"""Unit tests for power-on splash helpers (no HDMI required)."""

from firmware.display.boot_splash import _ease_in_cubic, _ease_out_cubic, boot_splash_enabled


def test_ease_curves():
    assert _ease_out_cubic(0.0) == 0.0
    assert _ease_out_cubic(1.0) == 1.0
    assert _ease_out_cubic(0.5) > 0.5
    assert _ease_in_cubic(0.5) < 0.5


def test_boot_splash_enabled_default(monkeypatch):
    monkeypatch.delenv("DOT_BOOT_SPLASH", raising=False)
    assert boot_splash_enabled() is True
    monkeypatch.setenv("DOT_BOOT_SPLASH", "0")
    assert boot_splash_enabled() is False
    monkeypatch.setenv("DOT_BOOT_SPLASH", "yes")
    assert boot_splash_enabled() is True
