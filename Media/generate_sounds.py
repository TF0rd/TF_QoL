#!/usr/bin/env python3
"""
TF_QoL sound pipeline — the ONE script to run after editing Media/sounds.txt.

What it does, in order:
  1. Synthesizes every callout in Media/sounds.txt whose .ogg is still missing,
     via en.text-to-speech.online's Edge-TTS proxy (no browser, no API key).
  2. Syncs Media.lua to the Media/Sounds folder in BOTH directions:
       - registers any .ogg/.mp3 present but not yet registered
         (display name from sounds.txt, else Title Case of the filename);
       - removes registrations whose audio file was deleted.

So the full loop is just:
    add a line to sounds.txt  ->  run this script  ->  done (audio + registration)

Settings mirror the site UI defaults captured 2026-08-28:
    Jenny - US (en-US-JennyNeural), speed 0%, pitch 0%, MP3 24khz/48kbps mono.

Usage:
    python3 Media/generate_sounds.py                 # generate missing + sync Media.lua
    python3 Media/generate_sounds.py --dry-run       # preview without doing anything
    python3 Media/generate_sounds.py --force         # regenerate EVERY callout (backs up)
    python3 Media/generate_sounds.py --only "Pain"   # restrict generation to a substring

Existing files are skipped by default (no re-synthesis, no backup churn). Use
--force to rebuild them; overwritten originals are backed up to staging/backup.

Deps: requests, websockets, cryptography (all present on this LXC), ffmpeg in PATH.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

import requests
import websockets
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

# ── Config (edit to change voice/format on a future run) ──────────────────────
VOICE = "en-US-JennyNeural"          # "Jenny - US" on the site
RATE = "0%"                          # speed slider
PITCH = "0%"
VOLUME = "0%"
OUTPUT_FORMAT = "audio-24khz-48kbitrate-mono-mp3"   # the site's MP3 option
GEC_VERSION = "1-147.0.3912.98"      # fake Edge version the site sends

SITE = "https://en.text-to-speech.online"
TRUSTED_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
BASEURL_KEY = b"FreeTTSOnline2024SecretKey!!1234"  # client-side AES key
WIN_EPOCH = 11644473600
REQUEST_DELAY_S = 1.5                # politeness between generations
RETRIES = 3

# ── Paths (all relative to this script = Media/) ──────────────────────────────
MEDIA_DIR = Path(__file__).resolve().parent
SOUNDS_TXT = MEDIA_DIR / "sounds.txt"
SOUNDS_DIR = MEDIA_DIR / "Sounds"
MEDIA_LUA = MEDIA_DIR.parent / "Media.lua"
STAGING = Path(f"/tmp/tf_qol_tts/{time.strftime('%Y%m%d-%H%M%S')}")

# Media.lua registrations we never touch when sorting (pinned legacy block).
LEGACY = {"Air Horn", "Brass", "Glass", "Oh No", "Tada Fanfare",
          "Water Drop", "Kaching", "Hiccup"}
REG = re.compile(
    r'^\s*LSM:Register\(\s*"sound",\s*"(.+?)",\s*\[\[Interface\\AddOns\\TF_QoL\\Media\\Sounds\\(.+?)\]\]\)\s*$'
)


def slugify(name: str) -> str:
    """LSM file-name convention: lowercase, spaces -> hyphens, keep ' and -."""
    return re.sub(r"\s+", "-", name.strip().lower())


def display_name(slug: str) -> str:
    """Fallback name: Title Case of the file stem (sounds.txt wins when present)."""
    return " ".join(w.capitalize() for w in re.split(r"[-_ ]+", slug))


def xml_escape(text: str) -> str:
    """Same escaping the site applies before building SSML."""
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("'", "&apos;").replace('"', "&quot;"))


def sec_ms_gec() -> str:
    """Site's Sec-MS-GEC DRM token: windows-epoch seconds floored to 5 min,
    converted to 100ns ticks, concatenated with the trusted token, SHA-256."""
    a = int(time.time()) + WIN_EPOCH
    a -= a % 300
    ticks = int(a * 1e7)
    return hashlib.sha256(f"{ticks}{TRUSTED_TOKEN}".encode()).hexdigest().upper()


