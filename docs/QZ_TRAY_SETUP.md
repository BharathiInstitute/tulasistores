# Chrome Receipt Printing — Setup Guide

## Problem
Chrome's built-in print dialog goes through the Windows POSIFlow driver,
which is locked to 50×50mm paper. This causes:
- Wrong receipt size (truncated / tiny)
- Upside-down output
- Annoying print dialog on every bill

## Solution: QZ Tray (free, one-time install)

**QZ Tray** is a free open-source service that lets web apps print
directly to thermal printers, bypassing the browser print dialog and
the Windows driver's paper-size settings entirely.

### One-time setup per POS PC (2 minutes)

1. Go to **https://qz.io/download/**
2. Click **Download QZ Tray for Windows** (~45 MB)
3. Run the installer → keep defaults → Finish
4. QZ Tray auto-starts and shows a small icon in the Windows tray (near clock)
5. **Open Tulasi Stores in Chrome** → **Settings → Hardware → Silent Print (QZ Tray)**
6. Click the **refresh icon** — status turns green: *detected*
7. Flip the switch **Use QZ Tray for receipt printing** to ON
8. Pick your **POSIFlow SR20** from the printer dropdown
9. Click **Test print** — receipt should come out at correct size and right-side up

That's it. Every subsequent receipt prints silently — no dialog, correct size,
correct orientation.

### Why this works

```
Before:  Chrome  →  Print dialog  →  Windows driver (50×50mm)  →  POSIFlow  ❌
After:   Chrome  →  QZ Tray  →  raw ESC/POS bytes  →  POSIFlow native 58mm  ✅
```

QZ Tray sends raw ESC/POS bytes directly to the printer queue — the
driver's page format and orientation settings are **not applied** to raw data.
The printer prints at its native 58mm width, in hardware feed order.

### Fallback

If QZ Tray is ever stopped or not installed, the app falls back to the
original Chrome print dialog flow — nothing breaks.

### Troubleshooting

- **Status shows "not detected"** → Make sure QZ Tray icon is in the tray.
  Start menu → QZ Tray → launch it. Click refresh in settings.
- **"Test print" fails** → Check printer is powered on and has paper.
  Try selecting a different printer in the dropdown.
- **Receipt still upside down** → Your printer has a physical flip setting.
  In POSIFlow driver properties check "180° rotation" option. Or edit the
  ESC/POS builder to insert `ESC { 1` (upside-down mode) at the top.
