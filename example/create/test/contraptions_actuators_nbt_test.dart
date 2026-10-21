// The pure NBT surface of the actuator contraptions and their data records: the keys, types and
// defaults of the `writeNbt`/`readNbt` pair against the Java reference. The block entities live on
// the host, but the contraption NBT and the column/glue records are pure, so this runs on the Dart
// VM.
//
// Java references: `BearingContraption`, `ClockworkContraption`, `PistonContraption`,
// `PulleyContraption`, `GantryContraption`, `MountedContraption`, `ElevatorColumn.ColumnCoords` and
// `SuperGlueEntity`.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/bearing/bearing_contraptions.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/elevator/elevator_column_coords.dart';
import 'package:create/src/contraptions/gantry/gantry_contraption.dart';
import 'package:create/src/contraptions/glue/super_glue_entity.dart';
import 'package:create/src/contraptions/mounted/mounted_contraption.dart';
import 'package:create/src/contraptions/piston/piston_contraption.dart';
import 'package:create/src/contraptions/pulley/pulley_contraption.dart';
import 'package:create/src/core/nbt.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A level over a map of states; blocks are full cubes and air is replaceable.
final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;

  _MapLevel([Map<Pos, BState>? blocks]) : blocks = blocks ?? {};

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

void main() {
  final level = _MapLevel();

  group('BearingContraption', () {
    test('round trips sails and facing', () {
      final contraption = BearingContraption(true, Direction.east)
        ..sailBlocks = 7;

      final nbt = contraption.writeNbt();
      expect(nbt.getString('Type'), 'create:bearing');
      expect(nbt.getInt('Sails'), 7);
      expect(nbt.getInt('Facing'), Direction.east.data3d);

      final restored = BearingContraption()..readNbt(level, nbt);
      expect(restored.sailBlocks, 7);
      expect(restored.facing, Direction.east);
    });

    test('missing keys default to no sails and direction 0 (down)', () {
      // `getIntOr("Sails", 0)` / `Direction.from3DDataValue(getIntOr("Facing", 0))`.
      final restored = BearingContraption()..readNbt(level, NbtMap());
      expect(restored.sailBlocks, 0);
      expect(restored.facing, Direction.down);
    });
  });

  group('ClockworkContraption', () {
    test('round trips facing, offset and the hand type', () {
      final contraption = ClockworkContraption()
        ..facing = Direction.south
        ..handType = HandType.minute
        ..offset = 3;

      final nbt = contraption.writeNbt();
      expect(nbt.getInt('facing'), Direction.south.data3d);
      expect(nbt.getInt('offset'), 3);
      // `handType.name()`: the Java enum name.
      expect(nbt.getString('HandType'), 'MINUTE');

      final restored = ClockworkContraption()..readNbt(level, nbt);
      expect(restored.facing, Direction.south);
      expect(restored.handType, HandType.minute);
      expect(restored.offset, 3);
    });

    test('a missing hand type reads as the first constant (hour)', () {
      final restored = ClockworkContraption()..readNbt(level, NbtMap());
      expect(restored.handType, HandType.hour);
      expect(restored.offset, 0);
      expect(restored.facing, Direction.down);
    });

    test('the Java name resolves to the intended hand, not the fallback', () {
      // `ClockworkContraption.java:110` writes `handType.name()`; `.java:118`
      // reads it with `readEnum` (first constant `HOUR` on an unknown name).
      expect(HandType.hour.javaName, 'HOUR');
      expect(HandType.minute.javaName, 'MINUTE');
      expect(HandType.fromName('MINUTE'), HandType.minute);
      expect(HandType.fromName('MINUTE'), isNot(HandType.values.first));
      expect(HandType.fromName('minute'), HandType.minute);
      expect(HandType.fromName('sideways'), HandType.hour);
    });
  });

  group('StabilizedContraption', () {
    test('round trips facing', () {
      final contraption = StabilizedContraption(Direction.west);
      final restored = StabilizedContraption()
        ..readNbt(level, contraption.writeNbt());
      expect(restored.facing, Direction.west);
      expect(contraption.writeNbt().getString('Type'), 'create:stabilized');
    });
  });

  group('PistonContraption', () {
    test('round trips the extension and orientation', () {
      final contraption = PistonContraption(Direction.up, true)
        ..initialExtensionProgress = 2
        ..extensionLength = 5;

      final nbt = contraption.writeNbt();
      expect(nbt.getString('Type'), 'create:piston');
      expect(nbt.getInt('InitialLength'), 2);
      expect(nbt.getInt('ExtensionLength'), 5);
      expect(nbt.getInt('Orientation'), Direction.up.data3d);

      final restored = PistonContraption(Direction.north, false)
        ..readNbt(level, nbt);
      expect(restored.initialExtensionProgress, 2);
      expect(restored.extensionLength, 5);
      expect(restored.orientation, Direction.up);
    });

    test('missing keys default to zero length and direction 0 (down)', () {
      final restored = PistonContraption()..readNbt(level, NbtMap());
      expect(restored.initialExtensionProgress, 0);
      expect(restored.extensionLength, 0);
      expect(restored.orientation, Direction.down);
    });
  });

  group('PulleyContraption', () {
    test('round trips the initial offset', () {
      final contraption = PulleyContraption(4);
      final nbt = contraption.writeNbt();
      expect(nbt.getString('Type'), 'create:pulley');
      expect(nbt.getInt('InitialOffset'), 4);

      final restored = PulleyContraption()..readNbt(level, nbt);
      expect(restored.initialOffset, 4);
    });
  });

  group('GantryContraption', () {
    test('round trips facing', () {
      final contraption = GantryContraption(Direction.west);
      final nbt = contraption.writeNbt();
      expect(nbt.getString('Type'), 'create:gantry');
      expect(nbt.getInt('Facing'), Direction.west.data3d);

      final restored = GantryContraption()..readNbt(level, nbt);
      expect(restored.facing, Direction.west);
    });
  });

  group('MountedContraption', () {
    test('round trips the rotation mode', () {
      final contraption = MountedContraption(CartMovementMode.rotationLocked);
      final nbt = contraption.writeNbt();
      expect(nbt.getString('Type'), 'create:mounted');
      // `rotationMode.name()`: the Java enum name.
      expect(nbt.getString('RotationMode'), 'ROTATION_LOCKED');

      final restored = MountedContraption()..readNbt(level, nbt);
      expect(restored.rotationMode, CartMovementMode.rotationLocked);
    });

    test('a missing rotation mode reads as the first constant (rotate)', () {
      final restored = MountedContraption()..readNbt(level, NbtMap());
      expect(restored.rotationMode, CartMovementMode.rotate);
    });
  });

  group('ElevatorColumn.ColumnCoords', () {
    test('writes the Java enum name and round trips', () {
      final coords = ColumnCoords(3, -7, Direction.east);
      final tag = coords.write();
      expect(tag.getInt('X'), 3);
      expect(tag.getInt('Z'), -7);
      // `side.name()`: `Direction.name()` is the upper case enum name.
      expect(tag.getString('Side'), 'EAST');
      expect(ColumnCoords.read(tag), coords);
    });

    test('a missing side defaults to Direction.values()[0] (down)', () {
      final restored = ColumnCoords.read(NbtMap());
      expect(restored.x, 0);
      expect(restored.z, 0);
      expect(restored.side, Direction.down);
    });
  });

  group('SuperGlueEntity box', () {
    test('round trips as two double lists', () {
      const box = Aabb(1, 2, 3, 4, 5, 6);
      final tag = NbtMap();
      writeGlueBox(tag, box);

      // `VecHelper.writeNBT`: `From`/`To` are lists of three doubles.
      expect(tag['From']!.kind, NbtKind.list);
      expect(tag.getVec('From'), (1.0, 2.0, 3.0));
      expect(tag.getVec('To'), (4.0, 5.0, 6.0));

      final restored = readGlueBox(tag);
      expect(restored.minX, 1);
      expect(restored.minY, 2);
      expect(restored.minZ, 3);
      expect(restored.maxX, 4);
      expect(restored.maxY, 5);
      expect(restored.maxZ, 6);
    });
  });
}
