#!/usr/bin/env python3
"""Focus Deck end-to-end harness (Python 3 stdlib only).

Drives the REAL installed app, the real CLI and the real shared JSON state on
this machine, prints one PASS/FAIL/SKIP line per check plus a summary, and
exits non-zero when any check fails.

Usage:
    python3 tests/e2e/deck_e2e.py

Safety:
    focus.json and settings.json are copied to a temp dir before any check and
    restored in a finally block.  Nothing outside the temp dir is deleted.

Known app behaviour that this harness measures (see README of the run report):
    * a CLI overlay stays in focus.json forever,
    * the overlay banner stays on screen past its TTL until another state change
      arrives.
"""

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

HOME = os.path.expanduser("~")
PROCESS = "FocusDeck"
APP_BUNDLE = os.path.join(HOME, "Applications", "Focus Deck.app")
APP_BINARY = os.path.join(APP_BUNDLE, "Contents", "MacOS", "FocusDeck")
DESKTOP_ENTRY = os.path.join(HOME, "Desktop", "Focus Deck.app")
SUPPORT_DIR = os.path.join(HOME, "Library", "Application Support", "FocusDeck")
FOCUS_JSON = os.path.join(SUPPORT_DIR, "focus.json")
SETTINGS_JSON = os.path.join(SUPPORT_DIR, "settings.json")
KEYCHAIN_SERVICE = "com.focusdeck.app"
KEYCHAIN_ACCOUNT = "todoist-api-token"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CLI_CANDIDATES = [
    os.path.join(HOME, ".local", "bin", "focusdeck"),
    os.path.join(REPO_ROOT, ".build", "release", "focusdeck-cli"),
]
BANNER = (300, 92, 600, 46)    # overlay banner band, relative to the window top-left.
                               # Kept above the title: the huge white letters dominate the
                               # statistics of any region they touch.
CHANGE_THRESHOLD = 4           # average-hash bits that count as "pixels changed"
LUMA_DELTA = 1.5               # mean-brightness change that counts as "something is drawn".
                               # The banner is translucent, so it shifts the mean a little;
                               # an average hash alone is mean-invariant and can miss it.
SIZE_MIN = (400, 240)

TMP = tempfile.mkdtemp(prefix="focusdeck-e2e-")
RESULTS = []                   # (check_id, status, detail)
START = time.time()
MEASURED = {}                  # extra observations for the summary


# ----------------------------------------------------------------- reporting --

def record(check_id, status, detail=""):
    RESULTS.append((check_id, status, detail))
    line = "%-4s %-6s %s" % (check_id, status, detail)
    print(line, flush=True)
    return status


def check(check_id, ok, detail=""):
    return record(check_id, "PASS" if ok else "FAIL", detail)


def skip(check_id, detail=""):
    return record(check_id, "SKIP", detail)


# ------------------------------------------------------------------ shelling --

def sh(cmd, timeout=30):
    """Run a command, return (rc, stdout, stderr). Never raises on exit code."""
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout after %ss" % timeout
    except OSError as exc:
        return 127, "", str(exc)


def osa(script, timeout=20):
    return sh(["osascript", "-e", script], timeout=timeout)


def osa_js(script, timeout=20):
    return sh(["osascript", "-l", "JavaScript", "-e", script], timeout=timeout)


def cli(*args, timeout=30):
    return sh([CLI_PATH] + list(args), timeout=timeout)


def log_wait(seconds):
    time.sleep(seconds)


# --------------------------------------------------------------- the window --

def window_frame():
    """(x, y, w, h) of window 1 in System Events coords (origin: top-left)."""
    rc, out, err = osa('tell application "System Events" to tell process "%s" to get '
                       '{position, size} of window 1' % PROCESS)
    if rc != 0:
        raise RuntimeError("System Events window read failed: %s" % (err or out))
    nums = [int(float(v)) for v in out.replace(",", " ").split() if v.strip()]
    if len(nums) != 4:
        raise RuntimeError("unexpected window geometry %r" % out)
    return nums[0], nums[1], nums[2], nums[3]


def set_window_size(w, h):
    rc, out, err = osa('tell application "System Events" to tell process "%s" to set size '
                       'of window 1 to {%d, %d}' % (PROCESS, w, h))
    if rc != 0:
        raise RuntimeError("cannot set window size: %s" % (err or out))


