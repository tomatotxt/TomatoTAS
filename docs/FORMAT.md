# .fe2tomatas format — version 1

New format; legacy creator/player files are not supported. All numeric values
are little endian. `string` is a u32 byte count followed by that many raw bytes.
No executable source is stored or evaluated when loading a run.

In order:

1. string `FE2TOMATAS`, u32 version `1`.
2. string map name, string author, string spawn path, f64 creation Unix timestamp.
3. u32 total nodes, u32 selected node ID.
4. For every node in ascending ID order: u32 parent ID, then the frame below.
5. u32 mark count, then string name + u32 node ID per mark (names sorted on write).
6. u32 Adler-32 checksum of every preceding byte. This detects accidental corruption;
   it is not a cryptographic authenticity check.

Node 1 has parent 0 and time 0. Other parents must have smaller positive IDs.
Every child has a strictly later timestamp than its parent. Branch tips are
reconstructed from parent links. Multiple marks may refer to the same node.

Each frame stores f64 values in this order:

| Field | Count | Meaning |
| --- | ---: | --- |
| time | 1 | Relative simulation seconds |
| root | 7 | Spawn-local position XYZ, quaternion XYZW |
| velocity | 3 | Spawn-local linear velocity XYZ |
| angular | 3 | Spawn-local angular velocity XYZ |
| camera | 7 | Spawn-local camera position XYZ, quaternion XYZW |
| geometry | 7 | Root size XYZ, hitbox size XYZ, hip height |
| humanoid | 7 | State enum value, walk speed, jump power, jump height, AutoRotate flag, PlatformStand flag, health |
| flags | 3 | Sliding, swinging, walljump flags (0/1) |

Next comes u32 animation count. Each animation contains string asset ID followed
by five f64 values: time position, speed, weight, priority enum value, looped flag.
Discrete fields are retained as f64 in v1 for a simple fixed schema; a later
version may compact those without changing runtime frame shapes.

The fixed frame payload is 308 bytes before animations (38 f64 values and a u32
animation count). Each node adds 4 bytes for its parent. Transforms use normalized
quaternions; finite precision remains inherent to Roblox and floating-point math.

Defaults: 256 MiB file cap, one million nodes, 1 MiB per string, 256 animation
tracks per frame, 100,000 marks. Decoding validates checksums before parsing,
buffer bounds, parent ordering, time ordering, finite numbers, rotations,
geometry, flags, and animation fields. File data never supplies a URL or module.

World-state payloads are absent. Adding map-state rewind requires a new schema
version, a provider implementation, and migration/compatibility decisions.
