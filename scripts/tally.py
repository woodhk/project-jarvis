#!/usr/bin/env python3
"""Summarises the Jarvis log: per spoken phrase and overall, what happened and how long it took.

    python3 scripts/tally.py [--since 2026-11-12T09:00:00Z] [--file PATH]
    python3 scripts/tally.py --self-test

A request is one line with outcome opened, offered, nothing, gone or failed (a choice taken from a list belongs to
the request that offered it). An open that is followed by "back" within 10 seconds counts as a wrong open.
"""
import argparse, datetime, json, os, re, statistics, sys

ATTEMPTS = {"opened", "offered", "nothing", "gone", "failed"}
STEPS = ("total", "transcribe", "pick", "open")


def when(record):
    return datetime.datetime.fromisoformat(record["at"].replace("Z", "+00:00"))


def phrase_key(text):
    return " ".join(re.sub(r"[^a-z0-9 ]", " ", text.lower()).split())


def summarise(records):
    """Returns (per phrase, overall). Each is a dict of counts plus lists of times."""
    def blank():
        return {"attempts": 0, "direct": 0, "offered": 0, "nothing": 0, "wrong": 0, "other": 0,
                "went_to": {}, "ms": {step: [] for step in STEPS}}
    phrases, overall = {}, blank()
    extra = {"unheard": 0, "left": 0, "choice_taken": 0, "space_ms": []}
    for index, record in enumerate(records):
        outcome = record.get("outcome")
        if outcome == "unheard": extra["unheard"] += 1
        if outcome == "left": extra["left"] += 1
        if outcome == "space": extra["space_ms"].append(record.get("ms", {}).get("spaceChanged", 0))
        is_choice = outcome == "opened" and record.get("step") == "choice"
        if is_choice: extra["choice_taken"] += 1
        # An open is wrong when the next request is "back" within 10 seconds.
        wrong = False
        if outcome == "opened":
            following = next((r for r in records[index + 1:] if r.get("outcome") != "space"), None)
            wrong = bool(following and following.get("outcome") == "back" and (when(following) - when(record)).total_seconds() <= 10)
        if outcome not in ATTEMPTS:
            continue
        for bucket in (phrases.setdefault(phrase_key(record.get("heard", "")), blank()), overall):
            if is_choice:                      # belongs to the request that offered it: count only a wrong pick
                bucket["wrong"] += wrong
                continue
            bucket["attempts"] += 1
            if outcome == "opened":
                bucket["wrong" if wrong else "direct"] += 1
                title = record.get("title") or "?"
                bucket["went_to"][title] = bucket["went_to"].get(title, 0) + 1
            elif outcome in ("offered", "nothing"):
                bucket[outcome] += 1
            else:
                bucket["other"] += 1
            for step in STEPS:
                if step in record.get("ms", {}): bucket["ms"][step].append(record["ms"][step])
    return phrases, overall, extra


def times(bucket):
    parts = []
    for step in STEPS:
        values = bucket["ms"][step]
        if values: parts.append(f"{step} {round(statistics.median(values))}/{max(values)}")
    return "  ".join(parts)


def line(name, b):
    went = ", ".join(f"{title} x{count}" for title, count in sorted(b["went_to"].items(), key=lambda kv: -kv[1]))
    return (f"{name[:58]:<58} {b['attempts']:>3} tries  direct {b['direct']:>2}  offered {b['offered']:>2}  nothing {b['nothing']:>2}"
            f"  wrong {b['wrong']:>2}  other {b['other']:>2}\n    ms median/worst: {times(b)}" + (f"\n    opened: {went}" if went else ""))


def report(records):
    phrases, overall, extra = summarise(records)
    out = [line(name, b) for name, b in sorted(phrases.items())]
    out.append("")
    out.append(line("ALL", overall))
    n = overall["attempts"] or 1
    out.append(f"    wrong opens {overall['wrong']}/{overall['attempts']} ({100 * overall['wrong'] / n:.0f}%; target under 5%)   "
               f"two-choice lists {overall['offered']}/{overall['attempts']} ({100 * overall['offered'] / n:.0f}%; target 10% or less)")
    out.append(f"    not heard {extra['unheard']}   lists left alone {extra['left']}   choices taken {extra['choice_taken']}"
               + (f"   desktop switch ms median/worst {round(statistics.median(extra['space_ms']))}/{max(extra['space_ms'])}" if extra["space_ms"] else ""))
    return "\n".join(out)


def self_test():
    def rec(second, heard, outcome, total=None, title=None, step=None):
        ms = {"total": total} if total is not None else {}
        return {"at": f"2026-11-12T09:00:{second:02d}Z", "heard": heard, "outcome": outcome, "title": title, "ms": ms, "step": step}
    records = [
        rec(0, "Open YouTube.", "opened", 400, "YouTube", "name"),
        rec(5, "open youtube", "opened", 480, "YouTube", "name"),
        rec(20, "open the gif session", "opened", 520, "IDEAS2", "jev"),      # wrong: "back" follows within 10 s
        rec(26, "back", "back", 300, "Notes"),
        rec(40, "open the insta session", "offered", 600, "A | B", "jev"),
        rec(55, "open my tax return", "nothing", 450, None, "jev"),
    ]
    phrases, overall, _ = summarise(records)
    got = (overall["direct"], overall["offered"], overall["nothing"], overall["wrong"], round(statistics.median(overall["ms"]["total"])))
    assert got == (2, 1, 1, 1, 480), got
    assert overall["attempts"] == 5 and phrases["open youtube"]["direct"] == 2, (overall["attempts"], phrases.keys())
    late = [dict(records[2]), dict(records[3], at="2026-11-12T09:00:45Z")]                   # "back" after 25 s is not a wrong open
    assert summarise(late)[1]["wrong"] == 0
    taken = [rec(0, "open the insta session", "offered", 600, "A | B", "jev"), rec(2, "open the insta session", "opened", 90, "A", "choice")]
    after = summarise(taken)
    assert (after[1]["attempts"], after[1]["offered"], after[1]["direct"], after[2]["choice_taken"]) == (1, 1, 0, 1), after
    print("ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--since", help="only requests at or after this time, for example 2026-11-12T09:00:00Z")
    parser.add_argument("--file", default=os.path.join(os.environ.get("JARVIS_HOME", os.path.expanduser("~")), "Library/Logs/Jarvis/events.jsonl"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not os.path.exists(args.file):
        sys.exit(f"No log yet at {args.file}")
    records = []
    for text in open(args.file, encoding="utf-8"):
        try: records.append(json.loads(text))
        except ValueError: continue
    if args.since:
        since = datetime.datetime.fromisoformat(args.since.replace("Z", "+00:00"))
        records = [r for r in records if when(r) >= since]
    print(report(records) if records else "No requests in that period.")


if __name__ == "__main__":
    main()
