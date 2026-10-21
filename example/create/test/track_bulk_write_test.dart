// The batching and re-fire decisions of a bulk track write (`track_write_plan.dart`).
//
// `HostTrackLevel.setBlocks` writes a placement's blocks in one `world.placeBlocks` call with
// `skipBlockAddedCallback`, because the host calls back into the plugin once per written block
// and each of those callbacks is a host-to-plugin round trip of tens of milliseconds (measured;
// the write itself is microseconds). The plugin therefore has to run that `placed` handling
// itself for every block it wrote, or a block would be written without its block entity. These
// tests pin the two decisions that make that safe: which blocks the batch actually writes, and
// which of them get the re-fire - with the `stateIndex` and old state id a handler reads.
//
// The dispatch of the event to the registered handlers itself needs the host (`World`, `Server`)
// and is checked on a live server instead (the block entity of a written track and what a client
// receives): those types only exist inside the plugin's wasm store, so they cannot be built here.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/core/state_layouts.dart';
import 'package:create/src/manifest/blocks.g.dart';
import 'package:create/src/trains/track/i_track_block.dart';
import 'package:create/src/trains/track/track_shape.dart';
import 'package:create/src/trains/track/track_write_plan.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

/// A state layout for the manifest entry [key], the way the registration builds it
/// (`registry_apply.dart`: `PluginStateLayouts.register(block.key, entry.baseStateId, layout)`).
/// `track_state_properties_test.dart` builds the `create:track` one the same way.
BlockStateLayout layoutOf(String key) {
  final entry = kBlocks.firstWhere((b) => b.key == key);
  return BlockStateLayout(
    BlockDefinition(
      key: 'create:$key',
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

/// The host numbers a block's states from its own base; any base works as long as the plan and
/// the test agree on it.
const int trackBase = 38182;
const int fakeTrackBase = 42000;

/// The `create:track` state with [shape] and `turn`, as a placement writes it.
BState trackState(TrackShape shape, {bool turn = false}) => BState('create:track', {
  trackShapeProperty: shape.serializedName,
  trackHasBeProperty: turn ? 'true' : 'false',
  'waterlogged': 'false',
});

const BState fakeTrack = BState('create:fake_track', {'waterlogged': 'false'});

/// The state id of a plugin block state through the layouts (what the host's `get-state-id`
/// answers for a state the plugin registered).
int idOf(BState state) => PluginStateLayouts.stateId(state.key, state.props)!;

/// The state id of air on the host: a vanilla block is not in [PluginStateLayouts], it is what
/// was at a position a placement writes into.
const int airId = 0;

void main() {
  setUp(() {
    PluginStateLayouts.clear();
    PluginStateLayouts.register('create:track', trackBase, layoutOf('track'));
    PluginStateLayouts.register('create:fake_track', fakeTrackBase, layoutOf('fake_track'));
  });
  tearDown(PluginStateLayouts.clear);

  /// The state id at a position before the write: [states] where the plan is told about one,
  /// air everywhere else.
  int Function(Pos) currentStates(Map<Pos, int> states) =>
      (pos) => states[pos] ?? airId;

  group('planTrackWrite', () {
    test('writes every block that is not there yet, in order', () {
      final zo = trackState(TrackShape.zo);
      final xo = trackState(TrackShape.xo);

      final writes = planTrackWrite(
        <TrackChange>[((0, 0, 0), zo), ((0, 0, 1), zo), ((0, 0, 2), xo)],
        currentStateAt: currentStates(const {}),
        idOf: idOf,
      );

      expect([
        for (final (pos, _, _, _) in writes) pos,
      ], [(0, 0, 0), (0, 0, 1), (0, 0, 2)]);
      expect([for (final (_, _, id, _) in writes) id], [
        idOf(zo),
        idOf(zo),
        idOf(xo),
      ]);
      expect(
        [for (final (_, _, _, old) in writes) old],
        [airId, airId, airId],
        reason: 'the placed event carries the state that was at the position',
      );
    });

    test('a block that already has the state is not written', () {
      final zo = trackState(TrackShape.zo);

      final writes = planTrackWrite(
        <TrackChange>[((0, 0, 0), zo), ((0, 0, 1), zo)],
        currentStateAt: currentStates({(0, 0, 0): idOf(zo)}),
        idOf: idOf,
      );

      expect(
        [for (final (pos, _, _, _) in writes) pos],
        [(0, 0, 1)],
        reason:
            'an unchanged write is skipped, so a track written over itself keeps its block entity',
      );
    });

    test('a state the host does not know is dropped', () {
      final writes = planTrackWrite(
        <TrackChange>[((0, 0, 0), const BState('create:not_a_block'))],
        currentStateAt: currentStates(const {}),
        idOf: (_) => null,
      );

      expect(writes, isEmpty);
    });
  });

  group('planPlacedHandling', () {
    final turn = trackState(TrackShape.zo, turn: true);

    test('one placed event per written block, carrying its state index', () {
      final writes = <TrackWrite>[
        ((0, 0, 0), turn, idOf(turn), airId),
        ((0, 0, 1), fakeTrack, idOf(fakeTrack), airId),
      ];

      final plan = planPlacedHandling(writes);

      expect(
        plan,
        hasLength(writes.length),
        reason: 'the write and its placed handling are paired one to one',
      );
      final (pos, key, stateIndex, oldStateId) = plan.first!;
      expect(pos, (0, 0, 0));
      expect(key, 'create:track');
      expect(stateIndex, idOf(turn) - trackBase, reason: 'state id = baseStateId + stateIndex');
      expect(
        PluginStateLayouts.valuesAt(trackBase + stateIndex),
        turn.props,
        reason: 'the state index names the state that was written',
      );
      expect(
        oldStateId,
        airId,
        reason: 'a handler (`TrackBlock.onPlace`) reads the state that was replaced',
      );

      expect(plan[1]?.$2, 'create:fake_track', reason: 'a fake track has a placed handler too');
      expect(plan[1]?.$3, idOf(fakeTrack) - fakeTrackBase);
    });

    test('a block this plugin did not register gets no placed event', () {
      final plan = planPlacedHandling(<TrackWrite>[
        ((0, 0, 0), BState.air, airId, airId),
      ]);

      expect(
        plan,
        [isNull],
        reason: 'a vanilla block has no behavior of this plugin and no state index',
      );
    });

    test('the plan follows the write order, so a batch can be handled in place', () {
      final writes = <TrackWrite>[
        ((0, 0, 0), turn, idOf(turn), airId),
        ((0, 0, 1), BState.air, airId, airId),
        ((0, 0, 2), turn, idOf(turn), airId),
      ];

      expect([for (final p in planPlacedHandling(writes)) p?.$1], [
        (0, 0, 0),
        null,
        (0, 0, 2),
      ]);
    });
  });
}