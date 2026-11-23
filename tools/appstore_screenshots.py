"""App Store screenshots: raw simulator shots plus captioned versions at Apple's sizes.

    python3 tools/appstore_screenshots.py              # build, shoot, caption -> appstore/screenshots/
    python3 tools/appstore_screenshots.py --frames     # only re-caption the existing raw shots
    python3 tools/appstore_screenshots.py --only 01-home,04-chess
    python3 tools/appstore_screenshots.py --devices iphone,ipad

Shoots on the newest-iOS simulators named in DEVICES, using the app's DEBUG launch arguments
(-openGame, -demoState, -chessMoves, ...). `-uiTesting` starts every shot from a clean slate
(no saved games) with Reduce Motion on, so nothing is caught mid-animation. Captions are drawn
by headless Google Chrome from a small HTML page. Every state shown is a fresh or scripted
game: no personal data can appear. Don't run it while tools/test.sh is using the simulators.
"""
import argparse
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "appstore", "screenshots")
RAW = os.path.join(ROOT, "build", "screenshots-raw")      # git-ignored
DERIVED = os.path.join(ROOT, "build", "screenshots-dd")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BUNDLE_ID = "com.gchapiewski.airplanemodegames"

# key -> (simulator name, App Store size). Each simulator's native screenshot is exactly that size.
DEVICES = {
    "iphone": ("iPhone 17 Pro Max", (1320, 2868)),        # 6.9" ("iPhone with Dynamic Island, large")
    "iphone-medium": ("iPhone 17", (1206, 2622)),         # 6.3" ("medium")
    "ipad": ("iPad Pro 13-inch (M5)", (2064, 2752)),      # 13" portrait
}

# (file key, caption, gradient colors from GameID.colors, launch arguments, seconds to settle)
SHOTS = [
    ("01-home", "Great games. No Wi‑Fi needed.", ("#6EC6FF", "#2F8FD8"), [], 3),
    ("02-sudoku", "Sudoku from easy to expert", ("#5B8CFF", "#3A5BDB"), ["-openGame", "sudoku"], 6),
    ("03-solitaire", "Classic Klondike Solitaire", ("#2FBF71", "#14845A"), ["-openGame", "solitaire"], 6),
    ("04-chess", "Chess vs. the computer or a friend", ("#C69B6D", "#8B5E3C"),
     ["-openGame", "chess", "-chessMode", "computer", "-chessMoves", "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5"], 4),
    ("05-word-guess", "Word games for the whole trip", ("#44C9C1", "#1E9690"),
     ["-openGame", "wordGuess", "-demoState"], 4),
    ("06-nonograms", "Reveal 44 hidden pictures", ("#FF6F61", "#D6453A"),
     ["-openGame", "nonograms", "-nonogramsDemo", "3", "m-pine-tree"], 4),
    ("07-minesweeper", "Minesweeper with no guessing", ("#8A9BB5", "#56657E"),
     ["-openGame", "minesweeper", "-minesweeperDemo", "beginner", "playing"], 4),
    ("08-snake", "Snake, 2048, Block Puzzle and more", ("#7BD957", "#3FA33A"),
     ["-openGame", "snake", "-snakeDemo"], 4),
]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def newest_udid(name):
    """The available simulator called `name` on the newest installed iOS."""
    data = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                          capture_output=True, text=True).stdout)
    best = None
    for runtime, devices in data["devices"].items():
        if "iOS" not in runtime:
            continue
        version = tuple(int(x) for x in runtime.rsplit("iOS-", 1)[-1].split("-") if x.isdigit())
        for d in devices:
            if d["name"] == name and (best is None or version > best[0]):
                best = (version, d["udid"])
    if not best:
        sys.exit(f"No simulator named '{name}'. Create it in Xcode > Window > Devices and Simulators.")
    return best[1]


