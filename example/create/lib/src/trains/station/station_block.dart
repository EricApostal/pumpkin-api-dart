// `StationBlock` (host): the block of a train station. The block only decides the comparator
// output and the right clicks; the station state lives in [StationBlockEntity].
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../conveyance/belt/transported_item.dart';
import '../../conveyance/items/item_codec.dart';
import '../../core/blocks.dart';
import '../support/runtime.dart';
import 'station_block_entity.dart';

/// `create:track_station`.
const String stationBlockKey = 'create:track_station';

/// `StationBlock.ASSEMBLING`.
const String stationAssemblingProperty = 'assembling';

/// `AllShapes.STATION`: a 16x2 plate with the marker post on it.
final BlockShape stationShape = BlockShape.boxes([
  BlockBox(0, 0, 0, 1, 2 / 16, 1),
  BlockBox(1 / 16, 0, 1 / 16, 15 / 16, 13 / 16, 15 / 16),
]);

final class StationBlock {
  CreateBlock build() => manifestBlock(
    'track_station',
    blockEntityType: StationBlockEntity.type,
    placement: const [PlacementRule.inWater('waterlogged')],
    collisionShape: stationShape,
    selectionShape: stationShape,
    behavior: BlockBehavior(
      // `hasAnalogOutputSignal` + `getAnalogOutputSignal`: a train at the station powers it.
      onComparatorOutput: (server, e) {
        final be = Tr.loaded
            ? Tr.i.store.typed<StationBlockEntity>(e.targetWorld.getId(), e.pos)
            : null;
        return be != null && be.trainPresent ? 15 : 0;
      },
      // `isPathfindable`: the station is not a walkable path node.
      isPathfindable: (server, e) => false,
      // `StationBlock.fallOn` (`:97-99`): an item that fell onto the station is handed to the
      // station's depot slot, like the depot family.
      onLandedUpon: _landedUpon,
      onUse: _use,
    ),
  );

  /// `StationBlock.fallOn` (`:97-99`) through `SharedDepotBlockMethods.onLanded`: a package item
  /// that fell onto the station enters the station's depot slot; the slot only accepts schedules,
  /// so anything else stays on the item. `super.fallOn` (the stock fall-damage path) is dead code
  /// here: the vanilla base of every Create block ignores a landed entity, and the host only runs
  /// this hook for custom blocks anyway.
  Future<double> _landedUpon(
    Server server,
    CustomBlockLandedEventData e,
  ) async {
    final world = e.targetWorld;
    final item = world.getEntityById(id: e.entityId)?.asItem();
    if (item == null) return 1.0;
    final be = Tr.loaded ? Tr.i.store.typed<StationBlockEntity>(world.getId(), e.pos) : null;
    final depot = be?.depot;
    if (depot == null) return 1.0;
    final transported = TransportedItemStack(await ItemCodec.read(item.getStack()));
    if (transported.stack.isEmpty) return 1.0;
    final before = transported.stack.count;
    if (depot.acceptLandedPackage(transported)) {
      item.discard();
    } else if (transported.stack.count != before) {
      final host = await ItemCodec.write(transported.stack);
      if (host != null) await item.setStack(stack: host);
    }
    return 1.0;
  }

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

    // `stack.getItem() == Items.FILLED_MAP` (`:120-133`): Java toggles the station's marker on the
    // map and answers SUCCESS, FAIL when the station has no id or the toggle did not happen. The
    // host exposes no map saved data at all — no way to read the item's `minecraft:map_id`, no way
    // to reach `MapData` (`centerX`/`centerZ`/`scale`/`decorations`) or the map's saved
    // `create:stations` list — so the toggle cannot be evaluated and Java's FAIL is the honest
    // answer where Java would sometimes SUCCEED. `StationMapMarkers` (`station_map_data.dart`)
    // holds all the toggle/add/refresh rules, ready for the day the host has them; the named
    // primitives are in `docs/host-gaps.md` ("Map saved data").
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
