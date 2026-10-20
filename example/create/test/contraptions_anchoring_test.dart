// The anchor rules of the contraption kinds: the controller block (and the blocks that belong to
// it) stays in the world while the structure in front is captured. These rules live in
// `isAnchoringBlockAt`, so the tests assemble against a map level and look at the captured local
// positions.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/bearing/bearing_contraptions.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/gantry/gantry_contraption.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A level over a map of states; blocks are full cubes and air is replaceable.
final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;

  _MapLevel(this.blocks);

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
  CapturedBlockEntity? blockEntityAt(Pos p) => null;

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

const _stone = BState('minecraft:stone');
const _bearing = BState('create:mechanical_bearing', {'facing': 'south'});
const _carriage = BState('create:gantry_carriage', {'facing': 'south'});
const _slidingDoor = BState('create:train_door', {
  'hinge': 'left',
  'half': 'lower',
  'open': 'false',
  'facing': 'north',
  'visible': 'true',
});

const _door = BState('minecraft:oak_door', {
  'hinge': 'left',
  'half': 'lower',
  'open': 'false',
  'facing': 'north',
});

void main() {
  test(
    'a bearing captures the block in front, not the bearing or its neighbours',
    () async {
      final level = _MapLevel({
        (0, 0, 0): _bearing,
        (0, 0, 1): _stone,
        // Adjacent to the first block but not glued or attached: not part of the structure.
        (1, 0, 1): _stone,
      });

      final contraption = BearingContraption(false, Direction.south);
      expect(await contraption.assemble(level, (0, 0, 0)), isTrue);

      // The search starts at the block in front, which becomes local position zero.
      expect(contraption.blocks.keys, contains((0, 0, 0)));
      expect(contraption.blocks.keys, isNot(contains((1, 0, 0))));
      // The bearing block itself stays in the world.
      expect(contraption.blocks.keys, isNot(contains((-1, 0, 0))));
    },
  );

  test('a gantry contraption leaves the block behind the carriage', () async {
    final level = _MapLevel({
      (0, 0, -1): _stone,
      (0, 0, 0): _carriage,
      (0, 0, 1): _stone,
    });

    final contraption = GantryContraption(Direction.south);
    expect(await contraption.assemble(level, (0, 0, 0)), isTrue);

    expect(contraption.blocks.keys, contains((0, 0, 0)));
    expect(contraption.blocks.keys, contains((0, 0, 1)));
    // `isAnchoringBlockAt` skips the block behind the carriage.
    expect(contraption.blocks.keys, isNot(contains((0, 0, -1))));
  });

  test('a stabilized contraption captures the block in front', () async {
    final level = _MapLevel({(0, 0, 1): _stone});

    final contraption = StabilizedContraption(Direction.south);
    expect(await contraption.assemble(level, (0, 0, 0)), isTrue);
    expect(contraption.blocks.keys, contains((0, 0, 0)));
  });

  test(
    'a clockwork arm captures its first block and skips the bearing',
    () async {
      final level = _MapLevel({(0, 0, 0): _bearing, (0, 0, 1): _stone});

      final contraption = ClockworkContraption()
        ..facing = Direction.south
        ..handType = HandType.hour;
      expect(await contraption.assemble(level, (0, 0, 0)), isTrue);

      expect(contraption.blocks.keys, contains((0, 0, 0)));
      expect(contraption.blocks.keys, isNot(contains((0, 0, -1))));
    },
  );

  test(
    'sliding doors do not notify their neighbours after movement, other doors do',
    () {
      final contraption = Contraption();
      // `SlidingDoorBlock` is driven by its block entity; a vanilla door is not.
      expect(
        contraption.shouldUpdateAfterMovement(
          const StructureBlockInfo(posZero, _slidingDoor),
        ),
        isFalse,
      );
      expect(
        contraption.shouldUpdateAfterMovement(
          const StructureBlockInfo(posZero, _door),
        ),
        isTrue,
      );
      expect(
        contraption.shouldUpdateAfterMovement(
          const StructureBlockInfo(posZero, _stone),
        ),
        isTrue,
      );
    },
  );
}
