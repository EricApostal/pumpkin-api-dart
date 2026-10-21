// Block callbacks read the state at the event position, not the event's `stateIndex`.
//
// A block callback's `stateIndex` is the index of the state within the block
// (`docs/block-callbacks.md`: `state id = baseStateId + stateIndex`), so using it as a state id
// resolves a vanilla block whose properties are missing and whose defaults silently apply. These
// tests pin the state resolution of two callbacks that were affected: the elevator contact's
// redstone (its `facing` and `powering`) and the gantry carriage's placement (`facing` and
// `axis_along_first`) — and the answer side of the `update-shape` hooks of the linear chassis and
// the gantry carriage, which must be a state index of the block, not a global state id.
import 'package:test/test.dart';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/chassis/chassis_logic.dart';
import 'package:create/src/contraptions/elevator/elevator_contact_logic.dart';
import 'package:create/src/contraptions/gantry/gantry_logic.dart';
import 'package:create/src/manifest/blocks.g.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockDefinition, BlockProperty, BlockStateLayout;

const contact = 'create:elevator_contact';
const carriage = 'create:gantry_carriage';
const shaft = 'create:gantry_shaft';

/// An elevator contact at [pos] facing [facing], powering when [powering].
BState contactState(Direction facing, {bool powering = false}) => BState(contact, {
  'facing': facing.serializedName,
  'powering': '$powering',
  'powered': 'false',
  'calling': 'false',
});

