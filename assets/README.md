# Built-in gallery assets

Stylized BMW-inspired roundels and emoji for the round display. These are **not** official BMW trademarks — geometric designs for personal use.

## Regenerate on Pi or dev machine

```bash
python3 scripts/generate_assets.py
# or full refresh (clears manifest cache):
bash scripts/refresh-gallery.sh
```

## BMW collection (14 items)

| File | Name | Type |
|------|------|------|
| default.png | Classic Roundel | static |
| classic-roundel.png | Blue Roundel | static |
| chrome-roundel.png | Chrome Roundel | static |
| m-sport.png | M Sport | static |
| minimal-m.png | M Badge | static |
| midnight.png | Midnight | static |
| alpine.png | Alpine White | static |
| motorsport.png | Motorsport | static |
| pulse.gif | Pulse Glow | animation |
| spin.gif | Slow Spin | animation |
| shimmer.gif | Shimmer | animation |
| m-stripe-flow.gif | M Stripe Flow | animation |
| breathe-blue.gif | Blue Breathe | animation |
| ring-pulse.gif | Ring Pulse | animation |

## Emoji collection (9 items)
| cool.png | Cool | static |
| heart-eyes.png | Heart Eyes | static |
| star.png | Star | static |
| fire.png | Fire | static |
| party.png | Party | static |
| wink.gif | Wink | animation |
| bounce.gif | Bounce | animation |
| laugh.gif | Laugh | animation |

## Add your own

Copy PNG/GIF (480×480) into `bmw/` or `emoji/`, then run `refresh-gallery.sh`.

Official BMW logos: upload via iPhone **My Media** for personal use only.
