// The pure contraption core: assembly from a map level, the NBT round trip, positions and the
// actor lifecycle. The host is not involved, so this runs on the Dart VM.
//
// The anchor is the actuator block, which stays in the world; the subclass' `addToInitialFrontier`
// is what a real actuator uses to name the blocks the contraption starts from.
import 'dart:collection';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/chassis/chassis_logic.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/contraption_type.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/movement.dart';
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/conveyance/belt/belt_geometry.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A level over a map of states and block entity data.
final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;
  final Map<Pos, NbtMap> blockEntities;

  _MapLevel(this.blocks, [Map<Pos, NbtMap>? blockEntities])
    : blockEntities = blockEntities ?? {};

  @override
  String get worldId => 'test:world';

  @override
  ContraptionSettings get settings => DefaultContraptionSettings();

  @override
  BState stateAt(Pos p) => blocks[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) => !stateCollisionEmpty(stateAt(p));

  @override
  List<BlockBox> collisionBoxes(Pos p) => stateCollisionBoxes(stateAt(p));

  @override
  bool supportShapeEmpty(Pos p) => stateCollisionEmpty(stateAt(p));

  @override
  bool canBeReplaced(Pos p) => stateReplaceable(stateAt(p));

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;

  @override
  bool isOutsideBuildHeight(Pos p) => false;

  @override
  int get minY => -64;

  @override
  CapturedBlockEntity? blockEntityAt(Pos p) {
    final nbt = blockEntities[p];
    if (nbt == null) return null;
    return CapturedBlockEntity(nbt.getString('id'), nbt.copy(), nbt.copy());
  }

  @override
  PushReaction pushReaction(BState state) => PushReaction.normal;

  @override
  bool isUnbreakable(BState state) => false;

  @override
  bool stateHasTag(BState state, String tag) => false;

  @override
  bool stateCollisionEmpty(BState state) => state.isAir;

  @override
  bool stateReplaceable(BState state) => state.isAir;

  @override
  List<BlockBox> stateCollisionBoxes(BState state) =>
      state.isAir ? const [] : const [BlockBox(0, 0, 0, 1, 1, 1)];
}

/// A contraption whose initial frontier is given, like an actuator names the blocks it moves.
final class _TestContraption extends Contraption {
  final List<Pos> initial;

  _TestContraption(this.initial);

  @override
  bool addToInitialFrontier(
    ContraptionLevel level,
    Pos pos,
    Direction? forcedDirection,
    Queue<Pos> frontier,
  ) {
    frontier.addAll(initial);
    return true;
  }
}

