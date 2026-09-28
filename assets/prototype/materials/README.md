# Tavern surface atlas

Original vector artwork authored for this project, 2026-09-24. No external asset pack, Jagex cache, or rimshare content is used.

`tavern_detail_atlas.svg` is a 512 x 256 greyscale detail atlas, eight 128 x 128 cells: plain, wood, stone, plaster, cloth, bread crust, iron, pottery. It modulates the existing vertex colours through `TavernMaterials`; geometry and palettes remain independently replaceable. Mipmaps are generated once for the shared texture.

The art builders opt into UVs and select surface IDs per part. All parts still share one mesh surface and material. Terrain and character meshes keep their existing materials.
