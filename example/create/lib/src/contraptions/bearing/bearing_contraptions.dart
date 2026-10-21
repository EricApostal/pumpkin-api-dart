// `BearingContraption`, `ClockworkContraption` and `StabilizedContraption` (pure): the contraptions
// of the bearing family. A bearing captures the structure in front of it and rotates it around its
// facing axis; the clockwork bearing captures two arms (hour and minute) that may overlap, and a
// stabilized contraption is the sub-structure a bearing leaves behind.
//
// Java: `content/contraptions/bearing/{BearingContraption,ClockworkContraption,StabilizedContraption}`.
import 'dart:collection';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../conveyance/nbt_names.dart' show enumFromNbtName;
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../entity/controlled_contraption_entity.dart'
    show BearingContraptionLike;

/// `BearingContraption`.
class BearingContraption extends Contraption implements BearingContraptionLike {
  int sailBlocks = 0;
  Direction facing;
  bool isWindmill;

  BearingContraption([this.isWindmill = false, this.facing = Direction.north]);

  @override
  String get typeId => 'create:bearing';

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    // Java searches from the block in front of the bearing; that block is the anchor of the
    // structure (local position zero) and is captured by the search itself.
    final offset = pos.relative(facing);
    if (!searchMovedStructure(level, offset, null)) return false;
    startMoving(level);
    expandBoundsAroundAxis(facing.axis);
    if (isWindmill && sailBlocks < level.settings.minimumWindmillSails)
      throw AssemblyException.notEnoughSails(
        sailBlocks,
        level.settings.minimumWindmillSails,
      );
    if (blocks.isEmpty) return false;
    return true;
  }

  /// The bearing block itself (behind the anchor) stays in the world.
  @override
  bool isAnchoringBlockAt(Pos pos) => pos == anchor.relative(facing.opposite);

  @override
  bool canBeStabilized(Direction facing, Pos localPos) {
    if (facing.opposite == this.facing && localPos == posZero) return false;
    return facing.axis == this.facing.axis;
  }

  @override
  void addBlock(ContraptionLevel level, Pos pos, CapturedBlock captured) {
    final localPos = pos - anchor;
    if (!blocks.containsKey(localPos) && _isSail(level, captured)) sailBlocks++;
    super.addBlock(level, pos, captured);
  }

  /// `AllBlockTags.WINDMILL_SAILS.matches(getSailBlock(capture))`: a copycat panel counts as the
  /// material it copies.
  bool _isSail(ContraptionLevel level, CapturedBlock captured) {
    final state = captured.info.state;
    if (state.key == 'create:copycat_panel') {
      final material = captured.blockEntity?.saved.getCompoundOrNull(
        'Material',
      );
      final name = material?.getString('Name');
      if (name != null && name.isNotEmpty) {
        final key = name.contains(':') ? name : 'minecraft:$name';
        return level.stateHasTag(BState(key), 'create:windmill_sails');
      }
    }
    return level.stateHasTag(state, 'create:windmill_sails');
  }

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putInt('Sails', sailBlocks);
    tag.putInt('Facing', facing.data3d);
    return tag;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    sailBlocks = nbt.getInt('Sails');
    facing = Direction.from3DDataValue(nbt.getInt('Facing'));
    super.readNbt(level, nbt, spawnData: spawnData);
  }

  int getSailBlocks() => sailBlocks;

  Direction getFacing() => facing;
}

/// `ClockworkContraption`: one of the two hands of a clockwork bearing.
class ClockworkContraption extends Contraption {
  Direction facing = Direction.north;
  HandType handType = HandType.hour;
  int offset = 0;
  final Set<Pos> ignoreBlocks = {};

  @override
  String get typeId => 'create:clockwork';

