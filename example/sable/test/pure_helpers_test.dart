// Pure helpers of the sub-level core: the math utilities, the heat section,
// water occlusion, the schematic context, the NBT field accessors and the
// entity helpers.
//
// Java: `SableMathUtils`, `HeatDataChunkSection`, `WaterOcclusionContainer`,
// `SubLevelSchematicSerializationContext`, `EntitySubLevelUtil`.
// create's NBT model and block positions are not exported from its barrel yet.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/core/nbt.dart' show NbtValue;
import 'package:pumpkin_api/pumpkin_api_core.dart' show PacketException;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A [SubLevelLookup] that always resolves to one object.
final class _Lookup implements SubLevelLookup {
  final Object? contained;

  _Lookup(this.contained);

  @override
  Object? containing(String dimensionId, (double, double, double) position) => contained;

  @override
  Object? trackingSubLevel(SablePlayer player) => null;
}

/// A minimal entity for [EntitySubLevelUtil].
final class _Entity implements SubLevelEntity {
  @override
  Vector3d position = Vector3d();

  @override
  Vector3d eyePosition = Vector3d();

  @override
  double eyeHeight = 1.62;

  @override
  Vector3d lookAngle = Vector3d(0, 0, 1);

  @override
  Vector3d deltaMovement = Vector3d();

  @override
  double boundingBoxHeight = 1.8;

  @override
  double xRot = 0;
  @override
  double yRot = 0;
  @override
  double yHeadRot = 0;
  @override
  double xOld = 0;
  @override
  double yOld = 0;
  @override
  double zOld = 0;
  @override
  double xo = 0;
  @override
  double yo = 0;
  @override
  double zo = 0;

  @override
  String typeId = 'minecraft:pig';

  @override
  bool isFallingBlock = false;
  @override
  bool isArrow = false;
  @override
  bool isHurtingProjectile = false;
  @override
  double accelerationPower = 0;

  /// The position the entity was snapped to.
  Vector3d? snapped;

  @override
  void snapTo(Vector3d position) {
    snapped = Vector3d.copy(position);
    this.position = Vector3d.copy(position);
  }

  /// The target of `lookAtFeet`.
  Vector3d? lookedAt;

  @override
  void lookAtFeet(Vector3d target) => lookedAt = Vector3d.copy(target);

  @override
  void setPosRaw(Vector3d position) => this.position = Vector3d.copy(position);
}

SubLevel makeSubLevel(FakeLevel level, FakeChunkHost host, {Pose3d? pose}) {
  final container = TestContainer(level, host);
  SubLevelContainer.register(container);
  return container.allocateSubLevel('00000000-0000-0000-0000-000000000001', 0, 0, pose ?? Pose3d());
}

