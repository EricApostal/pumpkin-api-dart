// The minecart payload handlers and the controller update packet.
//
// Java: `content/contraptions/minecart/{CouplingCreationPacket,
// capability/MinecartControllerUpdatePacket}`.
import '../../api/payloads.dart';
import '../../core/nbt.dart';
import '../core/nbt_map.dart';
import '../blocks/actuator_runtime.dart';
import 'capability/minecart_controller.dart';
import 'coupling_handler.dart';
import 'minecart_access.dart';

/// Binds `create:minecart_coupling_creation` to the payload bus.
void bindMinecartPackets(PayloadBus bus) {
  bus.onServerbound('create:minecart_coupling_creation', (player, fields) {
    final id1 = fields['id1'] as int;
    final id2 = fields['id2'] as int;
    final world = player.getWorld();
    final level = HostMinecartWorld(world, ActuatorRuntime.instance.store);
    tryToCoupleCarts(player, level, id1, id2);
  });
}

/// The field map of `MinecartControllerUpdatePacket` for a controller.
Map<String, Object?> minecartControllerUpdateFields(
  MinecartController controller,
  int entityId,
) {
  final nbt = controller.serializeNbt();
  return {'entityId': entityId, 'nbt': nbt.isEmpty ? null : nbt.toValue()};
}

/// The controller a client sent back (the packet is clientbound in Java; kept for tests and for a
/// future two-way sync).
MinecartController readMinecartControllerUpdate(
  NbtValue? nbt,
  String cartUuid,
) {
  final controller = MinecartController.empty();
  if (nbt != null && nbt.kind == NbtKind.compound) {
    controller.deserializeNbt(NbtMap.of(nbt));
  }
  return controller;
}
