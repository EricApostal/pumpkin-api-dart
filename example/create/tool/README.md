
## Data pack (`package_datapack.dart`)

Embeds Create's data pack into the plugin as `lib/src/data/datapack.g.dart`
(generated, committed) and writes `lib/src/data/datapack_report.json` (per category
file counts and sizes, recipe type histogram, and the `type` of every recipe file).

```sh
cd example/create
PATH=$HOME/.puro/envs/master/flutter/bin/cache/dart-sdk/bin:$PATH \
  dart run tool/package_datapack.dart [--create ../../../../java/Create]   # or CREATE_MOD_DIR
```

Inputs: `src/generated/resources/data/**` and `src/main/resources/data/**` (the
hand written files win) and `pack.mcmeta` of the Java mod. Dropped: `.wiki`, the
`curios` and `quark` namespaces. JSON is minified; every category is one gzip blob
(base64, 4096 character chunks). Categories (config `datapack.<name>`): `recipes`,
`loot_tables`, `advancements`, `recipe_advancements` (off), `tags`, `structures`,
`registries` (off), `other` (off). Rerun after the Java mod's data changes; the
embedded hash changes and the plugin rewrites the pack on the next load. The format
code is `lib/src/data/pack_format.dart` (pure, with its own inflate for dart2wasm),
tested by `test/datapack_test.dart`.


## Blocks and items (`extract_blocks.dart`)

Generates `lib/src/manifest/blocks.g.dart` (`kBlocks`, 643 entries, registration
order), `lib/src/manifest/items.g.dart` (`kItems`, registration order) and
`lib/src/manifest/REPORT_blocks.md` (counts, cross-checks, entries marked
`verified: false`, assumptions). Data classes: `lib/src/manifest/types_blocks.dart`.

```sh
cd example/create
PATH=$HOME/.puro/envs/master/flutter/bin/cache/dart-sdk/bin:$PATH \
  dart run tool/extract_blocks.dart [--create DIR] [--mc DIR] [--out DIR] [--dump] [BLOCK_KEY ...]
```

* `--create` (or `CREATE_MOD_DIR`): the Create checkout, default `../../../../java/Create`.
* `--mc` (or `MC_SRC_DIR`): root of the decompiled Minecraft 26.3 sources (needed for vanilla
  parent classes, `BlockStateProperties`, `Blocks`). Default: the NeoForm
  `steps/transformSource/transformed` directory under `../../../../java/Registrate/build/neoForm/*`.
* catnip / ponder source jars are unzipped from `~/.m2` (needs `unzip`) into
  `.dart_tool/create_manifest/ext_src`.
* `BLOCK_KEY` arguments print the resolved class, properties (sorted by name, with value order),
  defaults and notes of that block; `--dump` prints every block.

How it works: `src/java.dart` / `src/expr.dart` scan the Java sources; `src/interp.dart`
flattens Registrate builder chains (including helper methods and `BuilderTransformers`);
`src/blocks_enum.dart` enumerates blocks in `static` initialiser order (explicit blocks, dyed
lists, copper sets, fluid blocks, palettes); `src/blocks_props.dart` resolves
`createBlockStateDefinition` / `registerDefaultState` through the Create and vanilla class
chains; `src/blocks_stats.dart` evaluates `BlockBehaviour.Properties` / `Item.Properties`;
`src/items_build.dart` enumerates items; `src/blocks_emit.dart` writes the Dart files.
The generated files carry a "GENERATED ... never hand-edit" header.
