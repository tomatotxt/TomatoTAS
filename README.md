# TomatoTAS

Modular Flood Escape 2 character TAS Creator and Player with a native GUI and hotkeys for an executor
providing UNC/sUNC APIs. This is a new implementation; the files in `references/`
are research inputs, not runtime dependencies.

**Status:** implemented and locally tested core, loader, controller, storage and
mocked character/map integrations; FE2 integration still
requires in-game testing. Full map simulation and world savestates are deliberately
deferred. Character marks do not rewind buttons, fluids, platforms, server timers,
or hidden game-script variables. No autofarm is included.

## GitHub setup

Upload this directory's contents to the **root** of your repository on the `live`
branch. The default repository is `tomatotxt/TomatoTAS`. All modules use one configuration
and are fetched with `loadstring(game:HttpGet(...))` through the shared importer.
No ModuleScript `require` is used at runtime.

```lua
getgenv().TomatoTASConfig = {
    Owner = "tomatotxt",
    Repo = "TomatoTAS",
    Branch = "live",
    Directory = "TomatoTAS", -- executor-relative save folder
    File = "run",            -- default F6/F7 filename, without extension
    GUI = true,              -- false keeps the hotkey-only interface
    AutoPrepare = true,      -- prepares each live map after your character arrives
}
local c = getgenv().TomatoTASConfig
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/" .. c.Owner .. "/" .. c.Repo .. "/" .. c.Branch .. "/loader.luau",
    true
))()
```

The importer snapshots configuration, caches modules per launch, rejects circular
dependencies and invalid/missing source, and includes module paths in errors.
It validates capabilities and keybind settings before unloading an existing session.
Rerun the loader to fetch updates. For reproducible runs, `Branch` can instead be a
commit SHA. A moving branch can change between HTTP requests; a SHA avoids mixing
revisions. GitHub publication is not performed by this local build.

The local folder is initialized as a Git repository on `live`. Open this folder
in VS Code, commit the files in Source Control, then choose **Publish Branch**
to create `TomatoTAS` on GitHub. Choose public visibility for unauthenticated raw
HTTP loading. No remote is preconfigured, so VS Code can handle publication.

## First run

The GUI opens automatically. Drag its header to reposition it, use **Hide** to
collapse it to a launcher, or **×** to unload the tool and release character control.
The window scales to the available screen area and persists across respawns.

- **Studio:** record, play, stop, prepare/clone, step frames, save named character
  marks, choose replay mode/speed, and toggle camera playback.
- **Branches:** select a continuation and inspect its final frame. The latest 60
  tips appear in the list; the branch-cycle hotkey can still reach every tip.
- **Files:** select or name a run, save/load it, and explicitly load backup or
  pending recovery files. Saving/loading through the GUI updates the default run
  name used by F6/F7.

Click the timeline to seek a stored frame after pausing recording. Seeking uses
recorded timestamps. Disabled controls explain their requirements in the status
bar when hovered. **New run** asks for a second click within four seconds before
replacing an existing in-memory run; save it first.

GUI updates run at 10 Hz, separately from the simulation callbacks. Presentation
errors remove the panel but leave the engine/hotkeys operational. Reload to reopen
the panel, or set `GUI = false` to run without it. No third-party UI library or
remote image assets are required.

1. Load the tool before a new FE2 round when possible, so it captures zipline data.
2. Enter the round and stay on its spawn while preparation completes automatically.
   Preparation finds the live map and your character, waits for one continuous
   second of spawn stability, and captures your exact spawn-relative transform.
   Small movements accumulate against the start of the stable interval. **F1** /
   **Prepare map** remains available for a manual retry; `AutoPrepare = false`
   restores manual-only preparation. Preparation does not start recording.
3. For a static local clone, press **F8**. This prepares a clone and respawns you
   onto its settled spawn. It does not simulate server-controlled map mechanics.
   Once respawn and character attachment succeed, the original map is deleted
   locally. While recording in the clone, incoming `Map` / `NewMap` models in
   `workspace.Multiplayer` are also deleted locally. Pause or stop ends this cleanup.
   Clone creation may take time on large maps; do not change rounds during it.
4. Press **F2** to record your own movement, then **F2** to pause.
5. Use **F4/F5** for a character mark/restore, **F10** for a single physics step,
   and **F2** to continue recording a new branch.
6. Press **F6** to save, **F3** to replay, and **F9** to release character control.

The first frame stores the exact character transform relative to the settled
spawn. Target-map playback applies that same relative transform, eliminating the
recorded spawn's random world offset. Prepare the target map before playback;
map name and spawn path must match the run.

## Controls

