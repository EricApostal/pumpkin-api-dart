// `StickerBlockEntity`: the server keeps the extension state in the block state; the entity only
// answers whether the sticker is glued to a block (`isAttachedToBlock`), which the chassis/glue
// code asks for.
//
// Java: `content/contraptions/chassis/StickerBlockEntity` (the animation and the ComputerCraft
// peripheral are client-only / optional and not ported).
import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../blocks/actuator_contract.dart';
import '../glue/super_glue_entity.dart';
import 'chassis_logic.dart';

final class StickerBlockEntity extends CreateBlockEntity {
  StickerBlockEntity(super.worldId, super.pos);

  /// Stickers have no client state (the extension is in the block state).
  @override
  bool get syncsToClient => false;

  /// `isBlockStateExtended`.
  bool get isBlockStateExtended {
    final state = stateOfBlock;
    return isChassis(state) && state.flag('extended');
  }

  /// `isAttachedToBlock`: the block the sticker faces accepts a glued side.
  bool get isAttachedToBlock {
    final state = stateOfBlock;
    if (state.key != 'create:sticker') return false;
    final direction = state.dir('facing');
    if (direction == null) return false;
    final contraptionLevel = ActuatorHosts.levelOf(worldId);
    if (contraptionLevel == null) return false;
    final target = (this.pos.x, this.pos.y, this.pos.z).relative(direction);
    return isValidGlueFace(contraptionLevel, target, direction.opposite);
  }

  BState get stateOfBlock =>
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));
}
