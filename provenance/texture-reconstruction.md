# Texture reconstruction

The optional renderer in `game/native/textures/` reads the two original 128×128 atlases from an imported compatible DEEP JAR. It generates 1024×1024 colour atlases and a shallow hull/station normal atlas in private application storage.

`reconstruction_recipe.json` contains polygon contours, polynomial material colours, Gaussian shading fields and effect-density contours fitted to the v6 restoration artwork. `source_geometry.gd` keeps source-aligned markings and frames, including the imported insignia. `normal_recipe.gd` constructs shallow bevels analytically, keeping glass and painted pigment flat. Procedural grain is deterministic. The recipe contains artwork information derived from the restoration; it is not an artwork-independent upscaler. No original atlas, generated bitmap, raster residual or JAR is embedded in these files.

The engine's Apache-2.0 license does not grant rights to DEEP's original artwork or derivatives of that artwork. The original game attribution in `THIRD_PARTY_NOTICES.md` remains applicable.

The cache key includes the imported JAR identity, source-image hashes, recipe hash and renderer revision. Only a fully saved and verified set is activated. Native platforms render on a worker thread; single-threaded Web builds yield between scanlines. Texture filtering and mipmap generation remain in the normal model-library path.
