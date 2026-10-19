// `DeployerMovingInteraction`: a player clicking a deployer on a contraption swaps the item in
// their hand with the item in the deployer's hand; a wrench changes the mode.
//
// Ported from `content/kinetics/deployer/DeployerMovingInteraction.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../../contraptions/core/contraption.dart';
import '../../contraptions/core/movement.dart';
import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'deployer_actor_player.dart';
import 'deployer_types.dart';

/// The moving interaction of the deployer.
class DeployerMovingInteraction extends MovingInteractionBehaviour {
  const DeployerMovingInteraction();

  @override
  Future<bool> handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) async {
    final context = contraption.getActorAt(localPos);
    if (context == null) return false;

    if (player.holdsWrench) {
      final data = context.blockEntityData;
      if (data == null) return false;
      final mode = DeployerMode.fromJavaName(data.getString('Mode'));
      data.putString(
        'Mode',
        (mode == DeployerMode.punch ? DeployerMode.use : DeployerMode.punch)
            .javaName,
      );
      return true;
    }

    final host = player.hostPlayer;
    if (host is! Player) return false;

    final world = ProcessingRuntime.instance.worlds.byId(context.worldId);
    if (world == null) return false;
    final fake = actorPlayer(context, world);
    if (fake == null) return false;

    final deployerItem = await readActorHand(fake);
    final playerItem = await _readHand(host);
    await _setHand(host, deployerItem);
    await setActorHand(fake, playerItem);
    context.blockEntityData?.putCompound('HeldItem', actorStackNbt(playerItem));
    context.data.putCompound('HeldItem', actorStackNbt(playerItem));
    return true;
  }

  Future<PStack> _readHand(Player player) async {
    final item = player.getItemInHand(hand: Hand.right);
    if (item == null) return PStack.empty;
    final stack = await HostStacks.read(item);
    item.dispose();
    return stack;
  }

  Future<void> _setHand(Player player, PStack stack) async {
    final item = await HostStacks.write(stack);
    await player.setItemInHand(hand: Hand.right, stack: item);
  }
}
