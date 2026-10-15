#!/usr/bin/env python3
"""Reports how each Steam web helper session in a bottle ended up compositing.

Steam's CEF starts a GPU process on ANGLE (D3D11 through DXVK, or Vulkan).
When that process dies, Chromium relaunches it with --use-gl=disabled, which
is software compositing, and only then do the store pages paint. This prints,
per webhelper launch, the renderer ANGLE reported, whether and how long after
launch that fallback happened, and when the store view was first shown after
it, so a runtime or DXVK change can be compared run against run.

Usage: scripts/steam-cef-report.py [bottle-dir] [-n SESSIONS]

Without a bottle, the Whisky Preview bottle whose Steam logs changed last is
used. Times are Steam's log clock, which follows the prefix's time zone; the
local time is added where cef_log.txt lets it be matched by process ID.
"""

import argparse
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path

CONTAINERS = Path.home() / "Library/Containers/com.dappermint.WhiskyPreview"
STEAM_LOGS = Path("drive_c/Program Files (x86)/Steam/logs")

STAMP = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] (.*)")
CEF_STAMP = re.compile(r"^\[(\d+):\d+:(\d{4})/(\d{6})\.\d+:")


def parse_time(text):
    return datetime.strptime(text, "%Y-%m-%d %H:%M:%S")


def stamped_lines(path):
    if not path.exists():
        return
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = STAMP.match(line)
            if match:
                yield parse_time(match.group(1)), match.group(2)


def find_bottle():
    candidates = [
        logs for logs in CONTAINERS.glob("*/" + str(STEAM_LOGS)) if (logs / "webhelper.txt").exists()
    ]
    if not candidates:
        sys.exit(f"No bottle with Steam logs under {CONTAINERS}")
    return max(candidates, key=lambda logs: (logs / "webhelper.txt").stat().st_mtime)


def flag_mode(commandline):
    if "--disable-gpu-compositing" in commandline or "--disable-gpu " in commandline:
        return "software (-cef-disable-gpu)"
    if "--ignore-gpu-blocklist" in commandline:
        return "gpu (-cef-force-gpu)"
    return "default"


def load_sessions(logs):
    """Splits webhelper.txt into one session per helper launch.

    The file is appended in launch order, but its clock can jump back when
    the prefix's time zone changes, so sessions are kept in file order.
    """
    sessions = []
    for time, text in stamped_lines(logs / "webhelper.txt"):
        if text.startswith("Startup - webhelper launched"):
            pid = re.search(r"pid: (\d+)", text)
            sessions.append({
                "start": time,
                "pid": pid.group(1) if pid else None,
                "mode": flag_mode(text),
                "gpu_launches": [],
                "fallback": None,
                "store_loaded": None,
                "shown_after_fallback": None,
                "renderer": None,
                "local_offset": None,
            })
            continue
        if not sessions:
            continue
        session = sessions[-1]
        if "--type=gpu-process" in text:
            session["gpu_launches"].append(time)
            if "--use-gl=disabled" in text and session["fallback"] is None:
                session["fallback"] = time
        elif text.startswith("SteamBrowser") and "STARTUP LoadEnd" in text and session["store_loaded"] is None:
            if "'data:text/'" not in text:
                session["store_loaded"] = time
        elif (text.startswith("SteamBrowser") and "WasHidden 0" in text and session["fallback"]
              and session["shown_after_fallback"] is None and time >= session["fallback"]):
            session["shown_after_fallback"] = time
    return sessions


def attach_renderers(logs, sessions):
    reports = [
        (time, text.split("]:", 1)[1].strip())
        for time, text in stamped_lines(logs / "webhelper_gpu.txt")
        if "[ GL_RENDERER ]" in text
    ]
    for session in sessions:
        window_end = session["start"] + timedelta(minutes=5)
        for time, renderer in reports:
            if session["start"] <= time <= window_end:
                session["renderer"] = renderer
                break


def attach_local_offsets(logs, sessions):
    cef_log = logs / "cef_log.txt"
    if not cef_log.exists():
        return
    first_seen = {}
    with cef_log.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = CEF_STAMP.match(line)
            if match and match.group(1) not in first_seen:
                first_seen[match.group(1)] = (match.group(2), match.group(3))
    for session in sessions:
        seen = first_seen.get(session["pid"])
        if not seen:
            continue
        month_day, clock = seen
        local = datetime.strptime(f"{session['start'].year}{month_day}{clock}", "%Y%m%d%H%M%S")
        offset = local - session["start"]
        # A reused PID from another day matches nothing close; ignore it.
        if abs(offset) <= timedelta(hours=14):
            session["local_offset"] = timedelta(minutes=round(offset.total_seconds() / 900) * 15)


def since(session, time):
    if time is None:
        return "-"
    seconds = int((time - session["start"]).total_seconds())
    return f"+{seconds // 60}:{seconds % 60:02d}"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("bottle", nargs="?", type=Path, help="bottle directory")
    parser.add_argument("-n", "--sessions", type=int, default=10, help="most recent sessions to show")
    args = parser.parse_args()

    logs = args.bottle / STEAM_LOGS if args.bottle else find_bottle()
    if not (logs / "webhelper.txt").exists():
        sys.exit(f"No webhelper.txt in {logs}")

    sessions = load_sessions(logs)
    attach_renderers(logs, sessions)
    attach_local_offsets(logs, sessions)
    sessions = sessions[-args.sessions:]

    print(f"Steam logs: {logs}\n")
    fallback_delays = []
    for session in sessions:
        local = ""
        if session["local_offset"] is not None:
            local = f" (local {(session['start'] + session['local_offset']):%H:%M:%S})"
        print(f"webhelper {session['start']:%Y-%m-%d %H:%M:%S}{local}  pid {session['pid']}")
        print(f"  flags:        {session['mode']}")
        print(f"  renderer:     {session['renderer'] or 'no GPU report'}")
        print(f"  GPU launches: {len(session['gpu_launches'])}")
        if session["fallback"]:
            fallback_delays.append((session["fallback"] - session["start"]).total_seconds())
            print(f"  fallback:     {since(session, session['fallback'])} to --use-gl=disabled (software)")
        else:
            print("  fallback:     none")
        print(f"  store loaded: {since(session, session['store_loaded'])}")
        print(f"  store shown after fallback: {since(session, session['shown_after_fallback'])}")
        print()

    gpu_sessions = [s for s in sessions if s["mode"].startswith("gpu")]
    print(f"{len(fallback_delays)} of {len(gpu_sessions)} GPU-composited sessions fell back to software.")
    if fallback_delays:
        low, high = min(fallback_delays), max(fallback_delays)
        print(f"Fallback came {int(low)}s to {int(high)}s after launch.")
        if high - low <= 10:
            print("A delay that constant points to a timeout (a hung GPU process), not a crash.")


if __name__ == "__main__":
    main()
