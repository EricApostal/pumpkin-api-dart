// `MountedDepotInteractionBehaviour`: a player clicking a depot on a contraption swaps the item
// in their hand with the item on the depot. Ported from
// `content/logistics/depot/MountedDepotInteractionBehaviour.java`.
//
// The Dart `MovingInteractionBehaviour` does not report which hand was used; the interaction
// always acts on the main hand (Java ignores the off hand).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart' hide pos;
import '../../contraptions/core/contraption.dart';
import '../../contraptions/core/movement.dart';
import '../../contraptions/storage/mounted_storage.dart';
import '../../contraptions/storage/stacks.dart';
import '../host/stack_host.dart';

/// The depot's moving interaction.
class MountedDepotInteractionBehaviour extends MovingInteractionBehaviour {
  const MountedDepotInteractionBehaviour();

  @override
  Future<bool> handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) async {
    final hostPlayer = player.hostPlayer;
    if (hostPlayer is! Player) return false;

    final storage = contraption.storage.allItemStorages[localPos];
    if (storage is! DepotMountedStorage) return false;

    final itemOnDepot = storage.item;
    final held = hostPlayer.getItemInHand(hand: Hand.right);
    final itemInHand = await HostStacks.read(held);
    if (itemOnDepot.isEmpty && itemInHand.isEmpty) return true;

    storage.item = itemInHand.isEmpty
        ? StoredStack.empty
        : StoredStack(itemInHand.key, itemInHand.count);

    final result = itemOnDepot.isEmpty
        ? null
        : ItemStack.create(
            registryKey: itemOnDepot.item,
            count: itemOnDepot.count,
          );
    await hostPlayer.setItemInHand(hand: Hand.right, stack: result);

    player.playSound('create:depot_plop', 1, volume: 1);
    return true;
  }
}
