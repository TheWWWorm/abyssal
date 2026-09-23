# Abyssal Engine 1.2.11 — browser build

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

- All 16 headless engine regression suites passed on Linux x86-64 with Godot
  4.7 and locally supplied compatible content.
- Rendered model deformation and gate rotation checks passed on OpenGL and
  Vulkan. The 300-model stress check passed on OpenGL, Chromium WebGL and
  Linux WebKit WebGL, including a constrained shader buffer in the browsers.
- All five publication tests passed, along with source allowlist and
  provenance validation.

## Scope and limitations

A physical iPhone was not available. Linux WebKit checks do not establish
compatibility with iOS Safari or its Metal backend. Linux WebKit reports
framebuffer blit warnings on both this build and the previous build; the
targeted geometry checks pass.

Eight existing OpenGL headlight smoothness and saturation checks fail on both
this build and unchanged 1.2.10 source. This browser update addresses model
deformation; it does not include native platform packages.
