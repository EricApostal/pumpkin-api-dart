// `GantryContraption`: the structure carried by a gantry carriage. It translates along the shaft.
//
// Java: `content/contraptions/gantry/GantryContraption`.
import '../../common/common.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../entity/translating_contraption.dart';

class GantryContraption extends TranslatingContraption {
  Direction facing;

  GantryContraption([this.facing = Direction.north]);

  @override
  String get typeId => 'create:gantry';

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    if (!searchMovedStructure(level, pos, null)) return false;
    startMoving(level);
    return true;
  }

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
