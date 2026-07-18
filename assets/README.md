# Built-in gallery assets

Custom animations and emoji for the round display. Prefer your own uploads via the iPhone app (**My Media** / Custom) for personal logos.

## Refresh on Pi

```bash
cd ~/dotapp
git pull origin main
# do NOT run refresh-gallery.sh / generate_assets.py (wipes custom GIFs)
sudo rm -f /var/lib/bmw-logo/manifest.json
sudo rm -rf /var/lib/bmw-logo/frames/builtin-*
sudo systemctl restart bmw-logo-api bmw-logo-display
```

## Gallery animations (12 items)

| File | Name | Type |
|------|------|------|
| default.gif | Default | animation |
| challenger.gif | Challenger | animation |
| Itachi.gif | Itachi | animation |
| omnitrix.gif | Omnitrix | animation |
| quiet_r.gif | Quiet R | animation |
| quiet_w.gif | Quiet W | animation |
| radar.gif | Radar | animation |
| radar4.gif | Radar 4 | animation |
| anim1.gif | Anim 1 | animation |
| project1.gif | Project 1 | animation |
| project2.gif | Project 2 | animation |
| project3.gif | Project 3 | animation |

Prefer **GIF** for built-in gallery items on Pi Zero (more stable than WebM).
WebM/MP4 uploads still work via ffmpeg, but GIF is recommended.

Firmware accepts up to **360 frames** per GIF/video. Shorter clips preload into RAM;
longer ones (e.g. Project 1–3) stream from disk with a small frame cache.

Dark neon/radar clips are auto-brightened when building the frame cache so they
stay visible on dim round HDMI panels. After pulling updates, wipe `frames/` as
above — the first select rebuilds cache (may take a minute on Pi Zero).

## Emoji collection (9 items)

| File | Name | Type |
|------|------|------|
| smile.png | Smile | static |
| cool.png | Cool | static |
| heart-eyes.png | Heart Eyes | static |
| star.png | Star | static |
| fire.png | Fire | static |
| party.png | Party | static |
| wink.gif | Wink | animation |
| bounce.gif | Bounce | animation |
| laugh.gif | Laugh | animation |

## Add your own

Copy PNG/GIF/WebP (ideally 480×480) into `bmw/` or `emoji/`, update `catalog.json` names if needed, then run `refresh-gallery.sh`.

Or upload from iPhone — no repo changes required.