def decrypt_baseurl(payload_b64: str) -> dict:
    """AES-256-CBC, IV = first 16 bytes of decoded payload, PKCS7 padding."""
    raw = base64.b64decode(payload_b64)
    iv, ct = raw[:16], raw[16:]
    dec = Cipher(algorithms.AES(BASEURL_KEY), modes.CBC(iv)).decryptor()
    pt = dec.update(ct) + dec.finalize()
    return json.loads(pt[:-pt[-1]])


def get_ws_base(session: requests.Session) -> str:
    """Follow the site's own flow: fetch encrypted baseurl, decrypt, pick the
    non-Edge 'other' proxy endpoint (what a normal browser gets)."""
    r = session.get(f"{SITE}/api/index.php/baseurl", timeout=15,
                    headers={"Accept": "application/json"})
    r.raise_for_status()
    data = decrypt_baseurl(r.json()["data"])
    base = data.get("other") or data.get("edge")
    if not base:
        raise RuntimeError(f"baseurl response missing endpoints: {data}")
    return f"wss://{base}"


def report_usage(session: requests.Session) -> None:
    """Best-effort mirror of the site's per-generation quota ping (cosmetic)."""
    try:
        session.post(f"{SITE}/api/index.php/usage/consume", timeout=10,
                     json={"action": "generate"},
                     headers={"Content-Type": "application/json",
                              "Accept": "application/json"})
    except requests.RequestException:
        pass


def ts() -> str:
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


async def ws_synthesize(text: str, ws_base: str) -> bytes:
    """One WebSocket round-trip -> raw MP3 bytes."""
    conn_id = uuid.uuid4().hex.upper()
    url = (f"{ws_base}?TrustedClientToken={TRUSTED_TOKEN}"
           f"&Ocp-Apim-Subscription-Key={TRUSTED_TOKEN}"
           f"&Sec-MS-GEC={sec_ms_gec()}"
           f"&Sec-MS-GEC-Version={GEC_VERSION}"
           f"&ConnectionId={conn_id}")
    audio = b""
    async with websockets.connect(
        url, additional_headers={"Origin": SITE}, open_timeout=20, close_timeout=5
    ) as ws:
        cfg = json.dumps(
            {"context": {"synthesis": {"audio": {
                "metadataoptions": {"sentenceBoundaryEnabled": False,
                                    "wordBoundaryEnabled": True},
                "outputFormat": OUTPUT_FORMAT}}}},
            separators=(",", ":"))
        await ws.send(
            f"X-Timestamp:{ts()}\r\nContent-Type:application/json; charset=utf-8\r\n"
            f"Path:speech.config\r\n\r\n{cfg}"
        )
        ssml = (
            "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
            "xml:lang='en-US'>"
            f"<voice name='{VOICE}'><prosody pitch='{PITCH}' rate='{RATE}' "
            f"volume='{VOLUME}'>{xml_escape(text)}</prosody></voice></speak>"
        )
        await ws.send(
            f"X-RequestId:{conn_id}\r\nContent-Type:application/ssml+xml\r\n"
            f"X-Timestamp:{ts()}Z\r\nPath:ssml\r\n\r\n{ssml}"
        )
        while True:
            msg = await asyncio.wait_for(ws.recv(), timeout=30)
            if isinstance(msg, bytes):
                if len(msg) < 2:
                    continue
                hlen = int.from_bytes(msg[:2], "big")
                if len(msg) < hlen + 2:
                    continue
                headers = msg[2:2 + hlen].decode("utf-8", "replace")
                if "Path:audio" in headers:
                    audio += msg[2 + hlen:]
            elif "Path:turn.end" in msg:
                break
    if not audio:
        raise RuntimeError("no audio frames received")
    if not (audio[:3] == b"ID3" or audio[:2] == b"\xff\xfb" or audio[:2] == b"\xff\xf3"):
        raise RuntimeError(f"unexpected audio signature: {audio[:8].hex()}")
    return audio


def synthesize(text: str, ws_base: str) -> bytes:
    for attempt in range(1, RETRIES + 1):
        try:
            return asyncio.run(ws_synthesize(text, ws_base))
        except Exception as exc:  # noqa: BLE001 - report and retry
            print(f"    attempt {attempt}/{RETRIES} failed: {exc}")
            if attempt == RETRIES:
                raise
            time.sleep(2 * attempt)
    raise RuntimeError("unreachable")


