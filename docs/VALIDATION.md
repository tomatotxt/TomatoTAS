# Validation and acceptance

## Verified locally

- All production and test Luau files compile with the official Luau compiler.
- Core tests: branching, strictly monotonic parent-child time, binary roundtrip,
  every truncation and single-byte mutation of a sample file, invalid frames,
  10,000 randomized quaternion roundtrips, SLERP sign handling, interpolation,
  10,000-node branched run serialization.
- Controller tests with service doubles: capture cadence, mark/restore branching,
  exactly one frame step, exact-frame and timed playback, zero-delta handling,
  switching maps for a new run, unload, and runtime error cleanup. Automatic
  preparation tests cover entry, loader handoff, cancellation, delayed retries,
  preserving existing runs and disabling the feature. Sandbox commit ordering
  and recording-only cleanup transitions are checked through the controller.
- Clone preparation with mock Instances: dense batching, successful cleanup,
  failed clone cleanup, cancellation, rejection of unrestorable listeners,
  full quiet-interval spawn settling, rejection of accumulating slow drift,
  same-count part replacement, failed map parenting, delayed closure readiness,
  and rope cache isolation across rounds. Full mock acquisition/clone/respawn
  flows verify delayed arrival, anchor release, validated source deletion,
  failed-setup rollback, map arrival/rename, replacement containers and cleanup
  errors. Live recording never installs the sandbox deletion policy.
- Character mocks: deterministic track ordering/reuse, late hitboxes/events,
  camera replacement, inaccessible animations, takeover ownership, and isolated
  cleanup when individual objects fail. Partial constructor failures disconnect
  acquired events; rejected takeovers do not write another controller's state.
- File IO fault injection: staging, backup and final-write verification, rollback,
  explicit recovery loads, primary corruption, and failed temporary-file deletion.
- Loader tests execute the real loader source with mocked HTTP: default/custom
  URLs, module caching, bad responses, dependency cycles, rejected configuration,
  and preserving a previous session when validation or construction fails.

Current local result: **20 Luau files compile; 145 tests pass** (26 core,
40 controller, 29 map, 15 character, 10 storage, 10 loader, 15 GUI).
GUI tests use native-widget doubles to check construction, responsive scaling,
disabled actions, timeline selection, file/branch wiring, minimization and cleanup.
Stale queued row clicks, changed New run confirmation targets and pending frame
steps are covered. Animation weights above one survive capture, storage and playback.
They do not render the interface in Roblox; in-game visual validation is pending.
Controller coverage includes empty/single-branch hotkeys, branch cycling,
custom keybind validation, preserving recording after failed file operations,
map removal, cancellation and waiting for a fresh physics boundary when stepping.
Pure core modules also pass standalone Luau analysis.
The test runner now includes that analysis. Backup validation checks the same
binary invariants without allocating a second full recording tree.
Standalone analysis of Roblox/executor modules requires host API definitions;
compilation and mocked tests do not substitute for those definitions.

## Not yet verified in FE2

Run these checks using the intended executor after publishing the repository:

1. Start the loader in the lobby, during NewMap arrival, and after Map is loaded.
   Check invalid Repo, failed HTTP and incompatible capabilities produce clear errors.
   Verify preparation starts automatically after entering the map and does not
   replace the current run. Stop preparation, check that it stays cancelled, and
   retry with F1. Reload during playback and check the previous session releases.
2. On a static spawn, verify preparation takes at least one second after entry.
   On a moving spawn, verify the stable timer restarts after movement or rotation.
   Remove the map or respawn mid-preparation: verify timeout/cancellation releases work.
3. Clone a small then large map. Check no Archivable trap fires, properties/listeners
   return to their original values, and the original is deleted locally only after
   successful clone respawn. Failed setup must restore it. While recording, verify
   incoming Map/NewMap models disappear; pause/stop/unload must stop this policy.
   After a committed clone unload, wait for a new round or rejoin for a live map.
4. Confirm spawn-relative frame zero stays aligned across randomized live spawns.
5. Record walking, jumping, sliding, swimming, walljump and zipline examples.
   Compare recorded geometry, root transforms and animation positions during replay.
   Test both exact-frame and time modes at differing client frame rates.
6. Make two futures from one character mark. Save, reload, cycle branches and inspect
   each future. Repeat with one-frame stepping. World mechanics must remain visibly
   unrewound; the tool must not claim otherwise.
7. Restore a character mark during each custom movement mechanic. Check whether
   FE2's restarted controller can continue correctly, and record any private-state
   integration needed. Direct playback and live continuation are separate tests.
8. Stop and unload during playback, pause and after respawn. Check movement,
   geometry, camera, scripts, listeners and inactive MoveDirection hook behavior.
9. Test zipline packet capture before map load, mid-round closure recovery, and
   restoration after clone respawn. Verify no previous-map rope table is injected.
10. Interrupt a file save and verify the `.bak`/`.pending` recovery files. Load
    a corrupted, truncated, wrong-map or unsupported-version file and verify rejection.
11. Inspect GUI layout at desktop and small viewport sizes, drag to each edge,
    minimize/reopen it, edit text fields and respawn. Verify no clipped controls,
    unintended hotkeys while typing, or orphaned screens after reload/unload.
    Try Studio transport, named marks, both replay modes, branch selection,
    timeline seeking, file selection and recovery buttons in a live client.

These checks need an actual Roblox client. Local compilation and mocked controller
tests do not establish frame-perfect server outcomes or compatibility with every map.
