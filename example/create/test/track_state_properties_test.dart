// The properties of a `create:track` state, as the placement reads them.
//
// `TrackPlacement.tryConnect` checks `state1.hasProperty(TrackBlock.HAS_BE)` on the state of the
// position the held stack connects from (`TrackPlacement.java:170`, `track_placement.dart:135`).
// The host reports a plugin block's properties through its vanilla `Property` enum, which has no
// `turn` property and no rail `shape` value (`zo`, `cr_ndx`, ...), so it reported every track
// state as `{waterlogged=...}` and the check always failed: every second click answered
// "Original block removed, Sneak-click to reset".
//
// These tests pin the layout the plugin describes its own states with, so a state id keeps
// `shape` and `turn` without a host call.
import 'package:create/src/core/state_layouts.dart';
import 'package:create/src/manifest/blocks.g.dart';
import 'package:create/src/trains/track/i_track_block.dart';
import 'package:create/src/trains/track/track_shape.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

/// The `create:track` layout as the registration builds it from the manifest: `shape`, `turn` and
/// `waterlogged`, sorted by name.
BlockStateLayout trackLayout() {
  final entry = kBlocks.firstWhere((b) => b.key == 'track');
  return BlockStateLayout(
    BlockDefinition(
      key: 'create:track',
      properties: [
        for (final p in entry.properties)
          switch (p.type) {
            'bool' => BlockProperty.boolean(p.name),
            'int' => BlockProperty.intRange(
                p.name,
                int.parse(p.values.first),
                int.parse(p.values.last),
              ),
            _ => BlockProperty.enumeration(p.name, p.values),
          },
      ],
      defaultState: entry.defaultState,
      hardness: entry.hardness,
      blastResistance: entry.blastResistance,
    ),
  );
}

void main() {
  /// The host numbers the track states from its own base; any base works for the layout.
  const base = 38182;

  setUp(() => PluginStateLayouts.register('create:track', base, trackLayout()));
  tearDown(PluginStateLayouts.clear);

  group('create:track state properties', () {
    test('a track state keeps its shape and turn properties', () {
      final id = PluginStateLayouts.stateId('create:track', {
        trackShapeProperty: TrackShape.zo.serializedName,
        trackHasBeProperty: 'true',
        'waterlogged': 'false',
      });
      expect(id, isNotNull);

      final info = PluginStateLayouts.valuesAt(id!);
      expect(info, isNotNull);
      expect(info![trackShapeProperty], 'zo');
      expect(
        info[trackHasBeProperty],
        'true',
        reason: 'the placement needs `turn` on the state it connects from',
      );
      expect(info['waterlogged'], 'false');
      expect(PluginStateLayouts.of(id)?.key, 'create:track');
    });

    test('every track shape and turn combination has its own state', () {
      final seen = <int>{};
      for (final shape in TrackShape.values) {
        for (final turn in const ['true', 'false']) {
          final id = PluginStateLayouts.stateId('create:track', {
            trackShapeProperty: shape.serializedName,
            trackHasBeProperty: turn,
          })!;
          expect(seen.add(id), isTrue, reason: '${shape.serializedName}/$turn reuses a state');
          final values = PluginStateLayouts.valuesAt(id)!;
          expect(values[trackShapeProperty], shape.serializedName);
          expect(values[trackHasBeProperty], turn);
        }
      }
      expect(seen, hasLength(2 * TrackShape.values.length));
    });

    test('the state numbering is Java\'s: shape slowest, then turn, then waterlogged', () {
      // `TrackBlock.SHAPE`, `HAS_BE`, `WATERLOGGED`: properties sorted by name, the last one
      // fastest. 19 shapes x 2 turns x 2 waterlogged.
      int idOf(String shape, String turn, String waterlogged) =>
          PluginStateLayouts.stateId('create:track', {
            trackShapeProperty: shape,
            trackHasBeProperty: turn,
            'waterlogged': waterlogged,
          })!;

      expect(idOf('none', 'true', 'true'), base);
      expect(idOf('none', 'true', 'false'), base + 1);
      expect(idOf('none', 'false', 'true'), base + 2);
      expect(idOf('zo', 'true', 'true'), base + 4);
      expect(idOf('cr_ndz', 'false', 'false'), base + 18 * 4 + 3);
      expect(idOf('cr_ndz', 'false', 'false') - base + 1, 76);
    });

    test('an unknown property value is rejected instead of silently defaulted', () {
      expect(
        PluginStateLayouts.stateId('create:track', {trackShapeProperty: 'nope'}),
        isNull,
      );
      expect(PluginStateLayouts.stateId('create:rail', const {}), isNull);
    });
  });
}
