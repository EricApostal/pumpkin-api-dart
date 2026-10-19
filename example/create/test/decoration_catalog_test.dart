import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

import 'package:create/src/decoration/roles.dart';
import 'package:create/src/decoration/shape_rules.dart';
import 'package:create/src/manifest/manifest.dart';

BlockProperty prop(ManifestProperty p) => switch (p.type) {
  'bool' => BlockProperty.boolean(p.name),
  'int' => BlockProperty.intRange(p.name, int.parse(p.values.first), int.parse(p.values.last)),
  _ => BlockProperty.enumeration(p.name, p.values),
};

List<String> domain(ManifestBlock m, String name) => m.properties.firstWhere((p) => p.name == name).values;

List<ShapeRule> shapeRulesOf(ManifestBlock m, DecorationRole role) => switch (role) {
  DecorationRole.stairs => stairShapeRules(),
  DecorationRole.slab => slabShapeRules(),
  DecorationRole.pane => paneShapeRules(),
  DecorationRole.girder => girderShapeRules(),
  DecorationRole.encasedGirder => girderEncasedShapeRules(),
  DecorationRole.copycatPanel => copycatPanelShapeRules(),
  DecorationRole.copycatStep => copycatStepShapeRules(),
  DecorationRole.placard => placardShapeRules(),
  DecorationRole.whistle => whistleShapeRules(),
  DecorationRole.whistleExtension => whistleExtenderShapeRules(),
  DecorationRole.slidingDoor => slidingDoorShapeRules(folds: m.key == 'framed_glass_door'),
  DecorationRole.trapdoor => trapdoorShapeRules(),
  DecorationRole.ladder => ladderShapeRules(),
  DecorationRole.scaffolding => scaffoldingShapeRules(),
  _ => const [],
};

