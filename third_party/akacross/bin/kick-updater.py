#!/usr/bin/env python3
"""Start FiveM Enhanced's updater and report the WebView2 state accurately.

The FiveM page's safePost({type: 'ready'}) is a no-op in this setup because
the client clears window.chrome.webview after capturing its native bridge.
invokeNative('retryUpdates') is the same action as the launcher's Retry button.
This helper only operates the launcher's updater; it does not authenticate or
connect to a game server.
"""
from __future__ import annotations

import json
import socket
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cdp import WS, targets  # noqa: E402

TARGET_DEADLINE_SECONDS = 120
EVALUATION_TIMEOUT_SECONDS = 5


def page():
    """Find the FiveM launcher page, not an unrelated/blank WebView2 target."""
    deadline = time.monotonic() + TARGET_DEADLINE_SECONDS
    last_error = None
    while time.monotonic() < deadline:
        try:
            pages = [
                item for item in targets()
                if item.get("type") == "page" and item.get("webSocketDebuggerUrl")
            ]
            if pages:
                fivem_pages = [
                    item for item in pages
                    if "fivem" in (item.get("title", "") + " " + item.get("url", "")).lower()
                    or "cfx" in (item.get("title", "") + " " + item.get("url", "")).lower()
                ]
                if len(fivem_pages) == 1:
                    return fivem_pages[0]
                if len(pages) == 1:
                    return pages[0]
                if len(fivem_pages) > 1:
                    # Prefer a visible launcher URL over about:blank/devtools pages.
                    fivem_pages.sort(key=lambda item: (
                        item.get("url", "").startswith("about:"),
                        not bool(item.get("title")),
                    ))
                    return fivem_pages[0]
                last_error = "multiple WebView2 pages found, none identified as FiveM"
            else:
                last_error = "no WebView2 page target found"
        except Exception as exc:  # transient while WebView2 starts
            last_error = str(exc)
        time.sleep(2)
    raise RuntimeError(
        f"FiveM WebView2 DevTools did not become available in "
        f"{TARGET_DEADLINE_SECONDS}s ({last_error or 'unknown reason'}). "
        "Check that WebView2 remote debugging is enabled."
    )


def ev(ws: WS, expression: str, timeout: float = EVALUATION_TIMEOUT_SECONDS):
    """Evaluate JavaScript, preserving CDP exceptions and timeouts."""
    request_id = ws.send(
        "Runtime.evaluate",
        expression=expression,
        returnByValue=True,
        awaitPromise=True,
    )
    deadline = time.monotonic() + timeout
    old_timeout = ws.s.gettimeout()
    try:
        ws.s.settimeout(min(1.0, timeout))
        while time.monotonic() < deadline:
            try:
                message = ws.recv()
            except socket.timeout:
                continue
            if not isinstance(message, dict) or message.get("id") != request_id:
                # Ignore asynchronous CDP events and responses to other requests.
                continue
            result = message.get("result", {})
            if result.get("exceptionDetails"):
                details = result["exceptionDetails"]
                exception = details.get("exception", {})
                description = exception.get("description") or details.get("text")
                raise RuntimeError(f"WebView2 JavaScript evaluation failed: {description}")
            remote = result.get("result", {})
            return remote.get("value")
    finally:
        ws.s.settimeout(old_timeout)
    raise TimeoutError(f"Timed out evaluating WebView2 expression: {expression[:80]}")


def main() -> int:
    ws = None
    try:
        target = page()
        ws = WS(target["webSocketDebuggerUrl"])

        # Wait for the launcher's bridge to exist. Keep each CDP request short.
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            try:
                bridge_type = ev(ws, "typeof window.invokeNative", timeout=3)
                if bridge_type == "function":
                    break
            except (TimeoutError, RuntimeError, ConnectionError, OSError):
                pass
            time.sleep(1)
        else:
            raise RuntimeError(
                "The FiveM page did not expose window.invokeNative. "
                "The updater was not triggered."
            )

        state = ev(
            ws,
            "({url: location.href, title: document.title, "
            "body: (document.body?.innerText || '').trim()})",
        )
        body = state.get("body", "") if isinstance(state, dict) else ""
        if "INITIALIZING UPDATER" not in body.upper():
            summary = body.splitlines()[0][:120] if body else "(no visible page text)"
            print(f"kick-updater: updater already moved on; {summary}")
            return 0

        ev(ws, "window.invokeNative('retryUpdates')")
        time.sleep(3)
        try:
            updated = ev(
                ws,
                "({url: location.href, title: document.title, "
                "body: (document.body?.innerText || '').trim()})",
            )
        except (TimeoutError, RuntimeError, ConnectionError, OSError) as exc:
            print(
                "kick-updater: retryUpdates was sent, but WebView2 status "
                f"could not be read ({exc}). This is not a server-authentication result."
            )
            return 0

        text = updated.get("body", "") if isinstance(updated, dict) else ""
        if text:
            summary = " | ".join(text.splitlines())[:180]
            print(f"kick-updater: retryUpdates sent; updater page says: {summary}")
        else:
            title = updated.get("title", "") if isinstance(updated, dict) else ""
            print(
                "kick-updater: retryUpdates sent; WebView2 returned no visible body text"
                + (f" (title: {title})" if title else "")
                + ". This helper does not test Cfx authentication services."
            )
        return 0
    except Exception as exc:
        print(f"kick-updater: {exc}", file=sys.stderr)
        return 1
    finally:
        if ws is not None:
            try:
                ws.s.close()
            except OSError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
