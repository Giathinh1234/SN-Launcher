#!/usr/bin/env python3
"""
Dump the agent transcripts so they can be read as a conversation.

OpenCode keeps its messages in a SQLite database; codex keeps them as JSONL
rollouts. Both are unreadable by eye, so this normalises them into one markdown
transcript each.

    python3 tool/chatlog.py opencode            # this session
    python3 tool/chatlog.py codex               # every codex run
    python3 tool/chatlog.py codex --since 2h    # only recent ones
    python3 tool/chatlog.py all

Output goes to build/chatlog/.
"""
import argparse
import json
import os
import sqlite3
import time

HOME = os.path.expanduser("~")
DB = os.path.join(HOME, ".local/share/opencode/opencode.db")
CODEX = os.path.join(HOME, ".codex/sessions")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "build", "chatlog")


def parse_since(s):
    if not s:
        return 0.0
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    return time.time() - float(s[:-1]) * units[s[-1].lower()]


# ── OpenCode ─────────────────────────────────────────────────────────────────
def dump_opencode(since):
    if not os.path.exists(DB):
        print(f"  no database at {DB}")
        return
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    cutoff = since * 1000

    rows = con.execute(
        "select session_id, type, seq, time_created, data from session_message "
        "where time_created > ? order by time_created",
        (cutoff,),
    ).fetchall()

    if not rows:
        print("  nothing in range")
        return

    sessions = {}
    for session_id, mtype, seq, created, data in rows:
        sessions.setdefault(session_id, []).append((mtype, created, data))

    os.makedirs(OUT, exist_ok=True)
    for session_id, msgs in sessions.items():
        path = os.path.join(OUT, f"opencode-{session_id}.md")
        with open(path, "w") as f:
            f.write(f"# OpenCode session {session_id}\n\n")
            for mtype, created, data in msgs:
                try:
                    d = json.loads(data)
                except Exception:
                    continue
                stamp = time.strftime("%H:%M:%S",
                                      time.localtime(created / 1000))
                role = mtype
                # Text lives in data.content as a list of parts.
                parts = d.get("content") or d.get("parts") or []
                texts = []
                for p in parts:
                    if not isinstance(p, dict):
                        continue
                    t = p.get("type")
                    if t == "text" and p.get("text"):
                        texts.append(p["text"])
                    elif t == "tool" and p.get("state"):
                        st = p["state"].get("status", "")
                        name = p.get("tool", "?")
                        if st == "completed":
                            texts.append(f"_(tool: {name})_")
                        elif st == "error":
                            texts.append(f"_(tool {name} error)_")
                if not texts:
                    continue
                f.write(f"## {role} · {stamp}\n\n")
                f.write("\n\n".join(t.strip() for t in texts))
                f.write("\n\n")
        n = sum(1 for m in msgs)
        print(f"  {path}  ({n} messages)")


# ── Codex ────────────────────────────────────────────────────────────────────
def dump_codex(since, only_newest=False):
    if not os.path.isdir(CODEX):
        print(f"  no sessions at {CODEX}")
        return
    files = []
    for root, _, names in os.walk(CODEX):
        for n in names:
            if n.endswith(".jsonl"):
                p = os.path.join(root, n)
                if os.path.getmtime(p) >= since:
                    files.append(p)
    files.sort(key=os.path.getmtime)
    if only_newest and files:
        files = files[-1:]
    if not files:
        print("  nothing in range")
        return

    os.makedirs(OUT, exist_ok=True)
    for path in files:
        turns, tools, cwd = [], [], ""
        for line in open(path, errors="replace"):
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue

            if d.get("type") == "session_meta":
                cwd = (d.get("payload") or {}).get("cwd", "")
                continue
            if d.get("type") != "response_item":
                continue

            payload = d.get("payload") or {}
            kind = payload.get("type")

            # Codex stores conversation text in payload.content as a list of
            # parts; `text` is not used for messages in this format.
            text = ""
            if isinstance(payload.get("content"), list):
                text = "\n".join(
                    str(c.get("text", "")) for c in payload["content"]
                    if isinstance(c, dict) and c.get("text")
                )
            elif isinstance(payload.get("text"), str):
                text = payload["text"]

            if kind == "message" and text.strip():
                role = payload.get("role", "?")
                # Drop the harness-injected developer scaffolding; it is not
                # part of the conversation and is mostly noise.
                if role == "developer" or text.lstrip().startswith("<"):
                    continue
                turns.append((role, text))

            elif kind == "function_call":
                tools.append(payload.get("name", "?"))

            elif kind == "reasoning":
                for part in payload.get("summary") or []:
                    if isinstance(part, dict) and part.get("text"):
                        turns.append(("reasoning", part["text"]))

        if not turns and not tools:
            continue
        stamp = time.strftime("%Y-%m-%d %H:%M",
                             time.localtime(os.path.getmtime(path)))
        out_path = os.path.join(OUT, os.path.basename(path) + ".md")
        with open(out_path, "w") as f:
            f.write(f"# codex run · {stamp}\n\n")
            f.write(f"source: `{path}`\n\n")
            if cwd:
                f.write(f"cwd: `{cwd}`\n\n")
            if tools:
                f.write(f"tools called: {', '.join(sorted(set(tools)))}\n\n")
            f.write("---\n\n")
            for role, text in turns:
                f.write(f"## {role}\n\n{text.strip()}\n\n")
        print(f"  {out_path}  ({len(turns)} turns, {len(set(tools))} tools)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("which", choices=["opencode", "codex", "all"])
    ap.add_argument("--since", default=None,
                    help="e.g. 30m, 2h, 3d — only newer than this")
    args = ap.parse_args()
    since = parse_since(args.since)
    print(f"writing to {OUT}\n")
    if args.which in ("opencode", "all"):
        print("OpenCode:")
        dump_opencode(since)
    if args.which in ("codex", "all"):
        print("codex:")
        dump_codex(since)


if __name__ == "__main__":
    main()