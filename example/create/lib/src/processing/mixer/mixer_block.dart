// `MechanicalMixerBlock`: the block and its kinetic rules (vertical axis, no shafts, needs at
// least medium speed).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../basin/basin_block.dart';
import '../processing_runtime.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import 'mixer_block_entity.dart';

/// `MechanicalMixerBlock`.
abstract final class MechanicalMixerBlock {
  static const String key = 'create:mechanical_mixer';

  /// `AllShapes.MECHANICAL_PROCESSOR_SHAPE`.
  static final BlockShape shape = BlockShape.boxes(const [
    BlockBox(0, 0, 0, 4 / 16, 1, 1),
    BlockBox(12 / 16, 0, 0, 1, 1, 1),
    BlockBox(4 / 16, 0, 0, 12 / 16, 1, 4 / 16),
    BlockBox(4 / 16, 0, 12 / 16, 12 / 16, 1, 1),
  ]);

  static CreateBlock build() => createBlockFromManifest(
    'mechanical_mixer',
    blockEntityType: MechanicalMixerBlockEntity.type,
    collisionShape: shape,
    selectionShape: shape,
    behavior: BlockBehavior(
      // `canSurvive`: no basin right below.
      onCanPlace: (server, e) => !BasinBlock.isBasin(
        ProcessingRuntime.instance.store,
        ProcessingRuntime.instance.worlds.touch(e.targetWorld),
        e.pos.toPos().below,
      ),
      isPathfindable: (server, e) => false,
    ),
  );
}

/// `MechanicalMixerBlock`'s `IRotate`: a vertical axis without shafts, at least medium speed.
final class MixerBlockDef extends KineticBlockDef {
  const MixerBlockDef();

  @override
  KAxis rotationAxis(KState state) => KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) => false;

  @override
  SpeedLevel get minimumRequiredSpeedLevel => SpeedLevel.medium;

  // `MechanicalMixerBlock implements ICogWheel` (`isSmallCog()` default true); with no shaft
  // faces it is the only path that can drive the mixer.
  @override
  bool get isSmallCog => true;
}
