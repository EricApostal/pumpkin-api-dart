// The curved track packets:
//  * `create:destroy_curved_track` (CurvedTrackDestroyPacket): removes a curve from both ends,
//    drops its items and plays the break feedback;
//  * `create:select_curved_track` (CurvedTrackSelectionPacket): stores the clicked curve segment
//    in the held targeting item, after the overlap check;
//  * `create:place_curved_track` (PlaceExtendedCurvePacket): marks the held track item as an
//    extended curve placement.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../api/sounds.dart' show CreateSounds;
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../core/module.dart';
import '../entity/train_level.dart' show TrainSettings;
import '../graph/edge_point_type.dart';
import '../station/host_ops.dart' show sendOverlay, trainsLang;
import '../support/runtime.dart';
import 'bezier_track_point_location.dart';
import 'i_track_block.dart';
import 'track_host.dart';
import 'track_level.dart' show trackExtendedCurveComponent;
import 'track_propagator.dart';
import 'track_targeting_block_item.dart';

/// Installs the three handlers on the payload bus.
void installCurvedTrackPackets(CreateContext ctx) {
  final bus = ctx.services.find<PayloadBus>();
  bus?.onServerbound('create:destroy_curved_track', _onDestroy);
  bus?.onServerbound('create:select_curved_track', _onSelect);
  bus?.onServerbound('create:place_curved_track', _onPlace);
}

// -- destroy -------------------------------------------------------------------------------------

Future<void> _onDestroy(Player player, Map<String, Object?> fields) async {
  final pos = fields['pos'];
  final targetPos = fields['targetPos'];
  final soundSource = fields['soundSource'];
  if (pos is! Pos || targetPos is! Pos || soundSource is! Pos) return;

  final world = player.getWorld();
  final be = Tr.i.store
      .typed<TrackBlockEntityHost>(world.getId(), pos.toBlockPos())
      ?.track;
  if (be == null) return;

  final verifyDistance = TrainSettings.current.maxTrackPlacementLength * 4;
  final (px, py, pz) = player.getPosition();
  final dx = px - pos.center.$1,
      dy = py - pos.center.$2,
      dz = pz - pos.center.$3;
  if (dx * dx + dy * dy + dz * dz > verifyDistance * verifyDistance) {
    Tr.i.log.warn('A player was too far away from a destroyed curve track');
    return;
  }

  final level = HostTrackLevel(world, Tr.i.store);
  final bezier = be.getConnections()[targetPos];

  await be.removeConnection(targetPos);
  final other = Tr.i.store
      .typed<TrackBlockEntityHost>(world.getId(), targetPos.toBlockPos())
      ?.track;
  await other?.removeConnection(pos);

  TrackPropagator.onRailRemoved(level, pos, be.getBlockState());

  final wrench = fields['wrench'] == true;
  if (wrench) {
    Tr.i.service<CreateSounds>()?.playAtBlock(
      world,
      soundSource,
      'wrench_remove',
      volume: 1,
      pitch: level.random.nextDouble() * 0.5 + 0.5,
    );
    if (!_isCreative(player) && bezier != null) {
      bezier.addItemsToPlayer(HostTrackPlacementPlayer(player));
    }
  } else if (!_isCreative(player) && bezier != null) {
    bezier.spawnItems(level);
  }

  bezier?.spawnDestroyParticles(level);
  world.playCustomSound(
    soundName: 'minecraft:block.metal.break',
    category: SoundCategory.blocks,
    pos: soundSource.center,
    volume: 1,
    pitch: 1,
  );
}

bool _isCreative(Player player) => player.getGamemode() == GameMode.creative;

// -- select --------------------------------------------------------------------------------------

Future<void> _onSelect(Player player, Map<String, Object?> fields) async {
  final pos = fields['pos'];
  final targetPos = fields['targetPos'];
  final front = fields['front'] == true;
  final segment = fields['segment'];
  final slot = fields['slot'];
  if (pos is! Pos || targetPos is! Pos || segment is! int || slot is! int)
    return;

  final inventory = player.getInventory();
  if (inventory.getSelectedSlot() != slot) return;
  final storage = inventory.asInventory();
  final stack = storage.getItem(slot: slot);
  if (stack == null) return;

  final itemKey = await stack.getRegistryKey();
  if (targetingTypeOf(itemKey) == null) return;
  // Java: `AllBlocks.TRACK_SIGNAL.isIn(stack) ? SIGNAL : STATION`.
  final type = itemKey == 'create:track_signal'
      ? EdgePointType.SIGNAL
      : EdgePointType.STATION;

  if (player.asEntity().isSneaking() && hasTargetSelection(stack)) {
    sendOverlay(player, trainsLang('create.track_target.clear'));
    TrackTargetingComponents.clearAll(stack);
    await storage.setItem(slot: slot, item: stack);
    Tr.i.service<CreateSounds>()?.playAtBlock(
      player.getWorld(),
      pos,
      'controller_click',
      volume: 1,
      pitch: 0.5,
    );
    return;
  }

  final level = HostTrackLevel(player.getWorld(), Tr.i.store);
  final bezier = BezierTrackPointLocation(targetPos, segment);
  OverlapResult result = OverlapResult.valid;
  withGraphLocation(
    level,
    pos,
    front,
    bezier,
    type,
    (r, location) => result = r,
  );

  final feedback = result.feedback;
  if (feedback != null) {
    sendOverlay(player, trainsLang('create.$feedback'), color: 'c');
    Tr.i.service<CreateSounds>()?.playAtBlock(
      player.getWorld(),
      pos,
      'deny',
      volume: 0.5,
      pitch: 1,
    );
    return;
  }

  TrackTargetingComponents.writeSelectedPos(stack, pos);
  TrackTargetingComponents.writeSelectedDirection(stack, front);
  TrackTargetingComponents.writeBezier(stack, bezier);
  await storage.setItem(slot: slot, item: stack);

  sendOverlay(player, trainsLang('create.track_target.set'));
  Tr.i.service<CreateSounds>()?.playAtBlock(
    player.getWorld(),
    pos,
    'controller_click',
    volume: 1,
    pitch: 1,
  );
}

// -- place extended curve ------------------------------------------------------------------------

Future<void> _onPlace(Player player, Map<String, Object?> fields) async {
  final mainHand = fields['mainHand'] == true;
  final hand = mainHand ? Hand.right : Hand.left;
  final stack = player.getItemInHand(hand: hand);
  if (stack == null) return;

  final itemKey = await stack.getRegistryKey();
  if (TrackBlockRegistry.of(itemKey) == null) return;

  stack.setCustomComponent(
    trackExtendedCurveComponent,
    PacketBuffer.encode((w) => w.writeBool(true)),
  );
  await player.setItemInHand(hand: hand, stack: stack);
}