void main() {
  final owned = [for (final m in kBlocks) if (ownsBlock(m)) m];

  test('ownership: the palettes, copper sets, decoration classes and bars', () {
    expect(owned.length, 378);
    final keys = owned.map((m) => m.key).toSet();
    for (final k in ['metal_girder', 'copycat_panel', 'steam_whistle', 'placard', 'andesite_door', 'granite_pillar', 'copper_tiles', 'oak_window', 'andesite_bars', 'copycat_base']) {
      expect(keys, contains(k));
    }
    // Not decoration: plain materials of the content module.
    for (final k in ['industrial_iron_block', 'zinc_block', 'shaft', 'brass_block']) {
      expect(keys, isNot(contains(k)));
    }
  });

  test('role counts', () {
    final counts = <DecorationRole, int>{};
    for (final m in owned) {
      counts.update(roleOf(m), (v) => v + 1, ifAbsent: () => 1);
    }
    expect(counts[DecorationRole.stairs], 72);
    expect(counts[DecorationRole.slab], 72);
    expect(counts[DecorationRole.wall], 56);
    expect(counts[DecorationRole.pillar], 14);
    expect(counts[DecorationRole.pane], 3 + 17 + 1);
    expect(counts[DecorationRole.slidingDoor], 5);
    expect(counts[DecorationRole.trapdoor], 2);
    expect(counts[DecorationRole.casing], 6);
    expect(counts[DecorationRole.ladder], 3);
    expect(counts[DecorationRole.scaffolding], 3);
    expect(counts[DecorationRole.bracket], 2);
    expect(counts[DecorationRole.girder], 1);
    expect(counts[DecorationRole.encasedGirder], 1);
    expect(counts[DecorationRole.copycatPanel], 1);
    expect(counts[DecorationRole.copycatStep], 1);
    expect(counts[DecorationRole.copycatBars], 1);
    expect(counts[DecorationRole.copycatBase], 1);
    expect(counts[DecorationRole.placard], 1);
    expect(counts[DecorationRole.whistle], 1);
    expect(counts[DecorationRole.whistleExtension], 1);
    expect(counts[DecorationRole.cardboard], 2);
    expect(counts[DecorationRole.copperFull], 8);
  });

  test('every owned block makes a valid host definition with valid placement and shape rules', () {
    for (final m in owned) {
      final role = roleOf(m);
      final rules = shapeRulesOf(m, role);
      final def = BlockDefinition(
        key: 'create:${m.key}',
        properties: [for (final p in m.properties) prop(p)],
        defaultState: m.defaultState,
        hardness: m.hardness,
        blastResistance: m.blastResistance,
        soundType: m.soundType.toLowerCase(),
        shapeRules: rules,
      );
      expect(def.validate(), isEmpty, reason: m.key);
      expect(rules.length, lessThanOrEqualTo(64), reason: '${m.key} has too many shape rules');
      for (final r in rules) {
        r.when.forEach((k, v) {
          expect(m.properties.map((p) => p.name), contains(k), reason: '${m.key} shape rule property $k');
          expect(domain(m, k), contains(v), reason: '${m.key} shape rule value $k=$v');
        });
      }
      for (final r in placementRulesOf(role)) {
        expect(m.properties.map((p) => p.name), contains(r.property), reason: '${m.key} placement property');
        final values = domain(m, r.property);
        switch (r.source) {
          case PlacementSourceKind.horizontalFacing:
            expect(values, containsAll(['north', 'south', 'east', 'west']), reason: m.key);
          case PlacementSourceKind.lookingDirection:
            expect(values, containsAll(['north', 'south', 'east', 'west', 'up', 'down']), reason: m.key);
          case PlacementSourceKind.clickedHalf:
            expect(values, containsAll(['top', 'bottom']), reason: m.key);
          case PlacementSourceKind.clickedAxis:
            expect(values, containsAll(['x', 'y', 'z']), reason: m.key);
          case PlacementSourceKind.inWater:
            expect(values, containsAll(['true', 'false']), reason: m.key);
          default:
            break;
        }
      }
    }
  });

  test('shape rules cover every state of the blocks that rely on them', () {
    for (final m in owned) {
      final role = roleOf(m);
      if (const {DecorationRole.stairs, DecorationRole.ladder, DecorationRole.trapdoor, DecorationRole.copycatStep, DecorationRole.copycatPanel}
          .contains(role)) {
        final rules = shapeRulesOf(m, role);
        final def = BlockDefinition(
          key: 'create:${m.key}',
          properties: [for (final p in m.properties) prop(p)],
          defaultState: m.defaultState,
          hardness: 1,
          blastResistance: 1,
        );
        final layout = def.layout;
        for (var i = 0; i < layout.stateCount; i++) {
          final values = layout.valuesAt(i);
          final matched = rules.any((r) => r.when.entries.every((e) => values[e.key] == e.value));
          expect(matched, isTrue, reason: '${m.key} state $values has no shape rule');
        }
      }
    }
  });

  test('loot tables are used for slabs, doors, glass and the special blocks', () {
    bool lootOf(String key) => usesLootTable(kBlocks.firstWhere((m) => m.key == key), roleOf(kBlocks.firstWhere((m) => m.key == key)));
    expect(lootOf('cut_granite_slab'), isTrue);
    expect(lootOf('waxed_copper_tile_slab'), isTrue);
    expect(lootOf('andesite_door'), isTrue);
    expect(lootOf('framed_glass'), isTrue);
    expect(lootOf('oak_window_pane'), isTrue);
    expect(lootOf('tiled_glass'), isTrue);
    expect(lootOf('metal_girder_encased_shaft'), isTrue);
    expect(lootOf('bound_cardboard_block'), isTrue);
    expect(lootOf('cut_granite_stairs'), isFalse);
    expect(lootOf('andesite_bars'), isFalse);
    expect(lootOf('framed_glass_trapdoor'), isFalse);
    expect(lootOf('metal_girder'), isFalse);
    // 72 slabs + 5 doors + 36 glass + 3 more (encased girder, bound cardboard; copper slabs counted above).
    expect(owned.where((m) => usesLootTable(m, roleOf(m))).length, 72 + 5 + 36 + 1 + 1 - 0);
  });
}
