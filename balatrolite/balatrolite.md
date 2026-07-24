# Balatro Lite

[Balatro](https://www.playbalatro.com/), the poker-inspired roguelike deck builder, with an interface rebuilt for handheld screens.

This installs alongside the original Balatro port and keeps its own saves, so you can run either one.
Thanks to nkahoang for making [the original Balatro port](https://portmaster.games/detail.html?name=balatro).

You need to own Balatro on Steam. The macOS or the Windows version is fine.

## What's different

- **Fills the screen.** The playfield takes your device's own aspect ratio and uses the whole panel, so everything is drawn noticeably larger.
- **A layout built for a small screen.** The desktop sidebar becomes a single top status bar, the shop drops its oversized animated sign so the whole storefront fits on screen, and card descriptions are larger. The clearer Nunito font is used on every device.
- **Runs lighter.** CRT, bloom, shadows, and screen shake are off, the two full-screen shaders are trimmed, and the animated background is cached instead of redrawn every frame.


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




## Notes

- To turn off the performance changes, set `TRIM_SHADERS=0` and `PERF_OPTIMIZATIONS=0` near the top of `Balatro Lite.sh`, then delete `Balatro_pm`.
