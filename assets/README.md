# Built-in gallery assets

Custom animations and emoji for the round display. Prefer your own uploads via the iPhone app (**My Media** / Custom) for personal logos.

## Refresh on Pi

```bash
cd ~/dotapp
git pull origin main
bash scripts/refresh-gallery.sh
sudo systemctl restart bmw-logo-api bmw-logo-display
```

## BMW / custom animations (6 items)

| File | Name | Type |
|------|------|------|
| default.gif | Default | animation |
| challenger.gif | Challenger | animation |
| Itachi.gif | Itachi | animation |
| omnitrix.gif | Omnitrix | animation |
| quiet_r.gif | Quiet R | animation |
| quiet_w.gif | Quiet W | animation |

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
