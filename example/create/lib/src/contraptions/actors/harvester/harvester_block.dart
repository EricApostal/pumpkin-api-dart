// `HarvesterBlock` and `HarvesterBlockEntity`: the mechanical harvester block. The block entity only
// keeps the speed a Ponder scene animates it with.
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
import '../attached_actor_block.dart';

/// `HarvesterBlockEntity`.
final class HarvesterBlockEntity extends CreateBlockEntity {
  static const String type = 'create:harvester';

  HarvesterBlockEntity(super.worldId, super.pos);

  /// `manuallyAnimatedSpeed`: for simulations such as Ponder.
  double manuallyAnimatedSpeed = 0;

  double getAnimatedSpeed() => manuallyAnimatedSpeed;

  void setAnimatedSpeed(double speed) => manuallyAnimatedSpeed = speed;
}

/// `HarvesterBlock`.
CreateBlock buildHarvesterBlock() => buildAttachedActorBlock(
  'mechanical_harvester',
  blockEntityType: HarvesterBlockEntity.type,
);
