// A schematic placed in a virtual world (pure): the `SchematicLevel` of Create. The template
// is transformed (mirror, then rotate around the origin) and its blocks kept by position relative
// to the anchor; the printer and the requirement checks read it, nothing touches the real world.
import 'dart:math' as math;
import 'dart:typed_data';

import '../api/block_state.dart';
import '../common/binary_nbt.dart';
import '../common/bounds.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../common/vec_helper.dart';
import '../core/nbt.dart';
import 'state_transform.dart';

/// A block of a template.
final class TemplateBlock {
  /// The position inside the template.
  final Pos pos;
  final BState state;

  /// Block entity data as binary NBT (with an `id`, without a position), or null.
  final List<int>? nbt;

  const TemplateBlock(this.pos, this.state, [this.nbt]);
}

/// An entity of a template.
final class TemplateEntity {
  final Vec3 pos;
  final Pos blockPos;

  /// The saved entity as binary NBT.
  final List<int> nbt;

  const TemplateEntity(this.pos, this.blockPos, this.nbt);
}

/// What `StructureTemplate` holds, as plain data.
final class TemplateData {
  final Pos size;
  final List<TemplateBlock> blocks;
  final List<TemplateEntity> entities;

  const TemplateData(this.size, this.blocks, [this.entities = const []]);

  static const TemplateData empty = TemplateData(posZero, []);

  bool get isEmpty => size == posZero;
}

/// A block of the schematic world, in transformed template coordinates.
final class SchematicBlock {
  final BState state;

  /// Block entity data (binary NBT with `id`), or null.
  final List<int>? nbt;

  const SchematicBlock(this.state, [this.nbt]);
}

/// An entity of the schematic: spawn data for the real world.
final class SchematicEntity {
  /// The transformed position relative to the anchor.
  final Vec3 relativePos;

  /// The block position relative to the anchor.
  final Pos relativeBlockPos;

  /// The entity as binary NBT with the position and rotation already transformed to
  /// [relativePos] (the caller adds the anchor with [withPosition]).
  final List<int> nbt;

  const SchematicEntity(this.relativePos, this.relativeBlockPos, this.nbt);

  /// The NBT with `Pos` set to the absolute [position] (a fresh UUID is assigned on spawn).
  List<int> withPosition(Vec3 position) {
    final parsed = BinaryNbt.read(nbt);
    if (parsed == null || parsed.root.kind != NbtKind.compound) return nbt;
    final m = {...parsed.root.asCompound};
    m['Pos'] = NbtValue.list([
      NbtValue.double64(position.$1),
      NbtValue.double64(position.$2),
      NbtValue.double64(position.$3),
    ]);
    m.remove('UUID');
    return BinaryNbt.write(NbtValue.compound(m), name: parsed.name);
  }
}

/// `SchematicLevel`: the transformed blocks of a schematic.
final class SchematicWorld {
  /// The anchor the schematic was deployed at (absolute).
  final Pos anchor;
  final Map<Pos, SchematicBlock> _blocks = {};
  final List<SchematicEntity> entities = [];
  BlockBounds _bounds = BlockBounds.single(posZero);

  SchematicWorld(this.anchor);

  /// Builds the world of [template] placed with [rotation] and [mirror] (mirror first), like
  /// `StructureTemplate.placeInWorld(world, anchor, anchor, settings, ...)` followed by the
  /// `extraBounds` widening of `SchematicPrinter.loadSchematic`.
  factory SchematicWorld.fromTemplate(
    TemplateData template, {
    required Pos anchor,
    BlockRotation rotation = BlockRotation.none,
    BlockMirror mirror = BlockMirror.none,
  }) {
    final world = SchematicWorld(anchor);
    for (final b in template.blocks) {
      if (b.state.key == 'minecraft:structure_void') continue;
      final p = transformPos(b.pos, mirror, rotation, posZero);
      world.setBlock(p, SchematicBlock(transformState(b.state, mirror, rotation), b.nbt));
    }
    for (final e in template.entities) {
      world.entities.add(_transformEntity(e, mirror, rotation));
    }
    // extraBounds = calculateRelativePosition(settings, size - 1)
    final far = transformPos(template.size.offset(-1, -1, -1), mirror, rotation, posZero);
    world._bounds = world._bounds.encapsulatePos(far);
    return world;
  }