def build():
    print("▸ Building (Debug, for the launch arguments)")
    run(["xcodebuild", "-project", os.path.join(ROOT, "AirplaneModeGames.xcodeproj"),
         "-scheme", "AirplaneModeGames", "-destination", "generic/platform=iOS Simulator",
         "-derivedDataPath", DERIVED, "build", "-quiet"])
    return os.path.join(DERIVED, "Build", "Products", "Debug-iphonesimulator", "AirplaneModeGames.app")


def shoot(app, device_key, shots):
    name, size = DEVICES[device_key]
    udid = newest_udid(name)
    print(f"▸ {device_key}: {name}")
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
    run(["xcrun", "simctl", "ui", udid, "appearance", "light"])
    run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged",
         "--batteryLevel", "100", "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported"])
    run(["xcrun", "simctl", "install", udid, app])
    out = os.path.join(RAW, device_key)
    os.makedirs(out, exist_ok=True)
    for key, _, _, args, settle in shots:
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], capture_output=True)
        run(["xcrun", "simctl", "launch", udid, BUNDLE_ID, "-uiTesting", *args], capture_output=True)
        time.sleep(settle)
        path = os.path.join(out, key + ".png")
        run(["xcrun", "simctl", "io", udid, "screenshot", path], capture_output=True)
        print(f"  {key}")
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], capture_output=True)
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "clear"], capture_output=True)


def caption_html(raw_png, caption, colors, size):
    """The page Chrome renders into one captioned screenshot of exactly `size` pixels."""
    w, h = size
    cap_h = round(h * 0.15)
    font = round(w * (0.058 if w > 1500 else 0.074))
    pad = round(h * 0.035)
    shot_h = h - cap_h - pad
    radius = round(w * 0.06)
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden;
  background: linear-gradient(160deg, {colors[0]}, {colors[1]}); }}
.cap {{ height: {cap_h}px; display: flex; align-items: center; justify-content: center; text-align: center;
  padding: {round(h * 0.012)}px {round(w * 0.07)}px 0; box-sizing: border-box; color: white;
  font: 800 {font}px/1.1 "SF Pro Rounded", "Avenir Next", "Helvetica Neue", sans-serif;
  letter-spacing: -0.01em; text-shadow: 0 {round(h * 0.002)}px {round(h * 0.006)}px rgba(0,0,0,0.18); }}
img {{ display: block; margin: 0 auto; height: {shot_h}px; width: auto; border-radius: {radius}px;
  border: {round(w * 0.012)}px solid rgba(255,255,255,0.9);
  box-shadow: 0 {round(h * 0.012)}px {round(h * 0.035)}px rgba(0,0,0,0.28); }}
</style></head><body><div class="cap">{html.escape(caption)}</div>
<img src="{html.escape(os.path.basename(raw_png))}" alt=""></body></html>"""


def frame(device_key, shots):
    _, size = DEVICES[device_key]
    dest = os.path.join(OUT, device_key)
    os.makedirs(dest, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for key, caption, colors, _, _ in shots:
            raw = os.path.join(RAW, device_key, key + ".png")
            if not os.path.exists(raw):
                sys.exit(f"Missing raw shot {raw}; run without --frames first.")
            shutil.copy(raw, tmp)
            page = os.path.join(tmp, key + ".html")
            with open(page, "w") as f:
                f.write(caption_html(raw, caption, colors, size))
            target = os.path.join(dest, key + ".png")
            run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                 f"--window-size={size[0]},{size[1]}", f"--screenshot={target}", "file://" + page],
                capture_output=True)
            print(f"  {device_key}/{key}.png")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", action="store_true", help="only re-caption existing raw shots")
    parser.add_argument("--only", help="comma-separated shot keys")
    parser.add_argument("--devices", help="comma-separated device keys: " + ",".join(DEVICES))
    a = parser.parse_args()
    shots = [s for s in SHOTS if not a.only or s[0] in a.only.split(",")]
    devices = a.devices.split(",") if a.devices else list(DEVICES)
    if not a.frames:
        app = build()
        for d in devices:
            shoot(app, d, shots)
    print("▸ Captioning")
    for d in devices:
        frame(d, shots)


if __name__ == "__main__":
    main()
