// The mechanical press: a kinetic machine above a basin (compacting) or above a belt / depot /
// dropped item (pressing).

import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'press_block.dart';
import 'press_block_entity.dart';

/// The mechanical press.
final class PressPart extends ProcessingPart {
  @override
  String get name => 'press';

  @override
  void register(CreateRegistry registry) {
    registry.block(MechanicalPressBlock.build());
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: MechanicalPressBlockEntity.type,
        validBlocks: const [MechanicalPressBlock.key],
        create: (worldId, pos) => MechanicalPressBlockEntity(worldId, pos),
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    final kinetics = ctx.services.find<KineticNetworkService>();
    if (kinetics == null) return;
    // `getRotationAxis` / `hasShaftTowards`: a shaft along the facing axis.
    kinetics.registerKineticBlock(
      MechanicalPressBlock.key,
      const FacingAxisBlockDef(),
    );
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    final wrench = runtime.services.find<WrenchRegistry>();
    wrench?.registerDefault(const [MechanicalPressBlock.key]);
  }
}
