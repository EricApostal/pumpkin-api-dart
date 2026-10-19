// `PulleyContraption`: the structure hanging from a rope pulley. The pulley's rope blocks are
// anchored along the rope; the contraption translates vertically.
//
// Java: `content/contraptions/pulley/PulleyContraption`.
import 'dart:collection';

import '../../common/common.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../entity/translating_contraption.dart';

class PulleyContraption extends TranslatingContraption {
  int initialOffset;

  PulleyContraption([this.initialOffset = 0]);

  @override
  String get typeId => 'create:pulley';

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    if (!searchMovedStructure(level, pos, null)) return false;
    startMoving(level);
    return true;
  }

  /// `isAnchoringBlockAt`: the rope column from the pulley down to the anchor is not part of the
  /// structure. The core's anchoring rule only skips its own anchor, so the rope blocks are
  /// dropped from the frontier here.
  @override
  bool moveBlock(
    ContraptionLevel level,
    Direction? direction,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    while (frontier.isNotEmpty && _isRopeAboveAnchor(frontier.first)) {
      visited.add(frontier.removeFirst());
    }
    if (frontier.isEmpty) return true;
    return super.moveBlock(level, direction, frontier, visited);
  }

  bool _isRopeAboveAnchor(Pos p) {
    if (p.$1 != anchor.$1 || p.$3 != anchor.$3) return false;
    final y = p.$2;
    if (y <= anchor.$2 || y > anchor.$2 + initialOffset + 1) return false;
    return true;
  }

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putInt('InitialOffset', initialOffset);
    return tag;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    initialOffset = nbt.getInt('InitialOffset');
    super.readNbt(level, nbt, spawnData: spawnData);
  }

  int getInitialOffset() => initialOffset;
}
