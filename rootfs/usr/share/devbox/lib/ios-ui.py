"""devbox ios ui <command>: the app on the device driven through WebDriverAgent.

WebDriverAgent answers on http://127.0.0.1:8100 and streams the screen on
:9100 once `devbox ios ui start` runs. Points, not pixels: a tap at 195 785
is the middle of the bottom of a 390x844 screen (labels shows every rect).

  session <bundle id>        opens a session on the app, launched if needed;
                             every command below uses it
  activate <bundle id>       brings an installed app back to the foreground
                             (a link opened in Safari or Chrome, for example)
  labels                     what is on screen: type, rect x,y wxh, label
  find <class>               the elements of an XCUIElementType (TextField,
                             Button...) with their rects, for what labels
                             leaves out (a field inside a sheet)
  tap <text> [n]             taps the n-th (0) element whose label or name
                             contains <text>
  tapxy <x> <y>              taps a point
  swipe <x1> <y1> <x2> <y2>  drags from one point to the other
  type <text>                types into the focused field (tap it first)
  alert [accept|dismiss]     the text of the system alert shown, or answers it
  shot <file.png>            screenshot, full resolution
  record <seconds> <dir>     the screen at about 30 images a second (MJPEG,
                             half size), one JPEG a frame named
                             <n>-<time>.jpg: for an animation or a jump
                             that screenshots, a second apart, miss

The session is kept in $IOS_UI_DIR/session (devbox ios ui sets it).
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

PORT = int(os.environ.get("IOS_UI_PORT", "8100"))
MJPEG_PORT = int(os.environ.get("IOS_UI_MJPEG_PORT", "9100"))
BASE = f"http://127.0.0.1:{PORT}"
STATE = os.environ.get("IOS_UI_DIR", os.path.expanduser("~/.cache/dev-box/ios-ui"))
SESSION_FILE = os.path.join(STATE, "session")


def call(method, path, body=None, timeout=60, fail=True):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        reply = json.loads(error.read() or b"{}")
        if not fail:
            return {}
        sys.exit(f"WebDriverAgent: {reply.get('value', {}).get('message', reply)}")


def session():
    try:
        return open(SESSION_FILE).read().strip()
    except OSError:
        sys.exit("no session: devbox ios ui session <bundle id> first")


def in_session(method, path, body=None, timeout=60):
    return call(method, f"/session/{session()}{path}", body, timeout).get("value")


def element_id(element):
    return element.get("ELEMENT") or element.get("element-6066-11e4-a52e-4f735466cecf")


def walk(node, out):
    if node.get("label") or node.get("name"):
        out.append(node)
    for child in node.get("children") or []:
        walk(child, out)


def short_type(kind):
    kind = kind or ""
    return kind[len("XCUIElementType"):] if kind.startswith("XCUIElementType") else kind


def rect_text(r):
    return f'{r.get("x", 0):>5},{r.get("y", 0):>5} {r.get("width", 0):>4}x{r.get("height", 0):<4}'


def cmd_session(bundle_id):
    reply = call("POST", "/session", {"capabilities": {"alwaysMatch": {"bundleId": bundle_id, "shouldWaitForQuiescence": False}}}, timeout=120)
    sid = reply.get("sessionId") or reply.get("value", {}).get("sessionId")
    if not sid:
        sys.exit(f"no session: {reply}")
    os.makedirs(STATE, exist_ok=True)
    open(SESSION_FILE, "w").write(sid)
    # The MJPEG stream of record: close to 30 images a second, half size
    in_session("POST", "/appium/settings", {"settings": {"mjpegServerFramerate": 30, "mjpegScalingFactor": 50, "mjpegServerScreenshotQuality": 40}})
    print("session", sid, "on", bundle_id)


def cmd_activate(bundle_id):
    in_session("POST", "/wda/apps/activate", {"bundleId": bundle_id})
    print("foreground:", bundle_id)


def cmd_labels():
    nodes = []
    walk(call("GET", "/source?format=json")["value"], nodes)
    for n in nodes:
        print(f'{short_type(n.get("type")):<14} {rect_text(n.get("rect") or {})} {(n.get("label") or n.get("name"))[:90]}')


def cmd_find(kind):
    kind = kind if kind.startswith("XCUIElementType") else "XCUIElementType" + kind
    for element in in_session("POST", "/elements", {"using": "class name", "value": kind}):
        rect = in_session("GET", f"/element/{element_id(element)}/rect")
        print(short_type(kind), rect_text(rect))


def cmd_tap(text, index="0"):
    quoted = text.replace("\\", "\\\\").replace("'", "\\'")
    found = in_session("POST", "/elements", {"using": "predicate string", "value": f"label CONTAINS '{quoted}' OR name CONTAINS '{quoted}'"})
    if len(found) <= int(index):
        sys.exit(f"not on screen: {text} (devbox ios ui labels)")
    in_session("POST", f"/element/{element_id(found[int(index)])}/click", {})
    print("tapped:", text)


def cmd_tapxy(x, y):
    in_session("POST", "/wda/tap", {"x": float(x), "y": float(y)})
    print("tapped", x, y)


def cmd_swipe(x1, y1, x2, y2):
    in_session("POST", "/wda/dragfromtoforduration", {"fromX": float(x1), "fromY": float(y1), "toX": float(x2), "toY": float(y2), "duration": 0.2})
    print("swiped")


def cmd_type(text):
    in_session("POST", "/wda/keys", {"value": list(text)})
    print("typed")


def cmd_alert(answer=None):
    if answer is None:
        reply = call("GET", f"/session/{session()}/alert/text", fail=False)
        print(reply.get("value") or "no alert")
    elif answer in ("accept", "dismiss"):
        in_session("POST", f"/alert/{answer}", {})
        print("alert:", answer)
    else:
        sys.exit("alert [accept|dismiss]")


def cmd_shot(path):
    open(path, "wb").write(base64.b64decode(call("GET", "/screenshot")["value"]))
    print(path)


def cmd_record(seconds, out):
    os.makedirs(out, exist_ok=True)
    stream = urllib.request.urlopen(f"http://127.0.0.1:{MJPEG_PORT}", timeout=10)
    buf, count, end = b"", 0, time.time() + float(seconds)
    while time.time() < end:
        buf += stream.read(4096)
        start = buf.find(b"\xff\xd8")
        stop = buf.find(b"\xff\xd9", start + 2) if start != -1 else -1
        if start != -1 and stop != -1:
            with open(os.path.join(out, f"{count:04d}-{time.time():.3f}.jpg"), "wb") as frame:
                frame.write(buf[start:stop + 2])
            count += 1
            buf = buf[stop + 2:]
    print(count, "frames in", out)


COMMANDS = {
    "session": cmd_session, "activate": cmd_activate, "labels": cmd_labels, "find": cmd_find,
    "tap": cmd_tap, "tapxy": cmd_tapxy, "swipe": cmd_swipe, "type": cmd_type, "alert": cmd_alert,
    "shot": cmd_shot, "record": cmd_record,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    try:
        COMMANDS[sys.argv[1]](*sys.argv[2:])
    except TypeError:
        sys.exit(__doc__)
