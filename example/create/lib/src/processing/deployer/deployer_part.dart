// The deployer part of the processing module: the block and its block entity, the kinetic rules,
// the wrench (mode change), the contraption actor and its moving interaction.
import '../../api/wrenchable.dart';
import '../../contraptions/core/movement.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'deployer_block.dart';
import 'deployer_block_entity.dart';
import 'deployer_movement_behaviour.dart';
import 'deployer_moving_interaction.dart';
import 'manual_application.dart';

/// The deployer.
final class DeployerPart extends ProcessingPart {
  @override
  String get name => 'deployer';

  @override
  void register(CreateRegistry registry) {
    final spec = deployerSpec();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:deployer',
        validBlocks: [spec.block.key],
        create: DeployerBlockEntity.new,
      ),
    );
    registry.block(spec.block);
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.find<KineticNetworkService>()?.registerKineticBlock(
      'create:deployer',
      const DeployerKineticDef(),
    );

    MovementBehaviours.register(
      'create:deployer',
      const DeployerMovementBehaviour(),
    );
    MovingInteractions.register(
      'create:deployer',
      const DeployerMovingInteraction(),
    );
    // `ManualApplicationRecipe.manualApplicationRecipesApplyInWorld`: item application
    // recipes also work when a player right-clicks a block with the tool.
    ManualApplication.install(ctx);
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    runtime.services.find<WrenchRegistry>()?.register(
      'create:deployer',
      CallbackWrenchable(beforeWrenched: deployerWrenched),
    );
  }
}
