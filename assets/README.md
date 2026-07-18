# Built-in gallery assets

Custom animations and emoji for the round display. Prefer your own uploads via the iPhone app (**My Media** / Custom) for personal logos.

## Refresh on Pi

```bash
cd ~/dotapp
git pull origin main
# do NOT run refresh-gallery.sh / generate_assets.py (wipes custom assets)
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
| radar4.webm | Radar 4 | animation |
| anim1.webm | Anim 1 | animation |
| project1.webm | Project 1 | animation |
| project2.webm | Project 2 | animation |
| project3.webm | Project 3 | animation |

GIF and WebM are both supported. WebM/MP4 are decoded via ffmpeg into a PNG frame
cache (up to **360 frames**) with a visibility lift for dark neon/radar clips.

Shorter clips preload into RAM; longer ones stream from disk with a small frame cache.
First select of a WebM rebuilds its cache (can take a minute on Pi Zero).

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

Copy PNG/GIF/WebP/WebM (ideally 480×480) into `bmw/` or `emoji/`, update `catalog.json` names if needed, then run `refresh-gallery.sh`.

Or upload from iPhone — no repo changes required.
