import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'crushing_keys.dart';
import 'crushing_wheel_block_entity.dart';
import 'crushing_wheel_blocks.dart';
import 'crushing_wheel_controller_block_entity.dart';

/// Crushing wheels and their controller (`CrushingWheelBlock`,
/// `CrushingWheelControllerBlock` and their block entities).
final class CrusherPart extends ProcessingPart {
  @override
  String get name => 'crusher';

  @override
  void register(CreateRegistry registry) {
    registry.block(buildCrushingWheelBlock());
    registry.block(buildCrushingWheelControllerBlock());
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: crushingWheelKey,
        validBlocks: const [crushingWheelKey],
        create: CrushingWheelBlockEntity.new,
        tickInterval: 1,
      ),
    );
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: crushingWheelControllerKey,
        validBlocks: const [crushingWheelControllerKey],
        create: CrushingWheelControllerBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    final kinetics = ctx.services.find<KineticNetworkService>();
    if (kinetics == null) {
      ctx.log.warn(
        'No kinetic network: the crushing wheels will not connect to shafts.',
      );
      return;
    }
    // `CrushingWheelBlock extends RotatedPillarKineticBlock`: a shaft at both ends of `axis`.
    kinetics.registerKineticBlock(crushingWheelKey, const AxisBlockDef());
  }
}
