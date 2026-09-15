"""One-time OAuth bootstrap for Microsoft Advertising (Bing Ads).

Opens the Microsoft sign-in page, catches the redirect on the local callback URL,
exchanges the authorization code at login.microsoftonline.com and writes
MICROSOFT_ADS_ACCESS_TOKEN / MICROSOFT_ADS_REFRESH_TOKEN into the repo .env.
Nothing is printed except the token lengths and expiry.

Reads from .env: MICROSOFT_ADS_CLIENT_ID, MICROSOFT_ADS_CLIENT_SECRET,
MICROSOFT_ADS_REDIRECT_URI (must be http://localhost:<port>/<path>),
MICROSOFT_ADS_TENANT (default "common").

Usage:  python scripts/msads_oauth.py            # interactive, opens browser
        python scripts/msads_oauth.py --refresh  # rotate using the stored refresh token
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import threading
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"
SCOPE = "openid offline_access https://ads.microsoft.com/msads.manage"


def _token_url(tenant: str) -> str:
    return f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"


def _write_env(updates: dict[str, str]) -> None:
    text = ENV_PATH.read_text(encoding="utf-8")
    for key, value in updates.items():
        line = f"{key}={value}"
        if re.search(rf"^{key}=.*$", text, flags=re.M):
            text = re.sub(rf"^{key}=.*$", line, text, flags=re.M)
        else:
            text = text.rstrip("\n") + "\n" + line + "\n"
    ENV_PATH.write_text(text, encoding="utf-8")


def _exchange(tenant: str, data: dict[str, str]) -> dict:
    r = requests.post(_token_url(tenant), data=data, timeout=30)
    if r.status_code != 200:
        body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        sys.exit(f"token endpoint {r.status_code}: {body.get('error')} - {body.get('error_description', '')[:300]}")
    return r.json()


def _capture_code(redirect_uri: str, auth_url: str, timeout: int = 300) -> str:
    parsed = urllib.parse.urlparse(redirect_uri)
    port = parsed.port or 80
    result: dict[str, str] = {}
    done = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if "code" in qs:
                result["code"] = qs["code"][0]
                msg = "Authorization received - you can close this tab."
            else:
                result["error"] = qs.get("error_description", qs.get("error", ["no code"]))[0]
                msg = "Authorization failed: " + result["error"]
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(msg.encode())
            done.set()

        def log_message(self, *_):  # silence
            pass

    server = HTTPServer(("localhost", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"listening on {redirect_uri}; opening browser ...")
    webbrowser.open(auth_url)
    if not done.wait(timeout):
        server.shutdown()
        sys.exit("timed out waiting for the redirect")
    server.shutdown()
    if "error" in result:
        sys.exit("authorization error: " + result["error"])
    return result["code"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="use the stored refresh token instead of the browser")
    args = ap.parse_args()

    load_dotenv(ENV_PATH)
    client_id = os.environ["MICROSOFT_ADS_CLIENT_ID"]
    client_secret = os.environ["MICROSOFT_ADS_CLIENT_SECRET"]
    redirect_uri = os.environ["MICROSOFT_ADS_REDIRECT_URI"]
    tenant = os.environ.get("MICROSOFT_ADS_TENANT", "common")

    if args.refresh:
        refresh = os.environ.get("MICROSOFT_ADS_REFRESH_TOKEN")
        if not refresh:
            sys.exit("MICROSOFT_ADS_REFRESH_TOKEN not set")
        tok = _exchange(tenant, {
            "grant_type": "refresh_token", "client_id": client_id, "client_secret": client_secret,
            "refresh_token": refresh, "scope": SCOPE,
        })
    else:
        auth_url = "https://login.microsoftonline.com/%s/oauth2/v2.0/authorize?%s" % (tenant, urllib.parse.urlencode({
            "client_id": client_id, "response_type": "code", "redirect_uri": redirect_uri,
            "response_mode": "query", "scope": SCOPE, "prompt": "consent",
        }))
        code = _capture_code(redirect_uri, auth_url)
        tok = _exchange(tenant, {
            "grant_type": "authorization_code", "client_id": client_id, "client_secret": client_secret,
            "code": code, "redirect_uri": redirect_uri, "scope": SCOPE,
        })

    updates = {"MICROSOFT_ADS_ACCESS_TOKEN": tok["access_token"]}
    if tok.get("refresh_token"):
        updates["MICROSOFT_ADS_REFRESH_TOKEN"] = tok["refresh_token"]
    _write_env(updates)
    print(f"ok: access_token ({len(tok['access_token'])} chars, expires in {tok.get('expires_in')} s), "
          f"refresh_token {'written' if tok.get('refresh_token') else 'NOT returned'} -> .env")


if __name__ == "__main__":
    main()
