// The blaze burner: fuel, heat levels, the lit burner and the empty burner item.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../../fluids/boiler.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import 'blaze_burner_block.dart';
import 'blaze_burner_block_entity.dart';

/// The blaze burner.
final class BlazeBurnerPart extends ProcessingPart {
  @override
  String get name => 'burner';

  @override
  void register(CreateRegistry registry) {
    registry.block(BlazeBurnerBlock.build());
    registry.block(LitBlazeBurnerBlock.build());
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: BlazeBurnerBlockEntity.type,
        validBlocks: const [BlazeBurnerBlock.key],
        create: (worldId, pos) => BlazeBurnerBlockEntity(worldId, pos),
      ),
    );
    // `AllItems.EMPTY_BLAZE_BURNER`: a block item of the burner that places it unlit.
    registry.item(const ItemRegistration(key: BlazeBurnerBlock.emptyItemKey));
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    // `BlazeBurnerBlockItem.registerBlocks`: the empty burner is a block item too.
    try {
      BlockRegistries.host.setBlockItem(
        BlazeBurnerBlock.emptyItemKey,
        BlazeBurnerBlock.key,
      );
    } on BlockRegistryException catch (e) {
      ctx.log.warn('Could not link the empty blaze burner item: ${e.message}');
    }
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    final wrench = runtime.services.find<WrenchRegistry>();
    wrench?.registerDefault(const [
      BlazeBurnerBlock.key,
      LitBlazeBurnerBlock.key,
    ]);

    // `BoilerHeaters.blazeBurner` of the fluids module reads a `heat_level` property; this fork's
    // burner stores its heat in `blaze` (the manifest property), so the boiler needs this rule.
    // `onServerLoaded` runs after every module's `onLoad`, so it wins over `registerDefaults`.
    BoilerHeaters.register(BlazeBurnerBlock.key, (level, pos, state) {
      final value = state[BlazeBurnerBlock.blazeProperty];
      if (value == null || value == 'none') return BoilerHeaters.noHeat;
      if (value == 'seething') return 2;
      if (value == 'fading' || value == 'kindled') return 1;
      return BoilerHeaters.passiveHeat;
    });
  }
}