  /// `setBlock`: stores [block] at the relative [pos] and widens the bounds.
  void setBlock(Pos pos, SchematicBlock block) {
    _bounds = _bounds.encapsulatePos(pos);
    _blocks[pos] = block;
  }

  /// `getBounds()`, relative to the anchor.
  BlockBounds get bounds => _bounds;

  /// `setBounds`.
  void setBounds(BlockBounds b) => _bounds = b;

  /// `getAllPositions()`: the relative positions that hold a block (air included).
  Iterable<Pos> get allPositions => _blocks.keys;

  /// `isEmpty` of the printer: no block was placed at all.
  bool get isWorldEmpty => _blocks.isEmpty;

  /// The block at the relative [pos]: the support layer below the bounds is dirt (so floor
  /// attached blocks keep their support while printing), blocks outside the bounds are air.
  SchematicBlock blockAt(Pos pos) {
    if (pos.$2 - _bounds.minY == -1) return const SchematicBlock(BState('minecraft:dirt'));
    if (_bounds.isInside(pos)) {
      final b = _blocks[pos];
      if (b != null) return SchematicBlock(_forPrinting(b.state), b.nbt);
    }
    return const SchematicBlock(BState.air);
  }

  /// The state at the relative [pos] (`getBlockState`).
  BState stateAt(Pos pos) => blockAt(pos).state;

  /// `processBlockStateForPrinting`: furnaces are not lit.
  static BState _forPrinting(BState s) {
    if (s.has('lit') && s.flag('lit') && _isFurnace(s.key)) return s.setFlag('lit', false);
    return s;
  }

  static bool _isFurnace(String key) =>
      key == 'minecraft:furnace' || key == 'minecraft:blast_furnace' || key == 'minecraft:smoker';

  /// `StructureTemplate.transform(Vec3, ...)` of an entity.
  static SchematicEntity _transformEntity(TemplateEntity e, BlockMirror mirror, BlockRotation rotation) {
    final pos = transformVec(e.pos, mirror, rotation, posZero);
    final blockPos = transformPos(e.blockPos, mirror, rotation, posZero);
    final parsed = BinaryNbt.read(e.nbt);
    var nbt = e.nbt;
    if (parsed != null && parsed.root.kind == NbtKind.compound) {
      final m = {...parsed.root.asCompound};
      // Entity rotation: yaw is mirrored and then rotated.
      final rot = m['Rotation'];
      if (rot != null && rot.kind == NbtKind.list) {
        final items = rot.value as List<NbtValue>;
        if (items.length >= 2) {
          var yaw = (items[0].value as num).toDouble();
          final pitch = items[1].value;
          yaw = switch (mirror) {
            BlockMirror.leftRight => 180.0 - yaw,
            BlockMirror.frontBack => -yaw,
            BlockMirror.none => yaw,
          };
          yaw += rotation.index * 90.0;
          m['Rotation'] = NbtValue.list([NbtValue.float(yaw), NbtValue.float((pitch as num).toDouble())]);
        }
      }
      m['Pos'] = NbtValue.list([NbtValue.double64(pos.$1), NbtValue.double64(pos.$2), NbtValue.double64(pos.$3)]);
      nbt = Uint8List.fromList(BinaryNbt.write(NbtValue.compound(m), name: parsed.name));
    }
    return SchematicEntity(pos, blockPos, nbt);
  }

  /// The largest relative coordinate extent, for sanity checks.
  int get volume => _bounds.xSpan * _bounds.ySpan * _bounds.zSpan;

  @override
  String toString() => 'SchematicWorld(anchor $anchor, ${_blocks.length} blocks, bounds $_bounds)';
}

/// `Math.max(10, ...)`-style helper used by the launched items; kept here for the distance maths.
int cannonTicksForDistance(Pos start, Pos target) =>
    math.max(10, (math.sqrt(math.sqrt(target.distSqr(start))) * 4).toInt());
