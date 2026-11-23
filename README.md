# Lightroom Auto Straighten

A macOS script that runs Lightroom Classic's **Crop tool → Auto** straighten on a run of photos, one after another.

Lightroom can't batch the Crop tool's Auto button: syncing a crop copies one fixed angle to every photo. This script works around that by pressing Auto on each photo, so every photo gets its own angle.

## Requirements

- macOS with Lightroom Classic
- Terminal allowed under **System Settings → Privacy & Security → Accessibility**
- Xcode command line tools (`xcode-select --install`), used to compile a small helper on first run

## Usage

1. In Lightroom Classic, open the **Develop** module and select the first photo to straighten. The Crop tool can be open or closed.
2. Run:

```bash
./lr-autostraighten.sh [COUNT] [WAIT_SECONDS]
```

- `COUNT`: number of photos to process, moving right through the filmstrip (default 10)
- `WAIT_SECONDS`: pause after pressing Auto so Lightroom can finish calculating the angle (default 2.5). Raise it if some photos end up at 0°.

Example: `./lr-autostraighten.sh 25`

Don't use the mouse or keyboard while it runs. Press Ctrl+C to stop. Any crop can be undone in Lightroom with Cmd+Z.

## How it works

For each photo the script:

1. checks through macOS accessibility whether the Crop tool is open, by looking for its "Constrain to Image" checkbox, and presses **R** only if it's closed (R toggles the tool)
2. presses the Crop panel's **Auto** button, never the Basic panel's tone Auto
3. waits, presses **Return** to apply the crop, and moves to the next photo with the right arrow

## License

MIT
