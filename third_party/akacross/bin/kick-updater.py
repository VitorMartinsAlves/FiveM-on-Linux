#!/usr/bin/env python3
"""Nudge the FiveM Enhanced launcher into starting its update run.

The launcher's page announces itself with safePost({type:'ready'}), which goes
through window.chrome.webview.postMessage. FiveM's own document-created script
captures that bridge into a closure and then sets chrome.webview = null, so
safePost is a no-op and the 'ready' message never reaches native — the UI sits
at "INITIALIZING UPDATER... 0%" forever.

invokeNative() closes over the captured bridge, so it still works. Calling
invokeNative('retryUpdates') is exactly what the UI's Retry button does and
starts the update flow normally.
"""
import sys, time
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from cdp import targets, WS

DEADLINE = time.time() + 120

def page():
    while time.time() < DEADLINE:
        try:
            p = [t for t in targets() if t.get("type") == "page"]
            if p:
                return p[0]
        except Exception:
            pass
        time.sleep(2)
    return None

def ev(ws, expr):
    i = ws.send("Runtime.evaluate", expression=expr, returnByValue=True)
    d = time.time() + 12
    while time.time() < d:
        m = ws.recv()
        if m.get("id") == i:
            return m.get("result", {}).get("result", {}).get("value")
    return None

t = page()
if not t:
    sys.exit("launcher devtools never came up (is bin/enable-devtools.sh 1 set?)")
ws = WS(t["webSocketDebuggerUrl"])

# wait for the page to finish loading its script
for _ in range(30):
    if ev(ws, "typeof window.invokeNative") == "function":
        break
    time.sleep(1)
else:
    sys.exit("invokeNative never appeared")

body = ev(ws, "document.body.innerText") or ""
if "INITIALIZING UPDATER" not in body.upper():
    print(f"launcher already moving: {body.splitlines()[0] if body else '?'}")
    sys.exit(0)

ev(ws, "window.invokeNative('retryUpdates')")
time.sleep(3)
print("kicked:", (ev(ws, "document.body.innerText.replace(/\\n/g,' | ')") or "?")[:100])
