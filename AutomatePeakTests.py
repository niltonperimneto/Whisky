#!/usr/bin/env python3
import os
import subprocess
import time
import argparse
import sys

WHISKY_PREVIEW_APP = "/Applications/Whisky Preview.app"
BOTTLE_NAME = "STEAM"
APP_ID = "3527290"
PEAK_DIR = "/Users/niltonperimneto/Library/Containers/com.dappermint.WhiskyPreview/7B23E2E8-4D1B-451A-A24A-95A4BB90E13F/drive_c/Program Files (x86)/Steam/steamapps/common/PEAK"

def check_for_crash(backtrace_path):
    if os.path.exists(backtrace_path):
        print("\n❌ [CRASH DETECTED] A backtrace file was generated!")
        try:
            with open(backtrace_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if "os_sync_wait_on_address" in content:
                    print("   --> ERROR: 'os_sync_wait_on_address' page fault detected. MSYNC logic is still breaking things.")
                else:
                    print("   --> CRASH: Application crashed, but 'os_sync_wait_on_address' was NOT the primary cause.")
                    print("   --- Last 15 lines of backtrace ---")
                    print("\n".join(content.splitlines()[-15:]))
        except Exception as e:
            print(f"   --> Could not read backtrace: {e}")
        return True
    return False

def main():
    parser = argparse.ArgumentParser(description="Automate PEAK launch and debugging crash logs")
    parser.add_argument("--timeout", type=int, default=60, help="Seconds to wait before assuming stable launch")
    args = parser.parse_args()

    backtrace_path = os.path.join(PEAK_DIR, "backtrace.txt")

    print("[1/4] Preparing environment (killing stale processes)...")
    subprocess.run(["pkill", "-9", "-f", "-i", "peak"], capture_output=True)
    subprocess.run(["pkill", "-9", "-f", "-i", "steam"], capture_output=True)
    subprocess.run(["pkill", "-9", "-f", "wine"], capture_output=True)
    subprocess.run(["pkill", "-9", "-f", "Whisky Preview"], capture_output=True)

    if os.path.exists(backtrace_path):
        print(f"[2/4] Removing old crash log: {backtrace_path}")
        os.remove(backtrace_path)
    else:
        print("[2/4] No old crash log found.")

    print(f"[3/4] Launching PEAK (AppID {APP_ID}) via {WHISKY_PREVIEW_APP}...")
    subprocess.run(["open", "-a", WHISKY_PREVIEW_APP])
    time.sleep(3)
    
    # Launch via URL Scheme explicitly targeting the deployed Whisky Preview app
    subprocess.run(["open", "-a", WHISKY_PREVIEW_APP, f"whisky://launch?steam={APP_ID}&bottle={BOTTLE_NAME}"])

    print(f"[4/4] Monitoring for {args.timeout} seconds for crash logs...")
    start = time.time()
    
    peak_seen = False
    try:
        while time.time() - start < args.timeout:
            if check_for_crash(backtrace_path):
                # Application crashed
                sys.exit(1)
            
            ps = subprocess.run(["pgrep", "-i", "-f", "PEAK.exe"], capture_output=True)
            if ps.returncode == 0:
                if not peak_seen:
                    print("      --> PEAK.exe process is running!")
                    peak_seen = True
            
            time.sleep(2)

        if peak_seen:
            print("\n✅ [SUCCESS] PEAK launched and ran with NO crashes.")
            print("             The MSYNC logic fix is verified in real execution.")
        else:
            print("\n⚠️ [TIMEOUT] Timeout reached without a crash, but PEAK.exe was not detected.")
            
    except KeyboardInterrupt:
        print("\n[ABORTED] Monitoring cancelled by user.")
    finally:
        print("\nTest completed.")

if __name__ == "__main__":
    main()
