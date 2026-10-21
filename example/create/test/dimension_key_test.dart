// The world id / dimension key guard.
//
// The host has two strings per world:
//
//  * `World.getId()` and `World.getName()` are the **world id**: the folder name (`world`,
//    `world_nether` — `get_world_name` of `crates/pumpkin-core/src/world/mod.rs`);
//  * `World.getDimension()` is the **dimension key**: `minecraft:overworld`, `minecraft:the_nether`.
//
// Using the first where the second is needed fails silently — a comparison that never matches, a
// lookup that returns null, nothing in the log. Four bugs of that shape have shipped: the chain
// conveyor sync (`t.worldId != 'minecraft:overworld'` never ran the tick), the station marker
// preview (`dimension` returned the folder name, so the client's `getGraphLocationAt` missed),
// the display link's `click_to_link_data` (a folder name where Java writes an `Identifier`), and
// the global logistics tick (`world.getId() == 'minecraft:overworld'` was never true).
//
// `World` is a host (wasm) resource: a unit test cannot construct one, so it cannot observe the
// value a site produces. What it can do is pin the **expression** at every site that crosses the
// boundary — the audit table of the sweep, as code. Each entry names a file, the marker that finds
// the site and the identifier the site must produce; a regression to `getId()`/`getName()` (or a
// dimension key where a world id is keyed) fails here, which is the only place it can fail
// cheaply. The behavioural half of the guard is `isOverworldDimension` below: the predicate the
// overworld checks go through.
import 'dart:io';

import 'package:create/src/logistics/model/overworld.dart'
    show isOverworldDimension, overworldDimension;
import 'package:test/test.dart';

/// One audited site: the identifier it must produce, and why it is the dimension-key (or
/// world-id) domain.
typedef Site = ({
  String file,
  String marker,
  String mustMatch,
  String? mustNotMatch,
  String why,
});

