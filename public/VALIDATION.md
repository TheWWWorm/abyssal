# Abyssal Engine 1.2.9 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

- The 15 engine regression suites passed on Linux x86-64 with Godot 4.7.2 and
  locally supplied compatible content. They cover the portable content pack,
  ship and cargo screens, equipment store tabs, creature movement, collision,
  continuous travel, encounter navigation, and S.T.R.E.A.M. gate streaming.
- A Linux x86-64 release package was unpacked and its executable launched
  with a locally prepared content pack.

## Scope and limitations

Windows, macOS, Linux ARM64, Android and Web gameplay were not run on their
target systems for this release. Export and archive checks establish that the
packages were produced, not that those targets have been validated in play.
Windows and macOS packages are unsigned, and macOS is not notarized.

Android uses version code 33 and the existing release signing key for in-place
updates that preserve imported content and saves.
