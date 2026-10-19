// The mechanical mixer: mixes the contents of the basin two blocks below it.

import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'mixer_block.dart';
import 'mixer_block_entity.dart';

/// The mechanical mixer.
final class MixerPart extends ProcessingPart {
  @override
  String get name => 'mixer';

  @override
  void register(CreateRegistry registry) {
    registry.block(MechanicalMixerBlock.build());
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: MechanicalMixerBlockEntity.type,
        validBlocks: const [MechanicalMixerBlock.key],
        create: (worldId, pos) => MechanicalMixerBlockEntity(worldId, pos),
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    final kinetics = ctx.services.find<KineticNetworkService>();
    if (kinetics == null) return;
    kinetics.registerKineticBlock(
      MechanicalMixerBlock.key,
      const MixerBlockDef(),
    );
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    final wrench = runtime.services.find<WrenchRegistry>();
    wrench?.registerDefault(const [MechanicalMixerBlock.key]);
  }
}
