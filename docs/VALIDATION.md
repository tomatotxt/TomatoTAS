# Validation and acceptance

## Verified locally

- All production and test Luau files compile with the official Luau compiler.
- Core tests: branching, strictly monotonic parent-child time, binary roundtrip,
  every truncation and single-byte mutation of a sample file, invalid frames,
  10,000 randomized quaternion roundtrips, SLERP sign handling, interpolation,
  10,000-node branched run serialization.
- Controller tests with service doubles: capture cadence, mark/restore branching,
  exactly one frame step, exact-frame and timed playback, zero-delta handling,
  switching maps for a new run, unload, and runtime error cleanup.
- Clone preparation with mock Instances: dense batching, successful cleanup,
  failed clone cleanup, cancellation, rejection of unrestorable listeners,
  full quiet-interval spawn settling, rejection of accumulating slow drift,
  same-count part replacement, failed map parenting, delayed closure readiness,
  and rope cache isolation across rounds.
- Character mocks: deterministic track ordering/reuse, late hitboxes/events,
  camera replacement, inaccessible animations, takeover ownership, and isolated
  cleanup when individual objects fail.
- File IO fault injection: staging, backup and final-write verification, rollback,
  explicit recovery loads, primary corruption, and failed temporary-file deletion.
- Loader tests execute the real loader source with mocked HTTP: default/custom
  URLs, module caching, bad responses, dependency cycles, rejected configuration,
  and preserving a previous session when validation fails.

Current local result: **17 Luau files compile; 90 tests pass** (25 core,
24 controller, 14 map, 10 character, 10 storage, 7 loader).
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
2. On a static spawn, verify preparation takes at least one second after entry.
   On a moving spawn, verify the stable timer restarts after movement or rotation.
   Remove the map or respawn mid-preparation: verify timeout/cancellation releases work.
3. Clone a small then large map. Check no Archivable trap fires, properties/listeners
   return to their original values, and the original map returns on unload.
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

These checks need an actual Roblox client. Local compilation and mocked controller
tests do not establish frame-perfect server outcomes or compatibility with every map.
