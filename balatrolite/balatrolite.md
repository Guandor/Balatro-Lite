# Balatro Lite

A [PortMaster](https://portmaster.games/) port of [Balatro](https://www.playbalatro.com/) — the poker-inspired roguelike deck builder — with its interface rebuilt for the small screens of Linux handhelds.

**This is not the game itself.** It is the wrapper that makes a copy you already own run on a handheld: you buy Balatro on Steam, copy one file from it onto your device, and this patches and launches it there. Nothing here works without that file, and the game is never distributed with it.

There is already [a Balatro port for PortMaster](https://portmaster.games/detail.html?name=balatro), by nkahoang, which this one is built on — thank you. Balatro Lite is a variant of it aimed at smaller and slower devices: it trades visual effects for frame rate, and rebuilds the layout so a small panel shows a screen designed for it rather than a shrunken desktop one. It installs alongside the original and keeps its own saves, so you can have both and switch between them if you just want to try.

## What's different

- **Fills the screen.** The playfield takes your device's own aspect ratio and uses the whole panel, so everything is drawn noticeably larger.
- **A layout built for a small screen.** The desktop sidebar becomes a single top status bar, the shop drops its oversized animated sign so the whole storefront fits on screen, and card descriptions are larger. The clearer Nunito font is used on every device.
- **Runs lighter.** CRT, bloom, shadows, and screen shake are off, and the two full-screen shaders are trimmed. Reduced motion is on, which holds the background still, so it is drawn once into a buffer and reused until its colours change rather than recomputed every frame. The background is therefore a static image on this port, not the animated one.
- **Buttons that match your device.** The first launch asks you to press each button by the letter printed beside it, and takes your device's word for which is which. Handhelds print those letters in either the Xbox or the Nintendo arrangement, and what a device reports doesn't always match what it has printed on it.

In short, it's uglier, but it runs better and fits small screens better.

## Screenshots

![Blind selection](https://i.imgur.com/41sCbHl.jpeg)
![Playing a hand](https://i.imgur.com/QPrUJBH.jpeg)
![The shop](https://i.imgur.com/QRXpMAK.jpeg)

## What you need

- **A handheld running [PortMaster](https://portmaster.games/).** Balatro Lite is a PortMaster port and does not run without it. If your device doesn't have PortMaster yet, install that first.
- **Your own copy of Balatro**, bought on [Steam](https://store.steampowered.com/app/2379780/Balatro/). The Windows or the macOS build is equally fine — you copy a single file out of it.

## Installing

**1. Download the port.** Get the latest `balatrolite-vX.Y.Z.zip` from the [Releases page](https://github.com/Guandor/Balatro-Lite/releases). Balatro Lite isn't in PortMaster's built-in port list, so it is installed by hand — either route below does it.

**2. Install it, either way:**

- **Let PortMaster do it.** Copy the zip, still zipped, into PortMaster's `autoinstall` folder. It sits somewhere like `/roms/ports/autoinstall/`, though the exact path varies by device and firmware. Then open PortMaster, and it installs the port for you.
- **Or unpack it yourself.** Unzip it and copy both `Balatro Lite.sh` and the `balatrolite` folder into your device's `ports` folder, commonly `/roms/ports/`, keeping the two side by side.

**3. Add your game file.** Copy it into the `balatrolite` folder. It needs its own copy even if you already have the original port installed:

- **Windows:** Steam → right-click Balatro → Manage → Browse Local Files. Copy `Balatro.exe`.
- **macOS:** Steam → right-click Balatro → Manage → Browse Local Files. Right-click `Balatro.app` → Show Package Contents → `Contents/Resources`. Copy `Balatro.love`.

**4. Launch it** from your device's ports menu. The first start builds a patched copy called `Balatro_pm`, which takes a moment. Later launches skip that.

## Buttons

The first launch shows a short button check: press A, B, X, Y, then L1, L2, R1, and R2, each as it is labelled on your device. The answer is saved to `balatrolite/saves/controller-map.txt` and used from then on, so the letters Balatro prompts you with are the letters on your device.

- **START** saves. **SELECT** starts the questions over. Those two are the ones the check doesn't change, which is why they're the ones that answer the last screen.
- Every question waits for the button it names. If you leave it alone, a countdown appears and the check gives up on its own, keeping your device's own mapping. Pressing anything stops the countdown.
- To be asked again, choose **Set Up Buttons** in the in-game options menu and restart the port. Deleting `balatrolite/saves/controller-map.txt`, or setting `FORCE_BUTTON_SETUP=1` near the top of `Balatro Lite.sh`, does the same thing.
- If your device has no controller mapping at all — nothing responds in other ports either — the check also asks for the D-pad, Start, and Select, and builds a mapping from scratch.
- Skipping it (or leaving it alone until it times out) keeps your device's own mapping and doesn't ask again.

## Notes

- To turn off the performance changes, set `TRIM_SHADERS=0` and `PERF_OPTIMIZATIONS=0` near the top of `Balatro Lite.sh`, then delete `Balatro_pm`.
