# Drag regression checks

Run from the repository root:

```sh
test_build_dir=$(mktemp -d /tmp/notch-monster-tests.XXXXXX)
swift test --scratch-path "$test_build_dir"
```

The temporary scratch directory keeps test bundles outside iCloud Documents, which can add Finder metadata that prevents code signing.

The automated tests cover:

- Old file URLs on the drag pasteboard are not part of a new gesture.
- A changed pasteboard generation is recognized as fresh.
- Each gesture starts with its own pasteboard baseline.
- Pointer movement without window movement does not qualify as a window drag.
- Releasing outside the notch zone cancels capture, even after approaching it.
- A five-point outward reversal detaches inside the zone; smaller wobbles and pauses remain attached. After release, pausing stays detached and a one-point inward movement reattaches.
- Native retreat/pause drops keep the fixture intact, including when the mouse-up monitor resets visual state before AppKit's drop callback.
- Arm length persists, clamps to 80–360 pt, and redraws WindowServer's capture shape immediately.
- Movement and proximity calculations work with negative display coordinates.
- Native file-drop coordinates, rejection outside reach, and disabling the monster.
- Real WindowServer hit testing inside the invisible capture shape and pass-through outside it.
- Destination ownership survives mouse-up and stays held through the native drop callback.
- Model changes preserve the native destination's pasteboard registration.
- A unique disposable file reaches Trash exactly once; a duplicate callback leaves a replacement file untouched.
- Raycast receives all selected file paths, including punctuation and Unicode; successful and failed handoffs both leave originals in place, and duplicate callbacks do not launch twice.
- The file action defaults to Trash and remembers an explicit Raycast choice.
- A verified last-window close sends one normal quit request; other windows, close confirmations, newly opened windows, and unreadable window lists prevent it. Already exited apps and declined quit requests are not retried.
- Rendered arm pixels stay in front of the notch opening during shallow left/right reaches and every tested retraction stage; the hand remains at the cursor.

## End-to-end acceptance

Use the packaged, signed app with Accessibility and Screen Recording enabled. Use disposable files, a newly opened Finder window, and a new Safari window containing only an empty tab.

1. Drag a disposable file normally within Finder, away from the notch, then release. This leaves a prior drag payload for the regression scenario.
2. Drag the new Finder window by an empty part of its title bar toward the notch. Confirm the arm appears beside the cursor. Release inside the reach zone. Confirm that its screenshot folds into the notch and the original window closes.
3. Repeat with the new empty Safari window. Confirm the entire window closes, not merely a tab.
4. Open another test window. Drag it into reach, move a little farther from the notch while still inside reach, pause, then release. Confirm the arm retracts and the window stays where you place it. Repeat, but move inward again before releasing; it should reattach and consume. Also check retreating outside the zone.
5. Drag/select content without moving its window. Confirm that it does not trigger window capture.
6. Drop a disposable file inside the arm's reach. Confirm that its icon is yanked into the notch, its original path disappears, and the file appears in Trash. The app beneath the notch must not receive the drop.
7. Drag another disposable file near the notch, move outside the reach circle, then release over an ordinary destination. Confirm normal drop routing still works.
8. In a disposable test app, open two windows and minimize one. Feed the visible window; the application must stay running. Restore and feed its last window; the application should quit. If a document asks to save, cancel that prompt and confirm the app stays running.

Inspect the live gesture evidence with:

```sh
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "com.notchmonster.app"'
```

A successful window gesture reports `CLASSIFY moved window`, `ZONE inside=true`, `RELEASE window`, `SNAPSHOT`, `CLOSE`, `VERIFIED window removed`, and `YANK completed` for the running app process. Cancellation reports `RELEASE cancelled: hand detached or outside reach`.

A successful file gesture reports `CLASSIFY file`, `FILE_ENTER`, `FILE_DROP`, `FILE_TRASH result moved=1 failed=0`, and `FILE_CONCLUDE`. Check that these come from the running `NotchMonster` process, not `swiftpm-testing-helper`: callback tests alone do not prove native drag routing.

After a successful window yank, `LAST_WINDOW_QUIT` records `requested` when a normal quit request was sent, `windowsRemain` when another window exists, or the reason no request was sent. `requested` does not imply the application has already exited; an app may delay or decline quitting.

There is no destructive focused-window self-test. Validation uses an intentional title-bar drag of a disposable test window, exercising the same path as normal use.
