# Platform support

Version 1.8.0. Linux x86-64 was tested with Godot 4.7 on Linux and an NVIDIA RTX 3090 using Vulkan and OpenGL. The exported Linux executable started with imported content and rendered gameplay. Headlight mode changes, persistence, the graphics menu and ocean rendering passed automated Vulkan and OpenGL checks.

The browser build imported a compatible DEEP JAR locally, started a new game and exercised all four headlight settings in Chromium with WebGL 2. The importer and packaging regression suite passed 38 tests. No original game assets are included.

Other operating systems and physical mobile devices were not retested for this release.