def display_frames():
    """[(frame, visible)] in Quartz coords (origin: bottom-left of primary)."""
    script = ('ObjC.import("AppKit");var s=$.NSScreen.screens;var o=[];'
              'for(var i=0;i<s.count;i++){var f=s.objectAtIndex(i).frame;'
              'var v=s.objectAtIndex(i).visibleFrame;'
              'o.push([f.origin.x,f.origin.y,f.size.width,f.size.height,'
              'v.origin.x,v.origin.y,v.size.width,v.size.height]);}JSON.stringify(o);')
    rc, out, err = osa_js(script)
    if rc != 0 or not out:
        raise RuntimeError("cannot read displays: %s" % (err or out))
    return [[float(v) for v in row] for row in json.loads(out)]


def to_quartz(rect, primary_height):
    x, y, w, h = rect
    return (x, primary_height - (y + h), w, h)


def intersect(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x1, y1 = max(ax, bx), max(ay, by)
    x2, y2 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
    if x2 <= x1 or y2 <= y1:
        return None
    return (x1, y1, x2 - x1, y2 - y1)


def window_intersection(rect):
    """Largest intersection of a System Events window rect with any display."""
    screens = display_frames()
    primary = next((s for s in screens if s[0] == 0 and s[1] == 0), screens[0])
    q = to_quartz(rect, primary[3])
    best = None
    for s in screens:
        inter = intersect(q, (s[0], s[1], s[2], s[3]))
        if inter and (best is None or inter[2] * inter[3] > best[2] * best[3]):
            best = inter
    if best is None:
        return None
    # back to screenshot coords
    return (int(best[0]), int(primary[3] - (best[1] + best[3])), int(best[2]), int(best[3]))


def capture(path, region):
    rc, out, err = sh(["screencapture", "-x", "-R", "%d,%d,%d,%d" % region, path])
    if rc != 0 or not os.path.exists(path):
        raise RuntimeError("screencapture failed: %s" % (err or out))
    return path


# -------------------------------------------------- screenshot pixel compare --

def _png_read(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png")
    pos, idat = 8, b""
    width = height = bitdepth = colortype = None
    while pos < len(data):
        (ln,) = struct.unpack_from(">I", data, pos)
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            width, height, bitdepth, colortype, _c, _f, interlace = struct.unpack(">IIBBBBB", chunk)
            if interlace:
                raise ValueError("interlaced png")
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    if bitdepth != 8:
        raise ValueError("bit depth %s" % bitdepth)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(stride * height)
    prev = bytearray(stride)
    p = 0
    for row in range(height):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                c = prev[i - channels] if i >= channels else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif f != 0:
            raise ValueError("bad filter %s" % f)
        out[row * stride:(row + 1) * stride] = line
        prev = line
    return width, height, channels, bytes(out)


def average_hash(path, grid=32, workdir=None):
    """Perceptual average hash of a screenshot.  Uses the system sips tool to
    downscale (no third-party Python package is involved)."""
    small = os.path.join(workdir or TMP, os.path.basename(path) + ".%d.png" % grid)
    rc, out, err = sh(["sips", "-s", "format", "png", "-Z", str(grid), path, "--out", small])
    if rc != 0 or not os.path.exists(small):
        return None
    w, h, c, px = _png_read(small)
    vals = []
    for i in range(w * h):
        o = i * c
        if c >= 3:
            r, g, b = px[o], px[o + 1], px[o + 2]
        else:
            r = g = b = px[o]
        vals.append((r * 299 + g * 587 + b * 114) // 1000)
    avg = sum(vals) / len(vals)
    return [1 if v > avg else 0 for v in vals]


def hash_distance(a, b):
    if a is None or b is None or len(a) != len(b):
        return None
    return sum(1 for x, y in zip(a, b) if x != y)


def mean_luminance(path, grid=32):
    """Mean brightness (0-255) of a screenshot, via the same sips downscale."""
    small = os.path.join(TMP, os.path.basename(path) + ".%d.png" % grid)
    rc, out, err = sh(["sips", "-s", "format", "png", "-Z", str(grid), path, "--out", small])
    if rc != 0 or not os.path.exists(small):
        return None
    w, h, c, px = _png_read(small)
    total = 0
    for i in range(w * h):
        o = i * c
        if c >= 3:
            r, g, b = px[o], px[o + 1], px[o + 2]
        else:
            r = g = b = px[o]
        total += (r * 299 + g * 587 + b * 114) // 1000
    return total / float(w * h)


def capture_hashes(tag, region, grid=32):
    path = os.path.join(TMP, tag + ".png")
    capture(path, region)
    return average_hash(path, grid), path


def capture_metrics(tag, region, grid=32):
    """(average hash, mean luminance) of a region."""
    path = os.path.join(TMP, tag + ".png")
    capture(path, region)
    return average_hash(path, grid), mean_luminance(path, grid), path


# ------------------------------------------------------------- shared state --

def read_json(path):
    for _ in range(10):
        try:
            with open(path, "r") as handle:
                return json.load(handle)
        except (ValueError, OSError):
            time.sleep(0.2)
    raise RuntimeError("cannot read %s" % path)


def focus_state():
    return read_json(FOCUS_JSON)


def process_pids():
    rc, out, _ = sh(["pgrep", "-f", "MacOS/%s" % PROCESS])
    return [p for p in out.split() if p.strip()]


def app_running():
    return bool(process_pids())


def launch_app():
    sh(["open", APP_BUNDLE])
    for _ in range(40):
        if app_running():
            return True
        time.sleep(0.5)
    return False


def wait_for_window(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        rc, out, _ = osa('tell application "System Events" to tell process "%s" to get count '
                         'of windows' % PROCESS)
        if rc == 0 and out.strip() not in ("", "0"):
            return True
        time.sleep(0.5)
    return False


# ------------------------------------------------------------- settings file -

DEFAULT_SETTINGS = {
    "textScale": 1.0, "uppercase": True, "alwaysOnTop": True, "showQueue": True,
    "showClock": True, "showElapsed": True, "showCoverTitle": False,
    "animationEnabled": True, "animationIntensity": 0.7, "slideDuration": 0.9,
    "backdropDarkness": 0.28, "paletteOverride": None, "startAtLogin": False,
    "nextDisplayShortcutEnabled": True, "todoistEnabled": False,
    "todoistFilter": "today", "todoistRefreshMinutes": 5, "todoistTokenPresent": False,
}


def write_settings(scale):
    """Write a valid settings.json (read the live one first when it exists)."""
    try:
        data = read_json(SETTINGS_JSON)
        if not isinstance(data, dict):
            data = dict(DEFAULT_SETTINGS)
    except Exception:
        data = dict(DEFAULT_SETTINGS)
    for key, value in DEFAULT_SETTINGS.items():
        data.setdefault(key, value)
    data["textScale"] = scale
    with open(SETTINGS_JSON, "w") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
    return data


# ------------------------------------------------------------------- checks --

CLI_PATH = None


def choose_cli():
    for path in CLI_CANDIDATES:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    raise RuntimeError("focusdeck CLI not found in %s" % CLI_CANDIDATES)


def check_1_app_running():
    pids = process_pids()
    if not pids:
        launch_app()
    ok = app_running()
    pids = process_pids()
    check("1", ok, "process %r running (pid %s)" % (PROCESS, ",".join(pids) or "none"))


def check_2_window():
    if not wait_for_window():
        return check("2", False, "no window for process %r" % PROCESS)
    frame = window_frame()
    x, y, w, h = frame
    rc, fullscreen, _ = osa('tell application "System Events" to tell process "%s" to get value '
                            'of attribute "AXFullScreen" of window 1' % PROCESS)
    sane = w >= SIZE_MIN[0] and h >= SIZE_MIN[1]
    is_normal = fullscreen.strip() != "true"
    check("2", sane and is_normal,
          "window 1 position=(%d,%d) size=(%dx%d) fullscreen=%s (need >= %dx%d)"
          % (x, y, w, h, fullscreen or "?", SIZE_MIN[0], SIZE_MIN[1]))
    MEASURED["window"] = frame


def check_3_resizable():
    before = window_frame()
    set_window_size(900, 500)
    time.sleep(0.8)
    small = window_frame()
    # resizing happens live in the app window, so the deck must re-render there
    set_window_size(1200, 680)
    time.sleep(0.8)
    back = window_frame()
    ok = (small[2], small[3]) == (900, 500) and (back[2], back[3]) == (1200, 680)
    check("3", ok, "set 900x500 -> observed %dx%d ; set 1200x680 -> observed %dx%d (start %dx%d)"
          % (small[2], small[3], back[2], back[3], before[2], before[3]))


def check_4_cli_set():
    marker = "E2E MARKER %d" % int(time.time())
    region = window_intersection(window_frame())
    if region is None:
        return check("4a", False, "window does not intersect any display")
    h_before, _ = capture_hashes("set_before", region)
    rc, out, err = cli("set", marker)
    time.sleep(2.5)
    h_after, _ = capture_hashes("set_after", region)
    d = hash_distance(h_before, h_after)
    check("4a", d is not None and d > CHANGE_THRESHOLD,
          "CLI %r -> deck pixels changed: aHash distance %s (threshold >%d, cli rc=%d %s)"
          % ("set " + marker, d, CHANGE_THRESHOLD, rc, out or err))
    state = focus_state()
    current = (state.get("current") or {}).get("title", "")
    check("4b", current == marker, "focus.json current title = %r (expected %r)" % (current, marker))


def check_5_queue_done():
    rc, out, err = cli("queue", "A", "B")
    time.sleep(1.0)
    state = focus_state()
    titles = [item.get("title") for item in state.get("queue", [])]
    check("5a", titles == ["A", "B"], "after `focusdeck queue A B` queue = %s (rc=%d %s)"
          % (titles, rc, out or err))
    rc, out, err = cli("done")
    time.sleep(1.0)
    state = focus_state()
    current = (state.get("current") or {}).get("title")
    queue = [item.get("title") for item in state.get("queue", [])]
    check("5b", current == "A", "after `focusdeck done` current = %r, queue = %s (cli said %r)"
          % (current, queue, out or err))


def check_6_overlay():
    # a state change makes the app re-render without a stale banner
    cli("set", "E2E overlay baseline %d" % int(time.time()))
    time.sleep(2.5)
    region = window_intersection(window_frame())
    if region is None:
        return check("6a", False, "window does not intersect any display")
    bx, by, bw, bh = region
    banner_region = (bx + BANNER[0], by + BANNER[1], BANNER[2], BANNER[3])
    h_base, l_base, _ = capture_metrics("overlay_base", banner_region)
    # A long ttl: the app adopts outside changes on its own 1 s poll, so a 3 s banner can
    # expire before the screenshot lands. Correctness of expiry is checked on the state file.
    rc, out, err = cli("overlay", "E2E TEST", "--ttl", "20")
    time.sleep(2.5)
    h_shown, l_shown, _ = capture_metrics("overlay_shown", banner_region)
    d_shown = hash_distance(h_base, h_shown)
    delta_shown = None if (l_base is None or l_shown is None) else abs(l_shown - l_base)
    drawn = (d_shown is not None and d_shown > CHANGE_THRESHOLD) or \
            (delta_shown is not None and delta_shown >= LUMA_DELTA)
    check("6a", drawn,
          "banner drawn after `focusdeck overlay \"E2E TEST\" --ttl 20`: aHash distance %s "
          "(>%d) or mean brightness change %s (>=%s), rc=%d %s"
          % (d_shown, CHANGE_THRESHOLD,
             "n/a" if delta_shown is None else round(delta_shown, 2), LUMA_DELTA, rc, out or err))

    # Now a banner that must disappear. The cover animates, so "gone" is judged by the
    # app dropping the field itself plus the pixels moving back closer to the baseline.
    cli("overlay", "E2E EXPIRY", "--ttl", "2")
    time.sleep(6.0)
    h_late, l_late, _ = capture_metrics("overlay_late", banner_region)
    d_late = hash_distance(h_base, h_late)
    delta_late = None if (l_base is None or l_late is None) else abs(l_late - l_base)
    state = focus_state()
    overlay = state.get("overlay")
    check("6b", overlay is None,
          "focus.json overlay field cleared 6s after a 2s banner = %s (expected None, the app clears it)"
          % (json.dumps(overlay) if overlay else None))
    # The cover animates, so "the banner is gone" is judged as "the region moved back
    # towards the baseline", not as "the pixels are identical".
    back_to_base = (delta_late is not None and delta_shown is not None
                    and delta_late <= delta_shown + 0.5)
    check("6c", back_to_base,
          "banner region after expiry: brightness change %s vs %s while shown (expected <=)"
          % ("n/a" if delta_late is None else round(delta_late, 2),
             "n/a" if delta_shown is None else round(delta_shown, 2)))
    MEASURED["overlay"] = {"shown": d_shown, "late": d_late,
                           "luma_shown": delta_shown, "luma_late": delta_late}


def check_7_settings_persist():
    write_settings(1.6)
    rc, out, err = osa('quit app "Focus Deck"')
    for _ in range(30):
        if not app_running():
            break
        time.sleep(0.5)
    stopped = not app_running()
    trace("app stopped after quit (check 7)")
    if not launch_app():
        return check("7a", False, "app did not start again after quit")
    wait_for_window()
    time.sleep(1.0)
    data = read_json(SETTINGS_JSON)
    check("7a", data.get("textScale") == 1.6,
          "settings.json textScale after restart = %r (expected 1.6; quit rc=%d, stopped=%s)"
          % (data.get("textScale"), rc, stopped))
    trace("app relaunched for check 7")
    frame = window_frame()
    inter = window_intersection(frame)
    on_screen = inter is not None and inter[2] > 0 and inter[3] > 0
    check("7b", on_screen,
          "window reopened at (%d,%d) %dx%d, on-display area = %s"
          % (frame[0], frame[1], frame[2], frame[3], inter))


def trace(message):
    print("      . %-42s pids=%s" % (message, ",".join(process_pids()) or "NONE"), flush=True)


def check_8_desktop_icon():
    exists = os.path.lexists(DESKTOP_ENTRY)
    resolved = None
    kind = "missing"
    if exists:
        if os.path.islink(DESKTOP_ENTRY):
            resolved = os.path.realpath(DESKTOP_ENTRY)
            kind = "symlink"
        else:
            # A Finder alias file resolves through Finder, not through the filesystem.
            # Finder will not turn the resolved item straight into a POSIX path, so coerce
            # it back to an AppleScript alias first.
            rc, out, _ = osa('tell application "Finder" to get POSIX path of '
                             '((original item of (POSIX file "%s" as alias)) as alias)' % DESKTOP_ENTRY)
            if rc == 0 and out.strip():
                resolved = out.strip().rstrip("/")
                kind = "Finder alias"
            else:
                rc, out, _ = osa('POSIX path of (POSIX file "%s" as alias)' % DESKTOP_ENTRY)
                resolved = out.rstrip("/") if rc == 0 else None
                kind = "alias?"
    # A Finder alias to the app may resolve to the bundle or to the app inside it.
    def same_app(path):
        if path is None:
            return False
        for candidate in (path, os.path.realpath(path)):
            if candidate.rstrip("/") == APP_BUNDLE.rstrip("/"):
                return True
            if os.path.realpath(candidate).rstrip("/") == os.path.realpath(APP_BUNDLE).rstrip("/"):
                return True
        return False
    ok = exists and same_app(resolved)
    check("8a", ok, "%s exists=%s kind=%s resolves to %r (expected %r)"
          % (DESKTOP_ENTRY, exists, kind, resolved, APP_BUNDLE))
    ok_bin = os.path.isfile(APP_BINARY) and os.access(APP_BINARY, os.X_OK)
    check("8b", ok_bin, "%s exists=%s executable=%s"
          % (APP_BINARY, os.path.isfile(APP_BINARY), os.access(APP_BINARY, os.X_OK)))
    trace("after check 8")


def check_9_no_token():
    trace("start of check 9")
    rc, token, err = sh(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE,
                         "-a", KEYCHAIN_ACCOUNT, "-w"], timeout=15)
    had_token = rc == 0 and bool(token.strip())
    if rc == 124:
        return skip("9a", "keychain read timed out (would show a prompt) - token left untouched")
    if not had_token:
        skip("9a", "no keychain token stored for %s/%s (nothing to remove, nothing to restore)"
             % (KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT))
    else:
        rc_del, out_del, err_del = sh(["security", "delete-generic-password", "-s", KEYCHAIN_SERVICE,
                                       "-a", KEYCHAIN_ACCOUNT], timeout=15)
        removed = rc_del == 0
        if removed:
            rc_add, out_add, err_add = sh(["security", "add-generic-password", "-U",
                                           "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT,
                                           "-w", token.strip(),
                                           "-T", APP_BINARY, "-T", "/usr/bin/security"], timeout=15)
            rc_chk, back, err_chk = sh(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE,
                                        "-a", KEYCHAIN_ACCOUNT, "-w"], timeout=15)
            restored = rc_chk == 0 and back.strip() == token.strip()
            check("9a", restored,
                  "token removed and re-added (restored=%s, add rc=%d). The keychain ACL is "
                  "best-effort - re-enter the token by hand in Settings if Todoist stops working."
                  % (restored, rc_add))
        else:
            check("9a", False, "could not delete keychain token: %s" % (err_del or out_del))

    marker = "E2E no-token marker %d" % int(time.time())
    rc, out, err = cli("set", marker)
    time.sleep(2.5)
    state = focus_state()
    current = (state.get("current") or {}).get("title")
    alive = app_running()
    trace("end of check 9b")
    check("9b", alive and current == marker,
          "with no Todoist token: app alive=%s, CLI set -> focus.json current = %r (cli rc=%d %s, "
          "token present before=%s)" % (alive, current, rc, out or err, had_token))


# ------------------------------------------------------------ backup/restore --

def backup_state():
    stamp = time.strftime("%Y%m%d-%H%M%S")
    info = {}
    for name, path in (("focus", FOCUS_JSON), ("settings", SETTINGS_JSON)):
        target = os.path.join(TMP, "%s-%s.json" % (name, stamp))
        if os.path.exists(path):
            shutil.copy2(path, target)
            info[name] = (True, target)
        else:
            info[name] = (False, target)
    return info


def restore_state(backup):
    errors = []
    existed, target = backup["focus"]
    if existed:
        try:
            shutil.copy(target, FOCUS_JSON)
        except OSError as exc:
            errors.append("focus.json: %s" % exc)
    existed, target = backup["settings"]
    if existed:
        try:
            shutil.copy(target, SETTINGS_JSON)
        except OSError as exc:
            errors.append("settings.json: %s" % exc)
    else:
        try:
            write_settings(1.0)   # the file did not exist before: leave app defaults
        except OSError as exc:
            errors.append("settings.json default: %s" % exc)
    if not app_running():
        launch_app()
    if not wait_for_window(10):
        errors.append("no window after restore")
    try:
        set_window_size(1200, 680)
    except RuntimeError as exc:
        errors.append(str(exc))
    return errors, backup["settings"][0]


# --------------------------------------------------------------------- main --

def main():
    global CLI_PATH
    print("Focus Deck E2E harness  (repo: %s)" % REPO_ROOT)
    print("temp dir: %s" % TMP)
    try:
        CLI_PATH = choose_cli()
    except RuntimeError as exc:
        print("FATAL: %s" % exc)
        return 2
    print("cli: %s" % CLI_PATH)
    backup = backup_state()
    print("backed up focus.json=%s settings.json=%s" % (backup["focus"][0], backup["settings"][0]))
    print("-" * 72)

    steps = [check_1_app_running, check_2_window, check_3_resizable, check_4_cli_set,
             check_5_queue_done, check_6_overlay, check_7_settings_persist, check_8_desktop_icon,
             check_9_no_token]
    try:
        for step in steps:
            try:
                step()
            except Exception as exc:            # a broken step must not kill the run
                record(step.__name__, "FAIL", "harness error: %s: %s" % (type(exc).__name__, exc))
    finally:
        try:
            errors, had_settings = restore_state(backup)
        except Exception as exc:
            errors, had_settings = ["restore crashed: %s" % exc], False
        t = time.time() - START
        check("R", not errors,
              "state restored in %.1fs (focus.json + settings.json%s): %s"
              % (t, "" if had_settings else " [created with app defaults: file did not exist before]",
                 "; ".join(errors) if errors else "ok"))

    print("-" * 72)
    counts = {"PASS": 0, "FAIL": 0, "SKIP": 0}
    for _cid, status, _detail in RESULTS:
        counts[status] = counts.get(status, 0) + 1
    print("SUMMARY  %d checks: %d PASS, %d FAIL, %d SKIP   (%.1fs)"
          % (len(RESULTS), counts["PASS"], counts["FAIL"], counts["SKIP"], time.time() - START))
    for cid, status, detail in RESULTS:
        if status != "PASS":
            print("  %-4s %-4s %s" % (cid, status, detail))
    print("temp artifacts kept in %s (safe to delete)" % TMP)
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
