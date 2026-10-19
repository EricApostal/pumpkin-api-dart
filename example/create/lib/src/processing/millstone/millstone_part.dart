import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'millstone_block_entity.dart';
import 'millstone_blocks.dart';
import 'millstone_keys.dart';

/// The millstone (`MillstoneBlock` / `MillstoneBlockEntity`): grinds one item at a time with a
/// `create:milling` recipe, driven by the kinetic network (a shaft or hand crank below it).
final class MillstonePart extends ProcessingPart {
  @override
  String get name => 'millstone';

  @override
  void register(CreateRegistry registry) {
    registry.block(buildMillstoneBlock());
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: millstoneKey,
        validBlocks: const [millstoneKey],
        create: MillstoneBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    final kinetics = ctx.services.find<KineticNetworkService>();
    if (kinetics == null) {
      ctx.log.warn('No kinetic network: the millstone will not turn.');
      return;
    }
    kinetics.registerKineticBlock(millstoneKey, const MillstoneKineticDef());
  }
}
