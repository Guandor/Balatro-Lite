# Balatro Lite

[Balatro](https://www.playbalatro.com/), the poker-inspired roguelike deck builder, with an interface rebuilt for handheld screens.

This installs alongside the original Balatro port and keeps its own saves, so you can run either one.
Thanks to nkahoang for making [the original Balatro port](https://portmaster.games/detail.html?name=balatro).

You need to own Balatro on Steam. The macOS or the Windows version is fine.

## What's different

- **Fills the screen.** The playfield takes your device's own aspect ratio and uses the whole panel, so everything is drawn noticeably larger.
- **A layout built for a small screen.** The desktop sidebar becomes a single top status bar, the shop drops its oversized animated sign so the whole storefront fits on screen, and card descriptions are larger. The clearer Nunito font is used on every device.
- **Runs lighter.** CRT, bloom, shadows, and screen shake are off, the two full-screen shaders are trimmed, and the animated background is cached instead of redrawn every frame.
- **Buttons that match your device.** The first launch asks you to press each button by the letter printed beside it, and takes your device's word for which is which. Handhelds print those letters in either the Xbox or the Nintendo arrangement, and what a device reports doesn't always match what it has printed on it.


In short, it's uglier, but it runs better and fits small screens better.

## Installation

1. Buy the game on [Steam](https://store.steampowered.com/app/2379780/Balatro/).
2. Copy the files into your ports folder.
3. Copy your game file into the `balatrolite` folder — it needs its own copy even if you already have the original port installed:
   - **Windows:** Steam → right-click Balatro → Manage → Browse Local Files. Copy `Balatro.exe`.
   - **macOS:** Steam → right-click Balatro → Manage → Browse Local Files. Right-click `Balatro.app` → Show Package Contents → `Contents/Resources`. Copy `Balatro.love`.
4. Launch it. The first start builds a patched copy called `Balatro_pm`, which takes a moment.

## Screenshots

![Blind selection](https://i.imgur.com/41sCbHl.jpeg)
![Playing a hand](https://i.imgur.com/QPrUJBH.jpeg)
![The shop](https://i.imgur.com/QRXpMAK.jpeg)




## Buttons

The first launch shows a short button check: press A, B, X, Y, then L1, L2, R1, and R2, each as it is labelled on your device. The answer is saved to `balatrolite/saves/controller-map.txt` and used from then on, so the letters Balatro prompts you with are the letters on your device.

- **START** saves. **SELECT** starts the questions over. Those two are the ones the check doesn't change, which is why they're the ones that answer the last screen.
- No L2 on your device? Press **A** again to skip any shoulder or trigger you don't have.
- To be asked again, choose **Set Up Buttons** in the in-game options menu and restart the port. Deleting `balatrolite/saves/controller-map.txt`, or setting `FORCE_BUTTON_SETUP=1` near the top of `Balatro Lite.sh`, does the same thing.
- If your device has no controller mapping at all — nothing responds in other ports either — the check also asks for the D-pad, Start, and Select, and builds a mapping from scratch.
- Skipping it (or leaving it alone until it times out) keeps your device's own mapping and doesn't ask again.

## Notes

- To turn off the performance changes, set `TRIM_SHADERS=0` and `PERF_OPTIMIZATIONS=0` near the top of `Balatro Lite.sh`, then delete `Balatro_pm`.
