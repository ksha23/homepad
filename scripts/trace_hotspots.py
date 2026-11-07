"""Main-thread hot spots in a Faces tour recorded by scripts/profile-faces.sh.

    python3 scripts/trace_hotspots.py <run folder> [--top 25] [--phase "editor"] [--match <regex>]

Reads <run folder>/faces.trace (exported once to time-profile.xml beside it) and
<run folder>/test.log, splits the run into the tour's steps (opening, scrolling
My Faces, the gallery, the editor, the Widgets page) and prints, for each, the
main thread's busy time, the stretches of it long enough to hold up a frame,
and the app's functions with the most time in their stacks.

XCUITest reads the app's accessibility tree before every step, which the app
would not do on an iPad, so samples under those reads are left out and counted
apart. The test log and the trace are lined up by the first widget drag, which
both record.
"""
import argparse
import collections
import os
import pickle
import re
import subprocess
import xml.etree.ElementTree as ET

# Stacks from XCUITest's accessibility snapshots, not the app's own work.
HARNESS = re.compile(r"XCTElementSnapshotRequest|_AXXMIGCopyParameterizedAttributeValue|accessibilityUserTestingSnapshot"
                     r"|XCTPerformOnMainRunLoop")
# The app's own code: everything linked into the HomePad binary.
APP_BINARY = "HomePad"


def export(folder):
    """The trace's time profile as XML, exported once."""
    path = os.path.join(folder, "time-profile.xml")
    if not os.path.exists(path):
        with open(path, "w") as out:
            subprocess.run(["xcrun", "xctrace", "export", "--input", os.path.join(folder, "faces.trace"), "--xpath",
                            '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'], stdout=out, check=True)
    return path


def samples(folder):
    """(seconds, is main thread, weight in ms, [(function, binary)] leaf first) for each sample, cached."""
    cache = os.path.join(folder, "samples.pickle")
    if os.path.exists(cache):
        with open(cache, "rb") as handle:
            return pickle.load(handle)
    ids = {}
    rows = []
    for _, element in ET.iterparse(export(folder), events=("end",)):
        if element.tag == "row":
            rows.append(element)
        elif element.get("id") is not None:
            ids[element.get("id")] = element

    def resolve(element):
        if element is not None and element.get("ref"):
            return ids.get(element.get("ref"), element)
        return element

    result = []
    for row in rows:
        thread = resolve(row.find("thread"))
        if thread is None or "HomePad" not in thread.get("fmt", ""):
            continue
        time = resolve(row.find("sample-time"))
        weight = resolve(row.find("weight"))
        stack = resolve(row.find("tagged-backtrace"))
        if stack is None:
            stack = resolve(row.find("backtrace"))
        frames = []
        for frame in (stack.findall("frame") if stack is not None else []):
            frame = resolve(frame)
            binary = resolve(frame.find("binary"))
            frames.append((frame.get("name") or frame.get("addr") or "?", binary.get("name") if binary is not None else ""))
        result.append((int(time.text) / 1e9, thread.get("fmt", "").startswith("Main Thread"),
                       int(weight.text) / 1e6 if weight is not None else 1.0, frames))
    with open(cache, "wb") as handle:
        pickle.dump(result, handle)
    return result


def steps(folder):
    """The tour's steps from the test log: (seconds since the test began, what it did)."""
    found = []
    pattern = re.compile(r"^\s+t =\s+([\d.]+)s (Tap|Swipe up|Swipe down|Press) (.*)$")
    with open(os.path.join(folder, "test.log")) as log:
        for line in log:
            match = pattern.match(line)
            if match:
                found.append((float(match.group(1)), f"{match.group(2)} {match.group(3)[:40]}"))
    return found


