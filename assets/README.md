# Built-in gallery assets

Custom animations and emoji for the round display. Prefer your own uploads via the iPhone app (**My Media** / Custom) for personal logos.

## Switch animation on Pi

```bash
show            # list
show anim3
show project1
show status
```

## Refresh on Pi

```bash
cd ~/dotapp
git pull
# do NOT run refresh-gallery.sh / generate_assets.py (wipes custom assets)
sudo rm -f /var/lib/bmw-logo/manifest.json
sudo rm -rf /var/lib/bmw-logo/frames/builtin-*
sudo systemctl restart bmw-api bmw-display
```

## Gallery animations

| File | Name | Type |
|------|------|------|
| radar4.webm | Radar 4 | animation |
| anim1.webm | Anim 1 | animation |
| anim3.webm | Anim 3 | animation |
| anim4.webm | Anim 4 | animation |
| anim5.webm | Anim 5 | animation |
| anim6.webm | Anim 6 | animation |
| anim7.webm | Anim 7 | animation |
| anim8.webm | Anim 8 | animation |
| anim9.webm | Anim 9 | animation |
| anim10.webm | Anim 10 | animation |
| anim11.webm | Anim 11 | animation |
| anim12.webm | Anim 12 | animation |
| anim13.webm | Anim 13 | animation |
| anim14.webm | Anim 14 | animation |
| anim15.webm | Anim 15 | animation |
| anim16.webm | Anim 16 | animation |
| anim17.webm | Anim 17 | animation |
| project1.webm | Project 1 | animation |
| project2.webm | Project 2 | animation |
| project3.webm | Project 3 | animation |

WebM/MP4 are decoded via ffmpeg into a JPEG/PNG frame cache (up to **360 frames**)
with a visibility lift for dark neon/radar clips.

For the HTML mockup, each WebM has a matching **`.mp4` (H.264)** sibling so Safari
and iPhone can play the preview (VP9 WebM often does not). The Pi display still
uses the `.webm` from `catalog.json`.

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

Copy PNG/GIF/WebP/WebM (ideally 480×480) into `bmw/` or `emoji/`, update `catalog.json` names if needed, then restart `bmw-api`.

Or upload from iPhone — no repo changes required.