  /// `assembleClockworkAt`: the hour arm, and the minute arm when the hour arm leaves blocks in
  /// front of it.
  static (ClockworkContraption, ClockworkContraption?)? assembleClockworkAt(
    ContraptionLevel level,
    Pos pos,
    Direction direction,
  ) {
    var hourArmBlocks = 0;

    final hourArm = ClockworkContraption()
      ..facing = direction
      ..handType = HandType.hour;
    if (!hourArm.assembleSync(level, pos)) return null;
    for (var i = 0; i < 16; i++) {
      final offsetPos = posZero.relative(direction, i);
      if (hourArm.blocks.containsKey(offsetPos)) continue;
      hourArmBlocks = i;
      break;
    }

    ClockworkContraption? minuteArm;
    if (hourArmBlocks > 0) {
      minuteArm = ClockworkContraption()
        ..facing = direction
        ..handType = HandType.minute
        ..offset = hourArmBlocks;
      minuteArm._ignore(hourArm.blocks.keys, hourArm.anchor);
      if (!minuteArm.assembleSync(level, pos)) return null;
      if (minuteArm.blocks.isEmpty) minuteArm = null;
    }

    hourArm.startMoving(level);
    hourArm.expandBoundsAroundAxis(direction.axis);
    if (minuteArm != null) {
      minuteArm.startMoving(level);
      minuteArm.expandBoundsAroundAxis(direction.axis);
    }
    return (hourArm, minuteArm);
  }

  void _ignore(Iterable<Pos> blocks, Pos anchor) {
    for (final p in blocks) {
      ignoreBlocks.add(anchor + p);
    }
  }

  /// `assemble` for the clockwork: `searchMovedStructure(world, pos.relative(direction, offset+1))`.
  bool assembleSync(ContraptionLevel level, Pos pos) {
    final start = pos.relative(facing, offset + 1);
    return searchMovedStructure(level, start, null);
  }

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async =>
      assembleSync(level, pos);

  /// The clockwork bearing block itself (behind the first arm block) stays in the world.
  @override
  bool isAnchoringBlockAt(Pos pos) =>
      pos == anchor.relative(facing.opposite, offset + 1);

  @override
  bool moveBlock(
    ContraptionLevel level,
    Direction? direction,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    while (frontier.isNotEmpty && ignoreBlocks.contains(frontier.first)) {
      visited.add(frontier.removeFirst());
    }
    if (frontier.isEmpty) return true;
    return super.moveBlock(level, direction, frontier, visited);
  }

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putInt('facing', facing.data3d);
    tag.putInt('offset', offset);
    // `ClockworkContraption.java:110`: `handType.name()` (`HOUR`/`MINUTE`).
    tag.putString('HandType', handType.javaName);
    return tag;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    facing = Direction.from3DDataValue(nbt.getInt('facing'));
    handType = HandType.fromName(nbt.getString('HandType'));
    offset = nbt.getInt('offset');
    super.readNbt(level, nbt, spawnData: spawnData);
  }

  @override
  bool canBeStabilized(Direction facing, Pos localPos) {
    if (localPos == posZero || localPos.relative(facing) == posZero)
      return false;
    return facing.axis == this.facing.axis;
  }
}

/// `ClockworkContraption.HandType`.
enum HandType {
  hour('HOUR'),
  minute('MINUTE');

  const HandType(this.javaName);

  /// The Java constant name (`HOUR`/`MINUTE`): the Dart identifier is the
  /// lower-case form, so NBT and the reader use this instead of `name`.
  final String javaName;

  /// `ClockworkContraption.readEnum`: the constant named [name], else the first
  /// constant (`HOUR`).
  static HandType fromName(String name) =>
      enumFromNbtName(name, values, nameOf: (h) => h.javaName);
}

/// `StabilizedContraption`: the sub-structure a bearing leaves in place.
class StabilizedContraption extends Contraption {
  Direction facing;

  StabilizedContraption([this.facing = Direction.north]);

  @override
  String get typeId => 'create:stabilized';

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    final offset = pos.relative(facing);
    if (!searchMovedStructure(level, offset, null)) return false;
    startMoving(level);
    if (blocks.isEmpty) return false;
    return true;
  }

  /// A stabilized sub-contraption has no controller block in its structure.
  @override
  bool isAnchoringBlockAt(Pos pos) => false;

  @override
  bool canBeStabilized(Direction facing, Pos localPos) => false;

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putInt('Facing', facing.data3d);
    return tag;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    facing = Direction.from3DDataValue(nbt.getInt('Facing'));
    super.readNbt(level, nbt, spawnData: spawnData);
  }

  Direction getFacing() => facing;
}
