// The anchor rules of the contraption kinds: the controller block (and the blocks that belong to
// it) stays in the world while the structure in front is captured. These rules live in
// `isAnchoringBlockAt`, so the tests assemble against a map level and look at the captured local
// positions.
import 'dart:io';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/bearing/bearing_contraptions.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/gantry/gantry_contraption.dart';
import 'package:create/src/trains/bogey/standard_bogey_block.dart';
import 'package:create/src/trains/entity/carriage_contraption.dart';
import 'package:create/src/trains/entity/carriage_storage.dart';
import 'package:create/src/trains/entity/contraption_data.dart';
import 'package:create/src/trains/entity/train_level.dart';
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

/// The `ContraptionData` a [CarriageContraption] reads (the contraptions module implements it for
/// the real contraption; here it is the captured blocks of the [Contraption] below).
final class _CapturedView implements ContraptionData {
  _CapturedView(this.contraption);

  final Contraption contraption;

  @override
  Map<Pos, ContraptionBlockInfo> getBlocks() => {
    for (final entry in contraption.blocks.entries)
      entry.key: ContraptionBlockInfo(entry.value.state),
  };

  @override
  Pos get anchor => contraption.anchor;

  @override
  Pos toLocalPos(Pos pos) => contraption.toLocalPos(pos);

  @override
  List<Pos> getSeats() => const [];

  @override
  Map<String, int> getSeatMapping() => const {};

  @override
  Pos? getSeatOf(String passengerUuid) => null;

  @override
  void cancelActorStalls() {}

  @override
  void startMoving(TrainLevel level) {}

  @override
  void onEntityInitialize(TrainLevel level, Object entity) {}

  @override
  CarriageStorage? takeStorage() => null;

  @override
  void setPortalHiding(
    bool Function(Pos localPos) hiddenInPortal,
    bool Function() collidersHidden,
  ) {}

  @override
  void returnStorage(CarriageStorage storage) {}

  @override
  Future<void> removeBlocksFromWorld() async {}

  @override
  void expandBoundsAroundAxis(Axis axis) {}
}

/// The two lines of the host carriage contraption (`HostCarriageContraption`) that the train
/// assembly depends on: the anchor rule comes from the pure [CarriageContraption], and the check
/// after the search is [CarriageContraption.checkAssembly]. The host class itself needs the wasm
/// bindings, so it cannot be loaded here.
final class _CarriageHost extends Contraption {
  _CarriageHost(this.train) {
    train.data = _CapturedView(this);
  }

  final CarriageContraption train;

  @override
  bool isAnchoringBlockAt(Pos pos) => train.isAnchoringBlockAt(pos);

  @override
  CapturedBlock capture(ContraptionLevel level, Pos pos) {
    train.capture(level.stateAt(pos), pos);
    return super.capture(level, pos);
  }

  bool assembleCarriage(ContraptionLevel level, Pos pos) =>
      searchMovedStructure(level, pos, null) && train.checkAssembly();
}

const _stone = BState('minecraft:stone');
const _bogey = BState('create:small_bogey', {
  'axis': 'x',
  'waterlogged': 'false',
});
const _bogeyAlongZ = BState('create:small_bogey', {
  'axis': 'z',
  'waterlogged': 'false',
});
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
    'a carriage captures the bogey it is anchored at',
    () async {
      StandardBogeyBlock.registerStandardBlocks();

      // The station hands the carriage assembly the bogey block itself
      // (`StationBlockEntity.assemble`: the bogey position, not the block in front of it), so the
      // search starts *on* the bogey. Java's `CarriageContraption.isAnchoringBlockAt` returns
      // false for exactly that reason; the base class would skip the anchor and leave the
      // structure empty, which the station reports as "no structure attached to Bogey 1".
      final level = _MapLevel({
        (0, 0, 0): _bogey,
        // The carriage body beside the bogey, along its `axis`: the bogey's sticky side drags it
        // in.
        (1, 0, 0): _stone,
      });

      final contraption = _CarriageHost(CarriageContraption(Direction.east));
      expect(contraption.assembleCarriage(level, (0, 0, 0)), isTrue);

      expect(contraption.blocks.keys, contains((0, 0, 0)));
      expect(contraption.blocks.keys, contains((1, 0, 0)));
      expect(contraption.train.bogeys, 1);
    },
  );

  test(
    'a z-axis bogey drags the carriage body along z, not x',
    () async {
      StandardBogeyBlock.registerStandardBlocks();

      // `AbstractBogeyBlock.getStickySurfaces` reads the `axis` property (Java's
      // `BlockStateProperties.HORIZONTAL_AXIS` is named `axis`). Reading `horizontal_axis` found
      // nothing, so every bogey fell back to `x` and a bogey on a north-south track never picked
      // up the carriage body in front of it.
      final level = _MapLevel({
        (0, 0, 0): _bogeyAlongZ,
        // Along the bogey's sticky side (north/south).
        (0, 0, 1): _stone,
        // Off that side: not dragged in.
        (1, 0, 0): _stone,
      });

      final contraption = _CarriageHost(CarriageContraption(Direction.north));
      expect(contraption.assembleCarriage(level, (0, 0, 0)), isTrue);

      expect(contraption.blocks.keys, contains((0, 0, 1)));
      expect(contraption.blocks.keys, isNot(contains((1, 0, 0))));
    },
  );

  test(
    'the base anchor rule would capture nothing for a carriage, and the host keeps the override',
    () async {
      // The false condition behind `create.train_assembly.nothing_attached`: the station anchors
      // the carriage search *on the bogey* (`StationBlockEntity.assemble`), and the base
      // `Contraption.isAnchoringBlockAt` is `pos == anchor` (`contraption.dart`), so the search
      // skips the bogey itself. With the carriage body glued on top (not on the bogey's sticky
      // side) nothing else is dragged in, `CarriageContraption.checkAssembly` sees an empty
      // structure and the station answers "no structure attached to Bogey 1" however well the
      // carriage is glued (Java's `CarriageContraption.isAnchoringBlockAt` returns false).
      final base = Contraption();
      expect(
        await base.assemble(
          _MapLevel({(0, 0, 0): _bogey, (0, 1, 0): _stone}),
          (0, 0, 0),
        ),
        isTrue,
      );
      expect(base.blocks, isEmpty);
      expect(base.isAnchoringBlockAt((0, 0, 0)), isTrue);
      expect(CarriageContraption(Direction.north).isAnchoringBlockAt((0, 0, 0)), isFalse);

      // `HostCarriageContraption` reaches the wasm bindings, so it cannot be loaded here: the
      // rule above is tested through `_CarriageHost`, and this guards the one line that carries
      // it into the host class. Losing it is invisible to every other test (the host class is
      // never assembled on the VM) but turns every glued carriage back into "nothing attached".
      final host = File(
        'lib/src/contraptions/entity/carriage_contraption_host.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'@override\s+bool isAnchoringBlockAt\(Pos pos\)\s*=>\s*train\.isAnchoringBlockAt\(pos\);',
        ).hasMatch(host),
        isTrue,
        reason:
            'HostCarriageContraption must delegate the carriage anchor rule to the pure '
            'CarriageContraption, which answers false for every position',
      );
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
