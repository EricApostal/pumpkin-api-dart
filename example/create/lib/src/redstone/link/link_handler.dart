// `LinkHandler`: right clicking a block that has a `LinkBehaviour` (redstone links, stock
// links, ...) on one of its two frequency slots with an item sets that item as the frequency.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../support/rs_runtime.dart';
import 'frequency_stacks.dart';
import 'link_behaviour.dart';

abstract final class LinkHandler {
  static void install(RsRuntime rs) {
    rs.ctx.host.intercept(Events.playerUseBlock, (server, e) async {
      if (e.cancelled) return e;
      final player = e.player;
      if (e.sneaking || player.getGamemode() == GameMode.spectator) return e;

      final world = player.getWorld();
      final be = rs.store.at(rs.worldId(world), e.blockPos);
      final behaviour = be?.getBehaviour<LinkBehaviour>();
      if (behaviour == null) return e;

      final heldKey = await e.item.getRegistryKey();
      if (heldKey == 'create:linked_controller' || heldKey == 'create:wrench') return e;

      var consumed = false;
      for (final first in const [false, true]) {
        if (!behaviour.slotTest(first, e.cursor)) continue;
        behaviour.setFrequency(first, await frequencyOfStack(e.item));
        consumed = true;
        world.playSound(
          sound: Sound.entityItemFrameAddItem,
          category: SoundCategory.blocks,
          pos: e.blockPos.toPos().center,
          volume: 0.25,
          pitch: 0.1,
        );
      }
      return consumed ? e.cancel() : e;
    });
  }
}