def phases(folder, trace_samples):
    """The tour's phases in trace seconds, cut at its steps."""
    tour = steps(folder)
    drag = next(t for t, what in tour if what.startswith("Press \"Timers"))
    # The drag's signpost marks where the finger first moved, a press later.
    signposts = subprocess.run(["xcrun", "xctrace", "export", "--input", os.path.join(folder, "faces.trace"), "--xpath",
                                '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]'],
                               capture_output=True, text=True).stdout
    match = re.search(r'fmt="(\d+):(\d+)\.(\d+)\.\d+">\d+</event-time>(?:(?!</row>).)*?editor\.widgetDrag', signposts, re.S)
    offset = 0.0
    if match:
        begin = int(match.group(1)) * 60 + int(match.group(2)) + int(match.group(3)) / 1000
        offset = begin - (drag + 0.2)
    # Half a second early, so what a step sets off falls in its phase though the
    # log and the trace line up only to a tenth of a second. Steps are seconds apart.
    at = lambda t: t + offset - 0.5
    first = lambda prefix: next(t for t, what in tour if what.startswith(prefix))
    customizes = [t for t, what in tour if what.startswith("Tap \"Customize")]
    end = max(s[0] for s in trace_samples)
    return [
        ("open: Home Screen, zoom, My Faces built", 0, at(first("Swipe up"))),
        ("scroll My Faces", at(first("Swipe up")), at(first("Tap \"Add Face"))),
        ("gallery: open, scroll, close", at(first("Tap \"Add Face")), at(customizes[0])),
        ("editor: 4 faces, pages, distance", at(customizes[0]), at(customizes[-1])),
        ("Widgets page and drags", at(customizes[-1]), end),
    ]


def report(name, chosen, top, match):
    main = [s for s in chosen if s[1]]
    harness = sum(s[2] for s in main if any(HARNESS.search(f) for f, _ in s[3]))
    own = [s for s in main if not any(HARNESS.search(f) for f, _ in s[3])]
    if match:
        own = [s for s in own if any(re.search(match, f) for f, _ in s[3])]
    total = sum(s[2] for s in own)
    span = (max(s[0] for s in chosen) - min(s[0] for s in chosen)) if chosen else 0
    print(f"\n== {name}: {span:.1f} s, main thread {total:.0f} ms of the app's own work"
          f" ({100 * total / max(span * 1000, 1):.0f}% busy), {harness:.0f} ms more under XCUITest's reads")
    long = stretches(own)
    if long:
        print(f"   {len(long)} stretches of {STRETCH_MS} ms or more, {sum(w for _, w in long):.0f} ms in all,"
              f" longest {', '.join(f'{w:.0f}' for _, w in sorted(long, key=lambda x: -x[1])[:5])} ms")
    inclusive = collections.Counter()
    for _, _, weight, frames in own:
        for function in {f for f, binary in frames if binary == APP_BINARY}:
            inclusive[function] += weight
    for function, weight in inclusive.most_common(top):
        print(f"{100 * weight / max(total, 1):5.1f}%  {weight:7.0f} ms  {function[:160]}")


# A stretch of the main thread busy this long holds up at least one frame at 60 Hz.
STRETCH_MS = 20


def stretches(own):
    """(start, ms) of each run of main-thread samples with no gap over a few ms: what holds up frames."""
    found = []
    current = []
    for sample in sorted(own, key=lambda s: s[0]):
        if current and sample[0] - current[-1][0] > 0.003:
            found.append(current)
            current = []
        current.append(sample)
    if current:
        found.append(current)
    weights = [(run[0][0], sum(s[2] for s in run)) for run in found]
    return [(start, weight) for start, weight in weights if weight >= STRETCH_MS]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder")
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--phase", default=None, help="only phases whose name contains this")
    parser.add_argument("--match", default=None, help="only stacks with a function matching this regex")
    args = parser.parse_args()
    trace_samples = samples(args.folder)
    report("whole tour", trace_samples, args.top, args.match)
    for name, start, end in phases(args.folder, trace_samples):
        if args.phase and args.phase not in name:
            continue
        report(name, [s for s in trace_samples if start <= s[0] < end], args.top, args.match)


if __name__ == "__main__":
    main()
