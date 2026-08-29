# Getting a crash report off a device

How the 1.1.10 launch crash was diagnosed (2026-08-23). Written down because the
fast path is not obvious and the slow paths cost hours.

## The fast path: `devicectl`, straight off the paired device

Xcode 26's device CLI exposes the same crash store the phone's
**Settings → Privacy & Security → Analytics & Improvements → Analytics Data**
screen shows — scriptable, no App Store Connect account, no ingest delay.

```bash
xcrun devicectl list devices

# List the store. NOTE THE FLAG: `info files` takes --username.
xcrun devicectl device info files --device "iPhone von Julian" \
  --domain-type systemCrashLogs --username mobile

# Pull one out. Older reports live under Retired/.
# NOTE THE FLAG: `copy from` takes --user. The two subcommands disagree.
xcrun devicectl device copy from --device "iPhone von Julian" \
  --domain-type systemCrashLogs --user mobile \
  --source "Retired/GymStreak-2026-08-23-120321.ips" \
  --destination ./crash.ips
```

**The `--user` / `--username` split is a real trap** (devicectl 518.31, Xcode 26). `info files`
rejects `--user` with `Unknown option '--user'. Did you mean '--quiet'?` and `copy from` rejects
`--username`. Worse: if you pipe the failing `info files` through a `grep`, it prints nothing and
looks exactly like "no crash reports for this app". Check the exit status, not the grep.

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


## When there is no `.ips` at all

A `fatalError` hit **with the debugger attached** generates no crash report — lldb catches the trap
and the process never reaches ReportCrash. `devicectl` will show only unrelated older reports. Don't
read that as "it didn't crash".

For a SwiftData/Core Data fault, the store itself is better evidence than a backtrace would have
been, because CloudKit mirroring enables Core Data **persistent history**: the `ATRANSACTION` and
`ACHANGE` tables record every insert/update/delete with a timestamp and an author, so you can
reconstruct exactly what was mutated and when.

```bash
# The store is in the APP GROUP container, not the app container:
# ModelConfiguration's groupContainer defaults to .automatic, and the app has one App Group.
xcrun devicectl device info files --device "iPhone von Julian" \
  --domain-type appGroupDataContainer --domain-identifier group.com.gymstreak.shared \
  --username mobile

# Copy all THREE files into one directory — sqlite3 replays the WAL only when it sits
# next to the main file, and the newest transactions are in there.
for f in default.store default.store-shm default.store-wal; do
  xcrun devicectl device copy from --device "iPhone von Julian" \
    --domain-type appGroupDataContainer --domain-identifier group.com.gymstreak.shared \
    --user mobile --source "Library/Application Support/$f" --destination "./store/$f"
done
```

Reading it:

```sql
SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY;          -- entity id -> model name

-- Everything one transaction touched
SELECT p.Z_NAME, c.ZCHANGETYPE, COUNT(*), GROUP_CONCAT(c.ZENTITYPK)
FROM ACHANGE c JOIN Z_PRIMARYKEY p ON p.Z_ENT = c.ZENTITY
WHERE c.ZTRANSACTIONID = 115 GROUP BY 1, 2;      -- ZCHANGETYPE 0=insert 1=update 2=delete

-- Was it a local write or a CloudKit import? Author strings are INTERNED: join
-- ATRANSACTIONSTRING on ZAUTHORTS/ZCONTEXTNAMETS/ZBUNDLEIDTS. The plain ZAUTHOR /
-- ZCONTEXTNAME / ZBUNDLEID text columns are always NULL and will mislead you.
SELECT t.Z_PK, datetime(t.ZTIMESTAMP + 978307200, 'unixepoch', 'localtime'),
       a.ZNAME AS author, b.ZNAME AS bundle
FROM ATRANSACTION t
LEFT JOIN ATRANSACTIONSTRING a ON a.Z_PK = t.ZAUTHORTS
LEFT JOIN ATRANSACTIONSTRING b ON b.Z_PK = t.ZBUNDLEIDTS
ORDER BY t.ZTIMESTAMP DESC LIMIT 10;
-- author 'NSCloudKitMirroringDelegate.import' = it came from another device.
-- empty author + the app's bundle id = a local write from the app's own context.
```

`x-coredata://…/WorkoutExercise/p385` in a crash message means `ZWORKOUTEXERCISE.Z_PK = 385` — look
it up directly. This is how the History delete race was diagnosed without a backtrace; see
`docs/history-delete-race.md`.

Note `log collect --device-name …` needs root, so it is not a drop-in alternative.
