"""Expected under 15 seconds with a signed Debug app; total budget: 30 seconds."""

import json
import os
from pathlib import Path
import select
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build/AppKitDerivedData/Build/Products/Debug/Docky.app"
BINARY = APP / "Contents/MacOS/Docky"
PROBE = APP / "Contents/Library/LoginItems/DockyDockWatchdog.app/Contents/MacOS/DockyDockWatchdog"
STATE = Path.home() / "Library/Application Support/Docky/SystemDockVisibilityState.plist"


def frames():
    """Query a fresh AppKit process, with a two-second subprocess budget."""
    return json.loads(subprocess.check_output([str(PROBE), "--visible-frame-probe"], timeout=2))


def wait_for_output(process, phrase, budget):
    """Read only ready pipe data; an authorization/error cannot hang the run."""
    deadline = time.monotonic() + budget
    output = ""
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.1)
        if ready:
            chunk = os.read(process.stdout.fileno(), 4096).decode("utf-8", errors="replace")
            print(chunk.rstrip())
            output += chunk
            if phrase in output:
                return
        if process.poll() is not None:
            raise RuntimeError("Lifecycle fixture exited before " + phrase)
    raise TimeoutError("Lifecycle fixture exceeded its budget waiting for " + phrase)


def run():
    """Verify reconnect and watchdog restoration against live WindowServer state."""
    if STATE.exists():
        raise RuntimeError("Quit the running Docky before testing its lifecycle")
    baseline = frames()
    with subprocess.Popen(
        [str(BINARY), "--dock-bridge-crash-fixture", "-ApplePersistenceIgnoreState", "YES"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ) as process:
        try:
            wait_for_output(process, "Dock bridge crash fixture ready", 8)
            reserved = frames()
            if reserved == baseline:
                raise AssertionError("Fixture did not reserve desktop space")
            subprocess.run(["/usr/bin/killall", "Dock"], check=True, timeout=2)
            wait_for_output(process, "Native Dock reservation verified", 8)
            if frames() != reserved:
                raise AssertionError("Reservation was not restored after Apple Dock restarted")
            process.kill()
            process.wait(timeout=2)
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if not STATE.exists() and frames() == baseline:
                    print("Dock restart and forced-termination watchdog recovery passed")
                    return
                time.sleep(0.1)
            raise AssertionError("Watchdog did not restore Apple's Dock and usable screen area")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2)


if __name__ == "__main__":
    run()
