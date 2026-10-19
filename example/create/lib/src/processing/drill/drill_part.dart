// The mechanical drill part of the processing module: the block, its block entity and the
// contraption actor.
import '../../contraptions/core/movement.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../support/kinetics_bridge.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import 'drill_block.dart';
import 'drill_movement.dart';

/// The mechanical drill.
final class DrillPart extends ProcessingPart {
  @override
  String get name => 'drill';

  @override
  void register(CreateRegistry registry) {
    final spec = drillSpec();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:drill',
        validBlocks: [spec.block.key],
        create: DrillBlockEntity.new,
      ),
    );
    registry.block(spec.block);
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.find<KineticNetworkService>()?.registerKineticBlock(
      'create:mechanical_drill',
      const FacingBlockDef(shaftAtFront: false),
    );
    MovementBehaviours.register(
      'create:mechanical_drill',
      const DrillMovementBehaviour(),
    );
  }
}