| Key | Action |
| --- | --- |
| F1 | Manually retry preparation of the current map and character |
| F2 | Record / pause recording |
| F3 | Play selected branch / pause playback |
| F4 | Save character mark `quick` and pause |
| F5 | Restore character mark `quick` |
| F6 | Save configured run file |
| F7 | Load configured run file |
| F8 | Clone prepared map, respawn and restore zipline data |
| F9 | Stop and release control |
| F10 | Advance and record one simulation frame while paused |
| `[` / `]` | Previous / next recorded frame on selected branch |
| `\` | Cycle branch tips |
| End | Unload and clean up |

Hotkeys are ignored while typing. During map operations, F9 cancels and End unloads;
other hotkeys are ignored until the operation finishes. Console
messages report errors and status, which also appear in the GUI's status bar.
Stopping an automatic preparation suppresses retries for that map and character;
press F1 to retry, or enter another round. Automatic preparation never replaces
an existing run: use **New run** if you want to record a different map.
Unavailable actions display guidance without changing character control. A failed
save or load also leaves an ongoing recording or playback active.

Override keys in `TomatoTASConfig` before loading. Use Roblox KeyCode names as strings,
or `false` to disable a binding. Unknown actions, invalid keys and duplicates are
rejected before the tool starts:

```lua
getgenv().TomatoTASConfig.Keybinds = {
    Record = "R",
    Stop = "X",
    NextBranch = "B",
    Save = false,
}
```

Action names: `Prepare`, `Record`, `Play`, `Mark`, `Restore`, `Save`, `Load`, `Clone`,
`Stop`, `Step`, `PreviousFrame`, `NextFrame`, `NextBranch`, `Unload`. Table entries
not supplied retain the default bindings above. Guidance text uses the default
key names; use your configured equivalent when remapping.

## Script API

```lua
local tas = getgenv().TomatoTAS
tas:NewRun()                  -- explicitly replace in-memory run; save first
tas:Record()
tas:Pause()
tas:Mark("before_jump")       -- CHARACTER ONLY
tas:Restore("before_jump")
tas:Seek(120)                 -- global tree node ID, not branch-relative index
tas:Play(240, "frames")       -- exact samples, one stored frame per simulation callback
tas:Play(240, "time")         -- interpolate by recorded relative simulation time
tas:SetSpeed(0.5)             -- time playback only; does not slow Roblox physics
tas:SetCamera(false)          -- release camera takeover immediately
tas:Save("practice")
tas:Load("practice")
tas:Load("practice", "backup") -- explicitly recover the previous verified save
tas:Load("practice", "pending") -- inspect a completed staged save after an IO failure
print(tas:Status())
print(tas:ListFiles())
tas:Stop()
tas:Destroy()
```

For yielding commands, use `tas:Command(function() tas:Prepare() end)` or the hotkeys
to serialize user actions. The API is intended for sequential use, not concurrent
calls from multiple scripts. `tas:Dispatch("Record")` uses the same precondition
checks as the hotkey; `tas:Cancel()` also cancels a pending map operation.
`tas:RestoreWorld()` explicitly errors until world simulation exists.

Recovery loads do not overwrite the primary file. Saves stage and verify the new
bytes, verify a backup of the old valid file, and then write the primary. If the
last write fails, the tool attempts to restore the old primary and retains the
`.pending` file. A corrupt primary does not overwrite an older backup. Executor
filesystem APIs do not provide a portable atomic rename; a process crash can
still require explicit recovery.
Validating an older save retains only parent timestamps instead of constructing a
second full frame history, reducing peak memory during backup checks.

## Modules

| Module | Responsibility |
| --- | --- |
| `loader.luau` | Shared GitHub configuration, HTTP loading and dependency cache |
| `src/App.luau` | Creator/Player modes, hotkeys, frame events, branches and marks |
| `src/core/Tree.luau` | Parent-linked frame history; old futures remain intact |
| `src/core/Quaternion.luau` | Normalized matrix conversion and shortest-path SLERP |
| `src/core/Sampling.luau` | Binary-search playback sampling and interpolation |
| `src/core/Codec.luau` | Bounded binary encoding, validation and checksum |
| `src/core/Scope.luau` | Connection/resource lifetime management |
| `src/runtime/Character.luau` | Character capture, puppet enforcement and restoration |
| `src/runtime/Map.luau` | Map arrival, spawn settle, reversible clone preparation, ropes |
| `src/runtime/Storage.luau` | Verified file saves, backups and loading |
| `src/Types.luau` | Shared data shapes and future world-provider contract |
| `src/ui/Panel.luau` | Independent native GUI, action wiring and widget lifetime |
| `src/ui/Model.luau` | Time formatting, file naming, timeline selection and display state |

## Recording and playback behavior

Recording samples `PostSimulation`, using accumulated simulation deltas as the
relative timeline. It records actual completed frames rather than inventing 60 Hz
samples when the client runs slower. Frame zero is captured when recording starts.
Single-frame advance waits for the next `PreSimulation` boundary before releasing
the held character, then captures exactly one completed simulation callback.
Playback applies character state on `PreSimulation`; camera playback uses
`RenderStepped`. These phases follow the [Roblox scheduler documentation](https://create.roblox.com/docs/reference/engine/classes/RunService).

Captured state includes root and camera transforms, linear/angular velocity,
root/hitbox dimensions, hip height, humanoid state and movement parameters,
slide/swing/walljump event flags, and active animation IDs, times, weights,
speeds, priorities and looping flags. Recorded health is telemetry only; playback
does not overwrite server-owned health. Transform positions and quaternions use
64-bit floats in the file to avoid additional float32 quantization.

Time mode interpolates position, velocity, orientation and compatible animation
positions. Discrete mechanics switch at sample boundaries. Frame mode visits every
stored sample once; its wall-clock speed depends on the playback client's frame
rate. Neither mode can guarantee server-side outcomes or exact touch-event timing.

Puppet mode anchors the root so physics cannot integrate it beyond the recorded
sample. Character controller and animation scripts are temporarily disabled;
captured animation tracks are directly positioned. A scoped MoveDirection override
returns normalized horizontal target velocity. Stopping restores script states, geometry,
camera and movement settings. The shared metamethod hook remains installed but
inactive, avoiding unsafe removal of hooks belonging to other tools.

Animation capture has a stable ordering; playback matches asset IDs and occurrence
counts across samples. A missing or inaccessible animation warns once per takeover
and does not abort position playback. Late-created hitboxes, animators and mechanic
events are refreshed. Camera replacement and failed restoration of a stale object
do not prevent the remaining cleanup. Format v1 lacks animation length and a unique
track-instance identifier, so loop wraps and indistinguishable same-ID tracks still
have interpolation limits.

Continuing from a character mark restores recorded pose, velocity, geometry and
public humanoid state, but restarting FE2's controller does not reconstruct its
private walljump/zipline/swim state machines. Test resumes around these mechanics
in-game; this is distinct from direct puppet playback, which replays their recorded
visible state. Cached zipline data is re-injected for cloned recording.

## Clone behavior and limitations

Preparation disables Archivable listeners before changing Archivable, processes
a dense array in batches, and restores original properties/listeners afterward.
It refuses listeners that cannot be reversibly disabled. Cloning itself is a
synchronous Roblox operation and can still briefly stall on a large map.
Preparation checks instance identity and parent relationships, so replacing parts
without changing the descendant count is detected. Failed placement of either map
rolls back the placement and disposes of the unfinished clone. Zipline packets are
associated with map instances; a later round cannot replace a sandbox's rope cache.

The sandbox preserves world coordinates for zipline nodes. During setup, the live
map is temporarily moved to ReplicatedStorage so failed cloning or respawn can
restore it. After the new character has successfully respawned at the clone and
attached, the source map is destroyed locally. It is no longer restored on unload;
wait for a new round or rejoin to obtain a fresh live map.

While recording or advancing a simulation frame in a committed sandbox, scoped
listeners remove existing and newly arriving `Map` / `NewMap` models directly
under `workspace.Multiplayer`. Renamed maps and replacement Multiplayer containers
are handled. Unrelated objects and the sandbox are left alone. Pausing, playback,
stopping, failure cleanup and unloading disconnect those listeners. Removal affects
your client; it does not delete the server's maps or other players' maps.

Clone scripts are disabled. The clone is a static
snapshot of the moment it was copied, not a reconstructed map at round start.
Server-controlled mechanics, client scripts that assume `workspace.Multiplayer.Map`,
and game updates can affect sandbox behavior. Test this integration before relying
on a run. No server scripts are copied or simulated.

## Tests

With the official [Luau CLI tools](https://github.com/luau-lang/luau/releases) on PATH:

```powershell
.\scripts\check.ps1
# Or point to the folder containing luau.exe and luau-compile.exe:
.\scripts\check.ps1 -ToolsDirectory 'C:\path\to\luau-tools'
```

The script compiles all production/test files, statically analyzes the pure core,
and runs every suite in `tests/`.
It passes the actual loader source into the loader tests as a program argument;
those tests neither download modules nor duplicate the loader implementation.

Core tests cover rotation conversion, interpolation, branching, timestamps,
binary roundtrips, corruption/truncation, and a 10,000-node history. Controller
tests use service doubles to cover recording, character marks, stepping, playback,
new runs, failure handling and unload. Clone tests check batching, cancellation,
and restoration of source properties/listeners after success and failure. Character
tests cover takeover ownership, animation reuse/failure, delayed instances, cameras
and best-effort cleanup. Storage tests inject failures at each save stage and check
recovery. Loader tests use HTTP fixtures to check configuration, caching, failures
and session preservation. They do not validate Roblox engine behavior
or executor compatibility. See `docs/VALIDATION.md` for the in-game acceptance plan
and `docs/FORMAT.md` for the file schema.