void main() {
  const stone = BState('minecraft:stone');
  const dirt = BState('minecraft:dirt');

  test('assembles the blocks of the initial frontier', () async {
    final level = _MapLevel({
      (1, 0, 0): stone,
      (2, 0, 0): stone,
      (1, 0, 1): dirt,
    });

    final contraption = _TestContraption([(1, 0, 0), (2, 0, 0), (1, 0, 1)]);
    expect(await contraption.assemble(level, (0, 0, 0)), isTrue);
    expect(contraption.anchor, (0, 0, 0));
    expect(
      contraption.blocks.keys,
      containsAll([(1, 0, 0), (2, 0, 0), (1, 0, 1)]),
    );
    expect(contraption.blocks[(1, 0, 0)]!.state, stone);
    expect(contraption.toLocalPos((1, 2, 3)), (1, 2, 3));
    expect(contraption.toGlobalPos((1, 2, 3)), (1, 2, 3));
    expect(contraption.getSeats(), isEmpty);
  });

  test('round trips the NBT form', () async {
    final level = _MapLevel(
      {
        (6, 64, 5): const BState('minecraft:chest', {'facing': 'north'}),
      },
      {
        (6, 64, 5): NbtMap()
          ..putString('id', 'minecraft:chest')
          ..putInt('Value', 42),
      },
    );

    final contraption = _TestContraption([(6, 64, 5)]);
    await contraption.assemble(level, (5, 64, 5));
    contraption.getSeatMapping()['00000000-0000-0000-0000-000000000001'] = 0;

    final nbt = contraption.writeNbt();
    final restored = Contraption();
    restored.readNbt(level, nbt);

    expect(restored.anchor, (5, 64, 5));
    expect(restored.blocks.length, contraption.blocks.length);
    expect(
      restored.blocks[(1, 0, 0)]!.state,
      const BState('minecraft:chest', {'facing': 'north'}),
    );
    expect(restored.blocks[(1, 0, 0)]!.nbt!.getInt('Value'), 42);
    expect(restored.getSeatMapping(), {
      '00000000-0000-0000-0000-000000000001': 0,
    });
    expect(restored.typeId, ContraptionTypes.genericId);
  });

  test(
    'an actor is created for a movement behaviour and ticked by start/stop',
    () async {
      final behaviour = _CountingBehaviour();
      MovementBehaviours.register('minecraft:stone', behaviour);
      addTearDown(MovementBehaviours.registry.clear);

      final level = _MapLevel({(1, 0, 0): stone});
      final contraption = _TestContraption([(1, 0, 0)]);
      await contraption.assemble(level, (0, 0, 0));

      expect(contraption.getActors(), hasLength(1));
      contraption.startMoving(level);
      expect(behaviour.started, 1);
      expect(contraption.getActors().single.firstMovement, isTrue);

      contraption.stopMoving();
      expect(behaviour.stopped, 1);
      expect(contraption.getActors().single.position, isNull);
    },
  );

  test('bounds grow with the captured blocks', () async {
    final level = _MapLevel({(2, 3, 4): stone});
    final contraption = _TestContraption([(2, 3, 4)]);
    await contraption.assemble(level, (0, 0, 0));
    expect(contraption.bounds, isNotNull);
    expect(contraption.bounds!.maxX, 3);
    expect(contraption.bounds!.maxY, 4);
    expect(contraption.bounds!.maxZ, 5);
  });

  group('chassis ranges', () {
    const linear = BState('create:linear_chassis', {
      'axis': 'x',
      'sticky_top': 'true',
      'sticky_bottom': 'true',
    });
    const ungluedLinear = BState('create:linear_chassis', {
      'axis': 'x',
      'sticky_top': 'false',
      'sticky_bottom': 'false',
    });
    const radial = BState('create:radial_chassis', {
      'axis': 'y',
      'sticky_north': 'true',
      'sticky_south': 'true',
      'sticky_east': 'true',
      'sticky_west': 'true',
    });

    test('a linear chassis includes its range on both sticky sides', () {
      final level = _MapLevel({
        (0, 0, 0): linear,
        (1, 0, 0): stone,
        (2, 0, 0): stone,
        (3, 0, 0): stone,
        (-1, 0, 0): stone,
        (-2, 0, 0): stone,
        (-3, 0, 0): stone,
      });

      final positions = includedChassisPositions(level, (0, 0, 0), linear, 3, null);
      expect(positions.toSet(), {
        (1, 0, 0),
        (2, 0, 0),
        (3, 0, 0),
        (-1, 0, 0),
        (-2, 0, 0),
        (-3, 0, 0),
      });
      expect(positions, hasLength(6));
    });

    test('a linear chassis without glue follows only the forced movement', () {
      final level = _MapLevel({
        (0, 0, 0): ungluedLinear,
        (1, 0, 0): stone,
        (2, 0, 0): stone,
        (3, 0, 0): stone,
        (-1, 0, 0): stone,
        (-2, 0, 0): stone,
        (-3, 0, 0): stone,
      });

      expect(
        includedChassisPositions(
          level,
          (0, 0, 0),
          ungluedLinear,
          3,
          Direction.east,
        ).toSet(),
        {(1, 0, 0), (2, 0, 0), (3, 0, 0)},
      );
      expect(
        includedChassisPositions(level, (0, 0, 0), ungluedLinear, 3, null),
        isEmpty,
      );
    });

    test('adjacent linear chassis of the same kind join one group', () {
      const secondary = BState('create:secondary_linear_chassis', {
        'axis': 'x',
        'sticky_top': 'false',
        'sticky_bottom': 'false',
      });
      final level = _MapLevel({
        (0, 0, 0): linear,
        (1, 0, 0): linear,
        (0, 1, 0): linear,
        (0, 0, 1): secondary,
      });

      final group = <Pos>[];
      final visited = <Pos>{};
      final frontier = Queue<Pos>()..add((0, 0, 0));
      while (frontier.isNotEmpty) {
        final current = frontier.removeFirst();
        if (!visited.add(current)) continue;
        group.add(current);
        addAttachedChassesTo(
          level,
          current,
          level.stateAt(current),
          frontier,
          visited,
        );
      }

      // The secondary linear chassis and the different-axis neighbours stay out.
      expect(group.toSet(), {(0, 0, 0), (1, 0, 0), (0, 1, 0)});
    });

    test('a radial chassis includes its disc', () {
      final blocks = <Pos, BState>{};
      for (var dx = -3; dx <= 3; dx++) {
        for (var dz = -3; dz <= 3; dz++) {
          if (dx == 0 && dz == 0) continue;
          if (dx * dx + dz * dz <= 12) blocks[(dx, 0, dz)] = stone;
        }
      }
      blocks[(0, 0, 0)] = radial;
      final level = _MapLevel(blocks);

      final positions = includedChassisPositions(
        level,
        (0, 0, 0),
        radial,
        3,
        null,
      ).toSet();
      final expected = <Pos>{
        for (var dx = -3; dx <= 3; dx++)
          for (var dz = -3; dz <= 3; dz++)
            if (dx * dx + dz * dz <= 12 && (dx != 0 || dz != 0))
              (dx, 0, dz),
      };
      expect(positions, expected);
      expect(positions, hasLength(36));
    });

    test('the installed hooks drive assembly', () async {
      final level = _MapLevel({
        (0, 0, 0): stone,
        (1, 0, 0): linear,
        (2, 0, 0): stone,
        (3, 0, 0): stone,
        (4, 0, 0): stone,
      });
      ContraptionMovementHooks.addAttachedChasses = (lvl, pos, frontier, visited) =>
          addAttachedChassesTo(lvl, pos, lvl.stateAt(pos), frontier, visited);
      ContraptionMovementHooks.chassisIncludedPositions = (lvl, pos, direction) =>
          includedChassisPositions(lvl, pos, lvl.stateAt(pos), 3, direction);
      addTearDown(() {
        ContraptionMovementHooks.addAttachedChasses = null;
        ContraptionMovementHooks.chassisIncludedPositions = null;
      });

      final contraption = _TestContraption([(1, 0, 0)]);
      expect(await contraption.assemble(level, (0, 0, 0)), isTrue);
      expect(contraption.blocks.keys.toSet(), {
        (1, 0, 0),
        (2, 0, 0),
        (3, 0, 0),
        (4, 0, 0),
      });
    });
  });

  test('the belt hook follows a sloped segment', () async {
    const upward = BState('create:belt', {
      'facing': 'east',
      'part': 'middle',
      'slope': 'upward',
    });
    final level = _MapLevel({
      (0, 0, 0): stone,
      (1, 0, 0): upward,
      (2, 1, 0): stone,
    });

    // The straight-only fallback stops at the sloped segment's base.
    final straight = _TestContraption([(1, 0, 0)]);
    expect(await straight.assemble(level, (0, 0, 0)), isTrue);
    expect(straight.blocks.keys, isNot(contains((2, 1, 0))));

    ContraptionMovementHooks.beltNextSegment = nextSegmentPosition;
    addTearDown(() => ContraptionMovementHooks.beltNextSegment = null);
    final sloped = _TestContraption([(1, 0, 0)]);
    expect(await sloped.assemble(level, (0, 0, 0)), isTrue);
    expect(sloped.blocks.keys, contains((2, 1, 0)));
  });
}

final class _CountingBehaviour extends MovementBehaviour {
  int started = 0;
  int stopped = 0;

  @override
  Future<void> startMoving(MovementContext context) async => started++;

  @override
  Future<void> stopMoving(MovementContext context) async => stopped++;
}
