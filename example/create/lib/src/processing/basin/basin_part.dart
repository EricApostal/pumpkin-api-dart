// The basin: a 9 + 9 slot item inventory and two input / two output fluid tanks, the recipe
// filter, the spout and the heat level it reads from the block below. Presses and mixers drive
// it through `BasinOperatingBlockEntity`.
import '../../api/wrenchable.dart';
import '../../common/direction.dart';
import '../../contraptions/core/movement.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import 'basin_block.dart';
import 'basin_block_entity.dart';
import 'basin_movement.dart';

/// The basin.
final class BasinPart extends ProcessingPart {
  @override
  String get name => 'basin';

  @override
  void register(CreateRegistry registry) {
    registry.block(BasinBlock.build());
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: BasinBlockEntity.type,
        validBlocks: const [BasinBlock.key],
        create: (worldId, pos) => BasinBlockEntity(worldId, pos),
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    MovementBehaviours.register(BasinBlock.key, const BasinMovementBehaviour());
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    final wrench = runtime.services.find<WrenchRegistry>();
    if (wrench == null) return;
    wrench.register(
      BasinBlock.key,
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          final be = rt.store.typed<BasinBlockEntity>(
            rt.worlds.touch(c.world),
            c.pos,
          );
          if (be == null) return WrenchResult.pass;
          be.onWrenched(Direction.values[c.face.index]);
          return WrenchResult.success;
        },
      ),
    );
  }
}