/// The sites of the `create` package that compare, key or look up a world identifier.
final List<Site> sites = [
  // -- the overworld checks (dimension key) ---------------------------------------------------
  (
    file: 'lib/src/conveyance/belts_registration.dart',
    marker: 'ctx.onWorldTick((t) {',
    mustMatch: 't.world.getDimension()',
    mustNotMatch: 't.worldId',
    why: 'the chain conveyor tick only runs in the overworld; `WorldTick.worldId` is the folder '
        'name, so comparing it with `minecraft:overworld` never matched (bug 1)',
  ),
  (
    file: 'lib/src/logistics/logistics_module.dart',
    marker: 'isOverworldDimension(e.targetWorld.getDimension())',
    mustMatch: 'getDimension()',
    mustNotMatch: 'getId()',
    why: 'the overworld load handler of the global logistics networks',
  ),
  (
    file: 'lib/src/logistics/logistics_module.dart',
    marker: 'isOverworldDimension(t.world.getDimension())',
    mustMatch: 'getDimension()',
    mustNotMatch: 'getId()',
    why: 'the global logistics tick: `t.worldId` is the folder name, so the networks never ticked',
  ),
  (
    file: 'lib/src/logistics/logistics_module.dart',
    marker: 'isOverworldDimension(world.getDimension())',
    mustMatch: 'getDimension()',
    mustNotMatch: 'getId()',
    why: 'the initial scan for the overworld in `onServerLoaded`',
  ),
  (
    file: 'lib/src/kinetics/block_entities.dart',
    marker: 'final isNatural =',
    mustMatch: 'w.getDimension()',
    mustNotMatch: 'getId()',
    why: 'a clock only runs on natural time, i.e. in the overworld',
  ),
  (
    file: 'lib/src/redstone/display/display_env.dart',
    marker: 'bool get naturalDimension',
    mustMatch: 'lvl.world.getDimension()',
    mustNotMatch: 'getId()',
    why: 'the display sources that read the sky need the dimension, not the folder',
  ),
  (
    file: 'lib/src/fluids/fluid_host.dart',
    marker: 'bool get waterEvaporates',
    mustMatch: 'world.dimension',
    mustNotMatch: 'getName()',
    why: 'water evaporates in the Nether: `World.dimension` is `getDimension()` on the binding',
  ),

  // -- the trains module (dimension key) -----------------------------------------------------
  (
    file: 'lib/src/trains/entity/train_host.dart',
    marker: 'String get dimension =>',
    mustMatch: 'world.getDimension()',
    mustNotMatch: 'getId()',
    why: 'the graph nodes, the carriage dimensional entities and the wire palette are keyed by '
        'the dimension key',
  ),
  (
    file: 'lib/src/trains/track/track_host.dart',
    marker: 'String get dimension =>',
    mustMatch: 'world.getDimension()',
    // The next declaration is `_worldId => world.getId()` (the store key, correct), so the window
    // cannot forbid `getId()` outright; the getter's own line must read the dimension.
    mustNotMatch: null,
    why: 'the station marker: the client resolves the node by the dimension key (bug 2)',
  ),
  (
    file: 'lib/src/trains/graph/graph_registration.dart',
    marker: 'final dimension =',
    mustMatch: 'getDimension()',
    mustNotMatch: 'EdgePointOwnerInfo(pos, blockEntity.worldId',
    why: 'the edge point\'s block entity dimension goes into the graph packet and the saved data; '
        '`blockEntity.worldId` is the store key (folder name)',
  ),
  (
    file: 'lib/src/trains/graph/graph_registration.dart',
    marker: 'EdgePointHooks.invalidateTargeting = (',
    mustMatch: 'worldIdOf(dimension)',
    mustNotMatch: null,
    why: 'the invalidation hook is handed a dimension key and reads the store, which is keyed by '
        'the world id',
  ),
  (
    file: 'lib/src/trains/signal/single_block_entity_edge_point.dart',
    marker: 'void blockEntityAdded(Object blockEntity, bool front) {',
    mustMatch: 'info.dimension',
    mustNotMatch: 'info.worldId',
    why: '`blockEntityDimension` is a dimension key; the owner info no longer carries a world id',
  ),
  (
    file: 'lib/src/trains/station/global_station.dart',
    marker: 'hooks.loadedPostbox(',
    mustMatch: 'loadedPostbox(dimension',
    mustNotMatch: 'loadedPostbox(worldId',
    why: 'the station hands its block entity dimension to the mail hooks',
  ),
  (
    file: 'lib/src/decoration/sliding_door_movement.dart',
    marker: 'final stationWorldId =',
    mustMatch: 'worldIdOf(',
    mustNotMatch: 'getId()',
    why: 'the door control reads the block entity store with the station\'s dimension',
  ),
  (
    file: 'lib/src/trains/observer/observer_registration.dart',
    marker: 'api.testItem(',
    mustMatch: "api.testItem(''",
    mustNotMatch: 'overworldId',
    why: 'the filter test is not world scoped; a dimension key in a world-id slot is misleading',
  ),
  (
    file: 'lib/src/trains/manager/manager_registration.dart',
    marker: 'ctx.savedData.markDirty(',
    mustMatch: 'world.getId()',
    mustNotMatch: 'overworldId',
    why: 'saved data is keyed by the world id, the same string `flushWorld` looks the world up by',
  ),
  (
    file: 'lib/src/logistics/host/runtime.dart',
    marker: '_overworldWorldId =',
    mustMatch: 'touch(overworld)',
    mustNotMatch: 'overworldDimension',
    why: 'the global saved data is marked dirty with the world id, not with the dimension key',
  ),

  // -- the dimension key itself --------------------------------------------------------------
  (
    file: 'lib/src/redstone/support/level.dart',
    marker: 'String get dimension =>',
    mustMatch: 'world.getDimension()',
    mustNotMatch: 'getId()',
    why: 'the level view exposes both identifiers: `id` is the folder name, `dimension` the key',
  ),
  (
    file: 'lib/src/redstone/display/display_link_block.dart',
    marker: 'final dimension =',
    mustMatch: 'lvl.dimension',
    mustNotMatch: 'getId()',
    why: '`click_to_link_data.selected_dim` is an `Identifier` on the wire (bug 3)',
  ),
  (
    file: 'lib/src/schematics/host/world_view.dart',
    marker: 'final dimension =',
    mustMatch: 'world.getDimension()',
    mustNotMatch: 'getId()',
    why: 'the schematic viewer asks whether water evaporates in the dimension',
  ),
];

/// The source of [file], read from the package root (the working directory of `dart test`).
String _source(String file) {
  final handle = File(file);
  if (!handle.existsSync()) {
    fail('missing source file $file (run the test from the package root)');
  }
  return handle.readAsStringSync();
}

/// The [lines] after the first line containing [marker].
String _around(String source, String marker, {int lines = 4}) {
  final index = source.indexOf(marker);
  if (index < 0) fail('marker not found: $marker');
  final start = source.lastIndexOf('\n', index) + 1;
  var end = start;
  for (var i = 0; i < lines; i++) {
    final next = source.indexOf('\n', end);
    if (next < 0) {
      end = source.length;
      break;
    }
    end = next + 1;
  }
  return source.substring(start, end);
}

void main() {
  group('the overworld predicate', () {
    test('accepts the dimension key', () {
      expect(overworldDimension, 'minecraft:overworld');
      expect(isOverworldDimension('minecraft:overworld'), isTrue);
    });

    test('rejects the world id the host reports as `World.getId()`', () {
      // The folder name of the overworld: what the logistics tick used to compare against.
      expect(isOverworldDimension('world'), isFalse);
      expect(isOverworldDimension('world_nether'), isFalse);
    });
  });

  group('every world identifier site produces the documented string', () {
    for (final site in sites) {
      test('${site.file} :: ${site.marker}', () {
        final text = _around(_source(site.file), site.marker);
        expect(
          text,
          contains(site.mustMatch),
          reason: '${site.why}\n--- $text',
        );
        final mustNot = site.mustNotMatch;
        if (mustNot != null) {
          expect(
            text,
            isNot(contains(mustNot)),
            reason: '${site.why}\n--- $text',
          );
        }
      });
    }
  });
}