/// The layout of the manifest block [path] (`linear_chassis`): how the host numbers its states
/// (properties sorted by name, the manifest's default state). The registration builds the same
/// layout (`api/blocks.dart`, `hostProperty`), so an index derived here is the index the plugin's
/// `update-shape` answer must carry.
BlockStateLayout manifestLayout(String path) {
  final entry = kBlocks.firstWhere((b) => b.key == path);
  return BlockStateLayout(
    BlockDefinition(
      key: 'create:$path',
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
  group('elevator contact redstone reads the state at the position', () {
    test('a powering contact emits 15, a quiet one 0', () {
      const pos = (0, 0, 0);
      final powering = MapBlockGetter(blocks: {pos: contactState(Direction.east, powering: true)});
      final quiet = MapBlockGetter(blocks: {pos: contactState(Direction.east)});

      // `powering` is a property of the contact; the vanilla states a per-block index would
      // resolve have no such property, so the old decode always answered 0.
      expect(elevatorContactWeakPower(powering, pos, Direction.north), 15);
      expect(elevatorContactWeakPower(quiet, pos, Direction.north), 0);
    });

    test('a contact behind the reading side blocks the signal', () {
      const pos = (0, 0, 0);
      const east = (1, 0, 0);
      final level = MapBlockGetter(
        blocks: {
          pos: contactState(Direction.east, powering: true),
          east: contactState(Direction.west, powering: true),
        },
      );

      expect(elevatorContactWeakPower(level, pos, Direction.east), 0);
      expect(elevatorContactWeakPower(level, pos, Direction.north), 15);
    });

    test('wire does not connect on the side the contact faces', () {
      const pos = (0, 0, 0);
      final level = MapBlockGetter(blocks: {pos: contactState(Direction.east)});

      // `facing` comes from the state at `pos`: a contact facing east blocks the wire to the
      // west, and every other side connects. Reading a vanilla state instead would default
      // `facing` to south and refuse the north side.
      expect(elevatorContactCanConnect(level, pos, Direction.west), isFalse);
      expect(elevatorContactCanConnect(level, pos, Direction.north), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.south), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.up), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.down), isTrue);
      expect(elevatorContactCanConnect(level, pos, Direction.east), isTrue);
      expect(elevatorContactCanConnect(level, pos, null), isTrue);
    });
  });

  group('gantry carriage placement reads the state at the position', () {
    test('the placed carriage keeps its key and facing', () {
      const pos = (0, 0, 0);
      const west = (-1, 0, 0);
      final placed = BState(carriage, {
        'facing': 'east',
        'axis_along_first': 'true',
      });
      final level = MapBlockGetter(
        blocks: {
          pos: placed,
          // A shaft pointing up (axis y); facing east with `axis_along_first` the carriage
          // accepts a shaft on z, so the flag has to cycle.
          west: BState(shaft, {'facing': 'up'}),
        },
      );

      final next = gantryPlacementState(level, pos);
      // A per-block `stateIndex` used as a state id would resolve a vanilla block, and the
      // carriage would be replaced by it (`facing` would fall back to north).
      expect(next.key, carriage);
      expect(next.dir('facing'), Direction.east);
      expect(next.flag('axis_along_first'), isNot(placed.flag('axis_along_first')));
    });

    test('a shaft on the facing side does not decide the axis', () {
      const pos = (0, 0, 0);
      const east = (1, 0, 0);
      final placed = BState(carriage, {
        'facing': 'east',
        'axis_along_first': 'true',
      });
      final level = MapBlockGetter(
        blocks: {
          pos: placed,
          east: BState(shaft, {'facing': 'north'}),
        },
      );

      // The shaft behind a carriage facing east is to its west; the one to its east is in front.
      expect(gantryPlacementState(level, pos), placed);
    });
  });

  // The `update-shape` hook answers with the index of the new state *of the block*: the host takes
  // the answer only while it is below the block's state count and then looks the state up as
  // `states[index]` (`crates/pumpkin-core/src/block/blocks/dynamic.rs:194-198`, `state_id`). Both
  // callbacks used to answer with `BlockRegistry.resolveState(...)`, a global state id that is
  // always past that count for a plugin block, so the host discarded every answer and the state
  // never changed. The expected indices come from the layout of the block itself (built from the
  // manifest, like the registration builds it), never from a hard-coded number.
  group('the update-shape answers are indices of the block', () {
    final linearLayout = manifestLayout('linear_chassis');
    final carriageLayout = manifestLayout('gantry_carriage');

    test('the linear chassis answers with the index of its unglued state', () {
      // An x-axis chassis with the east side (its positive axis side, `sticky_top`) glued.
      const glued = BState('create:linear_chassis', {
        'axis': 'x',
        'sticky_top': 'true',
        'sticky_bottom': 'false',
      });
      const sameAxis = BState('create:linear_chassis', {
        'axis': 'x',
        'sticky_top': 'false',
        'sticky_bottom': 'false',
      });
      const otherAxis = BState('create:linear_chassis', {
        'axis': 'y',
        'sticky_top': 'false',
        'sticky_bottom': 'false',
      });
      const otherKind = BState('create:secondary_linear_chassis', {
        'axis': 'x',
        'sticky_top': 'false',
        'sticky_bottom': 'false',
      });
      final unglued = glued.setFlag('sticky_top', false);

      final index = linearChassisShapeAnswer(
        linearLayout,
        glued,
        Direction.east,
        sameAxis,
      );
      expect(index, linearLayout.indexOf(unglued.props));
      expect(index, isNotNull);
      // An index of the block, not a global state id (which is always past the count).
      expect(index!, lessThan(linearLayout.stateCount));

      // The glue is already gone, or the neighbour is a chassis of another kind or axis: the state
      // is kept.
      expect(
        linearChassisShapeAnswer(linearLayout, unglued, Direction.east, sameAxis),
        isNull,
      );
      expect(
        linearChassisShapeAnswer(linearLayout, glued, Direction.east, otherKind),
        isNull,
      );
      expect(
        linearChassisShapeAnswer(linearLayout, glued, Direction.east, otherAxis),
        isNull,
      );
      // The callback does not answer for a radial chassis at all (it has no glueable side); this
      // pins that the behaviour still returns early for it.
      expect(
        linearChassisShapeAnswer(
          manifestLayout('radial_chassis'),
          const BState('create:radial_chassis', {'axis': 'y'}),
          Direction.north,
          sameAxis,
        ),
        isNull,
      );
    });

    test('the gantry carriage answers with the index of its cycled state', () {
      // Facing north with `axis_along_first`: the valid shaft axis is y (the one left over from
      // the rotation axis x and the facing axis z).
      const facingNorth = BState(carriage, {
        'facing': 'north',
        'axis_along_first': 'true',
      });
      const shaftEast = BState(shaft, {
        'facing': 'east',
        'part': 'middle',
        'powered': 'false',
      });
      final verticalShaft = shaftEast.setValue('facing', 'up');
      final cycled = facingNorth.setFlag('axis_along_first', false);

      final index = gantryCarriageShapeAnswer(
        carriageLayout,
        facingNorth,
        Direction.south,
        shaftEast,
      );
      expect(index, carriageLayout.indexOf(cycled.props));
      expect(index, isNotNull);
      expect(index!, lessThan(carriageLayout.stateCount));

      // A shaft already on the valid axis, and a neighbour that is no shaft: the state is kept.
      expect(
        gantryCarriageShapeAnswer(
          carriageLayout,
          facingNorth,
          Direction.south,
          verticalShaft,
        ),
        isNull,
      );
      expect(
        gantryCarriageShapeAnswer(
          carriageLayout,
          facingNorth,
          Direction.south,
          BState.air,
        ),
        isNull,
      );
    });
  });
}