def to_ogg(mp3_path: Path, ogg_path: Path) -> None:
    """MP3 -> Vorbis q4, the addon's sound format."""
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3_path),
         "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)],
        check=True, capture_output=True, text=True,
    )


def verify_ogg(ogg_path: Path) -> float:
    """Return duration in seconds; raise if not valid vorbis audio."""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "format=format_name,duration:stream=codec_name", "-of", "json", str(ogg_path)],
        check=True, capture_output=True, text=True,
    )
    info = json.loads(out.stdout)
    codecs = {s.get("codec_name") for s in info.get("streams", [])}
    if "vorbis" not in codecs:
        raise RuntimeError(f"not vorbis: {codecs}")
    dur = float(info["format"].get("duration", "0"))
    if dur < 0.2:
        raise RuntimeError(f"duration too short: {dur}s")
    return dur


# ── Media.lua sync ────────────────────────────────────────────────────────────

def sync_media_lua(entries: list[str]) -> dict:
    """Reconcile Media.lua sound registrations with Media/Sounds/ (both ways).

    - add: files present on disk but not registered (name from entries/sounds.txt
      when the slug matches, else Title Case of the stem);
    - remove: registrations whose file is gone from the folder.

    Never touches font/statusbar registrations or the pinned LEGACY block order.
    """
    lines = MEDIA_LUA.read_text().splitlines(keepends=True)
    on_disk = {p.name for p in SOUNDS_DIR.iterdir() if p.is_file()
               and p.suffix in (".ogg", ".mp3")}

    name_by_slug = {slugify(e): e for e in entries}

    # 0. Reconcile display names to canonical sounds.txt Title Case.
    #    Matched by slug so "Chi-Ji" vs "Chi-ji" style drift self-heals.
    renamed = []
    reconciled = []
    for ln in lines:
        m = REG.match(ln)
        if m:
            name, fname = m.group(1), m.group(2)
            canonical = name_by_slug.get(slugify(fname.rsplit(".", 1)[0]))
            if canonical and canonical != name:
                indent = ln[:len(ln) - len(ln.lstrip())]
                ln = (f'{indent}LSM:Register("sound", "{canonical}", '
                      f'[[Interface\\\\AddOns\\\\TF_QoL\\\\Media\\\\Sounds\\\\{fname}]])\n')
                renamed.append((name, canonical))
        reconciled.append(ln)
    lines = reconciled

    registered = {m.group(2): m.group(1) for m in (REG.match(l) for l in lines) if m}

    added, removed = [], []

    # 1. Drop dead registrations (file deleted from Sounds/).
    kept = []
    for ln in lines:
        m = REG.match(ln)
        if m and m.group(2) not in on_disk:
            removed.append((m.group(1), m.group(2)))
            continue
        kept.append(ln)
    lines = kept

    # 2. Add registrations for present-but-unregistered audio files.
    unregistered = sorted(on_disk - set(registered))
    new = []  # (sort_key, name, file)
    for fname in unregistered:
        stem = fname.rsplit(".", 1)[0]
        name = name_by_slug.get(stem) or display_name(stem)
        if name in set(registered.values()):
            continue  # name already taken by another file — leave alone
        text = (f'LSM:Register("sound", "{name}", '
                f'[[Interface\\AddOns\\TF_QoL\\Media\\Sounds\\{fname}]])\n')
        new.append((name.lower(), name, fname, text))

    if new:
        # Insert into the sorted block (skip the pinned LEGACY prefix).
        sorted_idx = [i for i, ln in enumerate(lines)
                      if (m := REG.match(ln)) and m.group(1) not in LEGACY]
        for key, name, fname, text in sorted(new):
            pos = None
            for i in sorted_idx:
                m = REG.match(lines[i])
                if m is not None and m.group(1).lower() > key:
                    pos = i
                    break
            if pos is None:
                pos = sorted_idx[-1] + 1 if sorted_idx else len(lines)
            lines.insert(pos, text)
            sorted_idx = sorted([i + 1 if i >= pos else i for i in sorted_idx] + [pos])
            added.append((name, fname))

    MEDIA_LUA.write_text("".join(lines))

    # Validation.
    files_now, names_now = [], []
    for ln in lines:
        if m := REG.match(ln):
            files_now.append(m.group(2))
            names_now.append(m.group(1))
    missing = [f for f in files_now if f not in on_disk]
    dupes = [n for n in set(names_now) if names_now.count(n) > 1]
    if missing or dupes:
        raise RuntimeError(f"sync validation failed: missing={missing} dupes={dupes}")
    res = subprocess.run(["luac5.1", "-p", str(MEDIA_LUA)],
                         capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"luac5.1 -p failed: {res.stderr}")

    return {"added": added, "removed": removed, "renamed": renamed,
            "registrations": len(files_now), "files": len(on_disk)}


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="preview generation + sync without touching anything")
    ap.add_argument("--force", action="store_true",
                    help="regenerate EVERY callout (backs up existing .ogg first)")
    ap.add_argument("--limit", type=int, default=None, help="only first N entries")
    ap.add_argument("--only", default=None, help="substring filter on callout text")
    args = ap.parse_args()

    entries = []
    for line in SOUNDS_TXT.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            entries.append(line)
    if args.only:
        entries = [e for e in entries if args.only.lower() in e.lower()]
    if args.limit:
        entries = entries[: args.limit]

    # Which callouts actually need generating?
    to_generate = []
    for text in entries:
        target = SOUNDS_DIR / f"{slugify(text)}.ogg"
        if args.force or not target.exists():
            to_generate.append((text, target))

    print(f"voice={VOICE} rate={RATE} pitch={PITCH} format=mp3->ogg(q4)")
    print(f"{len(entries)} callouts in sounds.txt, {len(to_generate)} to generate"
          + (" (--force)" if args.force else ""))

    if args.dry_run:
        for text, target in to_generate:
            mark = "OVERWRITE" if target.exists() else "new"
            print(f"  {mark:9} {target.name:28} <- {text!r}")
        print(f"\n(dry-run: would sync Media.lua to {SOUNDS_DIR} afterward)")
        return 0

    if not to_generate:
        print("nothing to generate — every sounds.txt entry already exists")
    else:
        SOUNDS_DIR.mkdir(parents=True, exist_ok=True)
        (STAGING / "mp3").mkdir(parents=True, exist_ok=True)
        (STAGING / "backup").mkdir(parents=True, exist_ok=True)
        session = requests.Session()
        session.headers["User-Agent"] = (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36")
        ws_base = get_ws_base(session)
        print(f"ws endpoint: {ws_base}\nstaging: {STAGING}")

        failed, overwritten = [], []
        for i, (text, target) in enumerate(to_generate, 1):
            prefix = f"[{i:>2}/{len(to_generate)}] {text!r}"
            try:
                report_usage(session)
                mp3 = synthesize(text, ws_base)
                mp3_path = STAGING / "mp3" / f"{slugify(text)}.mp3"
                mp3_path.write_bytes(mp3)
                if target.exists():
                    shutil.copy2(target, STAGING / "backup" / target.name)
                    overwritten.append(target.name)
                to_ogg(mp3_path, target)
                dur = verify_ogg(target)
                print(f"{prefix} -> {target.name} ({len(mp3)} B mp3, {dur:.2f}s ogg)")
            except Exception as exc:  # noqa: BLE001
                failed.append((text, str(exc)))
                print(f"{prefix} FAILED: {exc}")
            if i < len(to_generate):
                time.sleep(REQUEST_DELAY_S)

        if failed:
            print("\n(some callouts failed to generate — syncing only what exists)")
            for text, err in failed:
                print(f"  - {text!r}: {err}")

    # Sync Media.lua regardless (idempotent).
    print("\nsyncing Media.lua …")
    summary = sync_media_lua(entries)
    for name, fname in summary["removed"]:
        print(f"  - removed {name!r} (file {fname} deleted)")
    for old, new in summary["renamed"]:
        print(f"  ~ renamed {old!r} -> {new!r} (canonical sounds.txt)")
    for name, fname in summary["added"]:
        print(f"  + added   {name!r} -> {fname}")
    if not summary["added"] and not summary["removed"] and not summary["renamed"]:
        print("  (no changes — already in sync)")

    print(f"\n═══ summary ═══\nregistrations: {summary['registrations']}  "
          f"files: {summary['files']}  generated: {len(to_generate)}  "
          f"added: {len(summary['added'])}  removed: {len(summary['removed'])}  "
          f"renamed: {len(summary['renamed'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
