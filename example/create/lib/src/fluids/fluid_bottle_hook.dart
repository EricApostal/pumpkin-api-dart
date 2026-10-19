// `FluidBottleItemHook`: a glass bottle used on a Create fluid block must not
// fill with water (Create's fluids are in the water tag). Vanilla's bottle item
// runs before the block, so the interaction is cancelled here.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';

abstract final class FluidBottleItemHook {
  /// The blocks whose fluid a glass bottle would wrongly pick up.
  static const Set<String> fluidBlocks = {'create:honey', 'create:chocolate'};

  /// Installs the hook (`PlayerInteractEvent.RightClickItem`).
  static void install(CreateContext ctx) {
    ctx.host.intercept(Events.playerUseBlock, (server, e) async {
      if (e.cancelled) return e;
      if (!fluidBlocks.contains(e.block)) return e;
      final String item;
      try {
        item = await e.item.getRegistryKey();
      } on Object {
        return e;
      }
      if (item != 'minecraft:glass_bottle') return e;
      return e.cancel();
    });
  }
}
