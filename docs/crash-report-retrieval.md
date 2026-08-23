# Getting a crash report off a device

How the 1.1.10 launch crash was diagnosed (2026-08-23). Written down because the
fast path is not obvious and the slow paths cost hours.

## The fast path: `devicectl`, straight off the paired device

Xcode 26's device CLI exposes the same crash store the phone's
**Settings → Privacy & Security → Analytics & Improvements → Analytics Data**
screen shows — scriptable, no App Store Connect account, no ingest delay.

```bash
xcrun devicectl list devices

# List the store. Note: --user (not --username), and 'mobile' is required.
xcrun devicectl device info files --device "iPhone von Julian" \
  --domain-type systemCrashLogs --user mobile

# Pull one out. Older reports live under Retired/.
xcrun devicectl device copy from --device "iPhone von Julian" \
  --domain-type systemCrashLogs --user mobile \
  --source "Retired/GymStreak-2026-08-23-120321.ips" \
  --destination ./crash.ips
```

Works for a TestFlight or App Store build — the app does **not** need to be a debug
build, and the device only needs to be paired.

## Reading the `.ips`

Line 1 is a JSON header (`app_version`, `build_version`, `bundleID`, `os_version`,
`is_beta`); the rest is a JSON body. Symbol names live in `usedImages`, indexed by
each frame's `imageIndex`:

```bash
head -1 crash.ips | python3 -m json.tool          # version / OS / TestFlight?
tail -n +2 crash.ips | python3 -c "
import json,sys
d=json.load(sys.stdin); imgs=d['usedImages']
print(d['exception'], d['termination'])
t=d['threads'][d['faultingThread']]
print('queue:', t.get('queue'))
for f in t['frames']:
    im=imgs[f['imageIndex']]
    print(f\"{im.get('name','?'):24s} 0x{f.get('imageOffset',0):x}  {f.get('symbol','')}\")
"
```

## Where the other stores are, and why they were empty

- `~/Library/Developer/Xcode/DeviceLogs/<device>/` — only populated when the Xcode
  **Devices and Simulators** window is opened. Stale otherwise; ours was two days behind.
- `~/Library/Logs/CrashReporter/MobileDevice/` — legacy, empty on Xcode 26.
- Xcode **Organizer → Crashes** — needs `share_with_app_devs: 1` in the report *and*
  Apple's aggregation delay. Fine for trends, useless for "it crashed five minutes ago."

## Symbolication

The frames from the app itself come back unsymbolicated unless the local dSYM's UUID
matches the report's `slice_uuid`. Compare with:

```bash
dwarfdump --uuid <path>.dSYM
```

An Xcode Cloud build's dSYM is **not** on your Mac — download it from Organizer or
App Store Connect. Often you don't need it: the framework frames around your code
(here, `-[WCSession _onqueue_notifyOfMessageError:…]` plus
`swift_task_isCurrentExecutorWithFlags`) identified the bug class precisely enough to
find the three candidate call sites by grep.

## Interpreting `EXC_BREAKPOINT` / `SIGTRAP`

Not a segfault — a deliberate Swift runtime trap. Common causes: force-unwrap of nil,
array out of bounds, `precondition`/`fatalError`, integer overflow, and — the one that
bit us — an **actor-isolation precondition**. If the stack contains
`swift_task_isCurrentExecutor*`, `_swift_task_checkIsolatedSwift`, or
`dispatch_assert_queue`, it is an isolation failure, not a logic bug:
see `docs/swift6-concurrency.md` §4a.
