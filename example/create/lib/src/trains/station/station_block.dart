// `StationBlock` (host): the block of a train station. The block only decides the comparator
// output and the right clicks; the station state lives in [StationBlockEntity].
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../core/blocks.dart';
import '../support/runtime.dart';
import 'station_block_entity.dart';

/// `create:track_station`.
const String stationBlockKey = 'create:track_station';

/// `StationBlock.ASSEMBLING`.
const String stationAssemblingProperty = 'assembling';

final class StationBlock {
  CreateBlock build() => manifestBlock(
    'track_station',
    blockEntityType: StationBlockEntity.type,
    placement: const [PlacementRule.inWater('waterlogged')],
    behavior: BlockBehavior(
      // `hasAnalogOutputSignal` + `getAnalogOutputSignal`: a train at the station powers it.
      onComparatorOutput: (server, e) {
        final be = Tr.loaded
            ? Tr.i.store.typed<StationBlockEntity>(e.targetWorld.getId(), e.pos)
            : null;
        return be != null && be.trainPresent ? 15 : 0;
      },
      onUse: _use,
    ),
  );

  /// `useItemOn`: a wrench or a sneak click falls through to the item; a schedule on the station's
  /// slot is handed to the player; everything else opens the station screen on the client.
  Future<BlockUseResult> _use(Server server, CustomBlockUseEventData e) async {
    if (e.sneaking) return BlockUseResult.tryEmptyHand;
    final be = Tr.loaded
        ? Tr.i.store.typed<StationBlockEntity>(e.targetWorld.getId(), e.pos)
        : null;
    if (be == null) return BlockUseResult.pass;

    final heldKey = e.withItem ? await e.item.getRegistryKey() : null;
    if (heldKey == 'create:wrench') return BlockUseResult.tryEmptyHand;

    // `stack.getItem() == Items.FILLED_MAP`: the station marker is toggled on the map. The host
    // does not expose the saved data of a map item, so the marker cannot be toggled here.
    if (heldKey == 'minecraft:filled_map') return BlockUseResult.fail;

    final autoSchedule = be.getAutoSchedule();
    if (autoSchedule != null) {
      await e.player.give(autoSchedule);
      be.depot?.removeHeldItem();
      be.sendData();
      return BlockUseResult.success;
    }

    // The station screen is client side; the server only reports the successful interaction.
    return BlockUseResult.success;
  }
}