void main() {
  group('SableMathUtils.getAngularVelocity', () {
    test('identical orientations give no angular velocity', () {
      final q = Quaterniond()..fromAxisAngle(Vector3d(0, 1, 0), 0.7);
      final result = SableMathUtils.getAngularVelocity(q, q, Vector3d());
      expect(result.length, closeTo(0, 1e-12));
    });

    test('a quarter turn about Y is pi/2 about -Y', () {
      final from = Quaterniond();
      final to = Quaterniond()..fromAxisAngle(Vector3d(0, 1, 0), math.pi / 2);
      final result = SableMathUtils.getAngularVelocity(from, to, Vector3d());
      expect(result.length, closeTo(math.pi / 2, 1e-9));
      expect(result.y, closeTo(-math.pi / 2, 1e-9));
      expect(result.x, closeTo(0, 1e-12));
      expect(result.z, closeTo(0, 1e-12));
    });

    test('a half turn about X is pi about -X', () {
      final from = Quaterniond();
      final to = Quaterniond()..fromAxisAngle(Vector3d(1, 0, 0), math.pi);
      final result = SableMathUtils.getAngularVelocity(from, to, Vector3d());
      expect(result.length, closeTo(math.pi, 1e-9));
      expect(result.x, closeTo(-math.pi, 1e-9));
    });

    test('the destination is written and returned', () {
      final dest = Vector3d(9, 9, 9);
      final result = SableMathUtils.getAngularVelocity(Quaterniond(), Quaterniond(), dest);
      expect(result, same(dest));
      expect(dest.length, 0);
    });
  });

  group('GridQuats', () {
    test('the groups hold the Java bit-pattern selections', () {
      expect(GridQuats.all.quaternions, hasLength(11));
      expect(GridQuats.xAxis.quaternions, hasLength(3));
      expect(GridQuats.yAxis.quaternions, hasLength(3));
      expect(GridQuats.zAxis.quaternions, hasLength(3));
      expect(GridQuats.real.quaternions, hasLength(5));
    });

    test('each group and its opposite partition the eleven base quaternions', () {
      for (final group in [
        GridQuats.all,
        GridQuats.xAxis,
        GridQuats.yAxis,
        GridQuats.zAxis,
        GridQuats.real,
      ]) {
        expect(group.quaternions.length + group.oppositeQuaternions.length, 11);
        expect(group.quaternions.toSet().intersection(group.oppositeQuaternions.toSet()), isEmpty);
      }
    });

    test('REAL is the identity, the three quarter turns and the corner rotation', () {
      expect(GridQuats.real.quaternions.first, Quaterniond(0, 0, 0, 1));
      expect(GridQuats.real.quaternions[1], Quaterniond(1, 0, 0, 1)..normalize());
      expect(GridQuats.real.quaternions[4], Quaterniond(1, 1, 1, 1)..normalize());
      expect(GridQuats.real.oppositeQuaternions, hasLength(6));
    });

    test('allGridQuaternions is GridQuats.ALL', () {
      expect(SableMathUtils.allGridQuaternions.toList(), GridQuats.all.quaternions);
    });
  });

  group('SableMathUtils.clampQuaternionToGrid', () {
    test('the identity snaps to the identity', () {
      final snapped = SableMathUtils.clampQuaternionToGrid(Quaterniond(), GridQuats.real.quaternions);
      expect(snapped, Quaterniond(0, 0, 0, 1));
    });

    test('a small rotation snaps back to the identity', () {
      final q = Quaterniond()..fromAxisAngleDeg(Vector3d(0, 1, 0), 10);
      final snapped = SableMathUtils.clampQuaternionToGrid(q, GridQuats.real.quaternions);
      expect(snapped.w, closeTo(1, 1e-12));
      expect(snapped.y, closeTo(0, 1e-12));
    });

    test('an exact quarter turn stays a quarter turn', () {
      final q = Quaterniond()..fromAxisAngleDeg(Vector3d(0, 1, 0), 90);
      final snapped = SableMathUtils.clampQuaternionToGrid(q, GridQuats.real.quaternions);
      expect(snapped.y, closeTo(math.sqrt1_2, 1e-12));
      expect(snapped.w, closeTo(math.sqrt1_2, 1e-12));
    });

    test('the sign of the input is restored on the result', () {
      final q = Quaterniond()..fromAxisAngleDeg(Vector3d(0, 1, 0), -90);
      final snapped = SableMathUtils.clampQuaternionToGrid(q, GridQuats.real.quaternions);
      expect(snapped.y, closeTo(-math.sqrt1_2, 1e-12));
      expect(snapped.w, closeTo(math.sqrt1_2, 1e-12));
    });

    test('the destination receives the result', () {
      final dest = Quaterniond(9, 9, 9, 9);
      final result = SableMathUtils.clampQuaternionToGrid(
        Quaterniond(),
        GridQuats.real.quaternions,
        dest,
      );
      expect(result, same(dest));
      expect(dest, Quaterniond(0, 0, 0, 1));
    });
  });

  group('HeatDataChunkSection', () {
    test('the index is y<<8 | z<<4 | x, matching the Java layout', () {
      expect(HeatDataChunkSection.indexOf(0, 0, 0), 0);
      expect(HeatDataChunkSection.indexOf(1, 0, 0), 1);
      expect(HeatDataChunkSection.indexOf(0, 0, 1), 16);
      expect(HeatDataChunkSection.indexOf(0, 1, 0), 256);
      expect(HeatDataChunkSection.indexOf(15, 15, 15), 4095);
    });

    test('set and get round trip; unset points are 0', () {
      final section = HeatDataChunkSection();
      expect(section.get(3, 4, 5), 0);
      section.set(3, 4, 5, 7);
      expect(section.get(3, 4, 5), 7);
      expect(section.get(5, 4, 3), 0);
    });

    test('clear resets every point', () {
      final section = HeatDataChunkSection()
        ..set(0, 0, 0, 1)
        ..set(15, 15, 15, 2)
        ..clear();
      expect(section.get(0, 0, 0), 0);
      expect(section.get(15, 15, 15), 0);
    });
  });

  group('WaterOcclusionContainer', () {
    test('a region occludes its occupied cells, with no pose offset', () {
      final volume = BoundedBitVolume3i(0, 0, 0, 1, 1, 1)..setOccupied(0, 0, 0, true);
      final container = ServerWaterOcclusionContainer('minecraft:overworld', _Lookup(null))
        ..addRegion(volume);

      expect(container.isOccluded((0.5, 0.5, 0.5)), isTrue);
      expect(container.isOccluded((1.5, 0.5, 0.5)), isFalse);
      expect(container.getOccludingRegion((0.5, 0.5, 0.5)), isNotNull);
      expect(container.getOccludingRegion((1.5, 0.5, 0.5)), isNull);
    });

    test('the region is transformed by its sub-level pose', () {
      final volume = BoundedBitVolume3i(0, 0, 0, 1, 1, 1)..setOccupied(0, 0, 0, true);
      final pose = Pose3d()..position().set(10, 0, 0);
      final container = ServerWaterOcclusionContainer(
        'minecraft:overworld',
        _Lookup('sub'),
        poseOf: (_) => pose,
      )..addRegion(volume);

      expect(container.isOccluded((10.5, 0.5, 0.5)), isTrue);
      expect(container.isOccluded((0.5, 0.5, 0.5)), isFalse);
    });

    test('markDirty marks regions touching the position or a neighbour', () {
      final near = WaterOcclusionRegion(BoundedBitVolume3i(0, 0, 0, 0, 0, 0)..setOccupied(0, 0, 0, true));
      final far = WaterOcclusionRegion(BoundedBitVolume3i(5, 0, 0, 5, 0, 0)..setOccupied(5, 0, 0, true));
      final container = ServerWaterOcclusionContainer('minecraft:overworld', _Lookup(null))
        ..addRegion(near.getVolume())
        ..addRegion(far.getVolume());
      final nearRegion = container.regions.firstWhere((r) => r.getVolume().minX == 0);

      container.markDirty((1, 0, 0));
      expect(nearRegion.isDirty(), isTrue);
      expect(container.regions.firstWhere((r) => r.getVolume().minX == 5).isDirty(), isFalse);

      nearRegion.clearDirty();
      expect(nearRegion.isDirty(), isFalse);
      container.markDirty((2, 0, 0));
      expect(nearRegion.isDirty(), isFalse);
    });

    test('addRegion returns the region; removeRegion removes it', () {
      final container = ServerWaterOcclusionContainer('minecraft:overworld', _Lookup(null));
      final region = container.addRegion(BoundedBitVolume3i(0, 0, 0, 0, 0, 0));
      expect(container.regions, {region});
      container.removeRegion(region);
      expect(container.regions, isEmpty);
    });

    test('register and unregister key the container by dimension', () {
      final level = FakeLevel();
      final container = ServerWaterOcclusionContainer(level.dimensionId, _Lookup(null));
      WaterOcclusionContainer.register(container);
      expect(WaterOcclusionContainer.of(level), same(container));
      WaterOcclusionContainer.unregister(level);
      expect(WaterOcclusionContainer.of(level), isNull);
    });
  });

  group('SubLevelSchematicSerializationContext', () {
    tearDown(() => SubLevelSchematicSerializationContext.setCurrentContext(null));

    test('the current context is a static slot, as Java\'s thread local is', () {
      expect(SubLevelSchematicSerializationContext.getCurrentContext(), isNull);
      final context = SubLevelSchematicSerializationContext(
        SchematicContextType.save,
        BoundingBox3i.values(0, 0, 0, 1, 1, 1),
      );
      SubLevelSchematicSerializationContext.setCurrentContext(context);
      expect(SubLevelSchematicSerializationContext.getCurrentContext(), same(context));
    });

    test('runWith installs the context and restores the previous one', () {
      final outer = SubLevelSchematicSerializationContext(
        SchematicContextType.save,
        BoundingBox3i.values(0, 0, 0, 1, 1, 1),
      );
      final inner = SubLevelSchematicSerializationContext(
        SchematicContextType.place,
        BoundingBox3i.values(2, 2, 2, 3, 3, 3),
      );
      SubLevelSchematicSerializationContext.setCurrentContext(outer);

      final seen = inner.runWith(() => SubLevelSchematicSerializationContext.getCurrentContext());
      expect(seen, same(inner));
      expect(SubLevelSchematicSerializationContext.getCurrentContext(), same(outer));
    });

    test('runWith restores the previous context even when the body throws', () {
      final context = SubLevelSchematicSerializationContext(
        SchematicContextType.save,
        BoundingBox3i.values(0, 0, 0, 1, 1, 1),
      );
      expect(
        () => context.runWith<void>(() => throw StateError('boom')),
        throwsStateError,
      );
      expect(SubLevelSchematicSerializationContext.getCurrentContext(), isNull);
    });

    test('transforms and mappings are stored and returned', () {
      final context = SubLevelSchematicSerializationContext(
        SchematicContextType.place,
        BoundingBox3i.values(0, 0, 0, 1, 1, 1),
      );
      Pos transform(Pos pos) => (pos.$1 + 1, pos.$2, pos.$3);
      context
        ..setPlaceTransform(transform)
        ..setSetupTransform(transform);

      expect(context.getPlaceTransform()!((0, 0, 0)), (1, 0, 0));
      expect(context.getSetupTransform()!((0, 0, 0)), (1, 0, 0));
      expect(context.getType(), SchematicContextType.place);
      expect(context.getBoundingBox().minX, 0);

      final level = FakeLevel();
      final subLevel = makeSubLevel(level, FakeChunkHost(level));
      final mapping = SchematicMapping(Vector3d(1, 2, 3), Quaterniond(), 'uuid', transform);
      context.getMappings()[subLevel.uniqueId] = mapping;
      expect(context.getMapping(subLevel), same(mapping));
      expect(context.getMappingById(subLevel.uniqueId), same(mapping));
      expect(context.getMappingById('other'), isNull);
    });
  });

  group('NbtFields', () {
    test('numeric fields accept every numeric tag kind', () {
      final map = {
        'byte': NbtValue.byte(3),
        'short': NbtValue.short(4),
        'int': NbtValue.int32(5),
        'long': NbtValue.long(6),
        'float': NbtValue.float(7.5),
        'double': NbtValue.double64(8.5),
      };
      expect(NbtFields.doubleOr(map, 'byte', -1), 3);
      expect(NbtFields.doubleOr(map, 'short', -1), 4);
      expect(NbtFields.doubleOr(map, 'int', -1), 5);
      expect(NbtFields.doubleOr(map, 'long', -1), 6);
      expect(NbtFields.doubleOr(map, 'float', -1), 7.5);
      expect(NbtFields.doubleOr(map, 'double', -1), 8.5);
    });

    test('an absent field takes the default; a required one throws', () {
      expect(NbtFields.doubleOr(const {}, 'x', 2.0), 2.0);
      expect(() => NbtFields.requireDouble(const {}, 'x'), throwsA(isA<PacketException>()));
      expect(() => NbtFields.requireString(const {}, 'x'), throwsA(isA<PacketException>()));
      expect(() => NbtFields.requireCompound(const {}, 'x'), throwsA(isA<PacketException>()));
    });

    test('a wrong tag kind is rejected', () {
      final map = {'s': NbtValue.string('x'), 'b': NbtValue.byte(1)};
      expect(() => NbtFields.doubleOr(map, 's', 0), throwsA(isA<PacketException>()));
      expect(() => NbtFields.stringOrNull(map, 'b'), throwsA(isA<PacketException>()));
    });

    test('a boolean is a byte, and any non-zero byte is true', () {
      expect(NbtFields.boolOr({'b': NbtValue.byte(2)}, 'b', false), isTrue);
      expect(NbtFields.boolOr({'b': NbtValue.byte(0)}, 'b', true), isFalse);
      expect(() => NbtFields.boolOr({'i': NbtValue.int32(1)}, 'i', false), throwsA(isA<PacketException>()));
    });

    test('a compound field is returned as a map', () {
      final map = {
        'c': NbtValue.compound({'k': NbtValue.int32(1)}),
      };
      final value = NbtFields.requireCompound(map, 'c')['k']!;
      expect(value.kind.name, 'int');
      expect(value.value, 1);
      expect(NbtFields.compoundOrNull(map, 'missing'), isNull);
    });
  });

  group('EntitySubLevelUtil', () {
    tearDown(() {
      EntitySubLevelUtil.retainInSubLevel.clear();
      EntitySubLevelUtil.trackingSubLevelLookup = null;
    });

    test('an entity type is kicked unless it is retained', () {
      final entity = _Entity();
      expect(EntitySubLevelUtil.shouldKick(entity), isTrue);
      EntitySubLevelUtil.retainInSubLevel.add(entity.typeId);
      expect(EntitySubLevelUtil.shouldKick(entity), isFalse);
    });

    test('without a tracking sub-level the old position is the current one', () {
      final entity = _Entity()..position = Vector3d(1, 2, 3);
      EntitySubLevelUtil.setOldPosNoMovement(entity);
      expect([entity.xOld, entity.yOld, entity.zOld], [1, 2, 3]);
      expect([entity.xo, entity.yo, entity.zo], [1, 2, 3]);
    });

    test('with a tracking sub-level the old position is projected through it', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final subLevel = makeSubLevel(level, host);
      subLevel.pose.position().set(10, 0, 0);
      subLevel.mutableLastPose.position().set(9, 0, 0);
      EntitySubLevelUtil.trackingSubLevelLookup = (_) => subLevel;

      final entity = _Entity()..position = Vector3d(10, 5, 0);
      EntitySubLevelUtil.setOldPosNoMovement(entity);

      expect(entity.xOld, closeTo(9, 1e-12));
      expect(entity.yOld, closeTo(5, 1e-12));
      expect(entity.zOld, closeTo(0, 1e-12));
    });

    test('kickEntity moves the entity by the pose and rotates its motion', () {
      final level = FakeLevel();
      final host = FakeChunkHost(level);
      final subLevel = makeSubLevel(level, host);
      subLevel.pose.position().set(10, 0, 0);

      final entity = _Entity()
        ..position = Vector3d(1, 2, 3)
        ..deltaMovement = Vector3d(0.5, 0, 0);
      EntitySubLevelUtil.kickEntity(subLevel, entity);

      expect(entity.snapped, Vector3d(11, 2, 3));
      expect(entity.deltaMovement.x, closeTo(0.5, 1e-12));
      expect(entity.lookedAt, isNotNull);
    });

    test('a custom entity orientation is not provided by the model', () {
      expect(EntitySubLevelUtil.getCustomEntityOrientation(_Entity(), 0), isNull);
      expect(EntitySubLevelUtil.hasCustomEntityOrientation(_Entity()), isFalse);
    });
  });
}