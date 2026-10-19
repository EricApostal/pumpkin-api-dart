// The conveyance side of `DepotApi`: the depot and ejector block entities expose their
// `DepotBehaviour` to the machines of the processing module through the service the depot part
// provides. It also carries the ejector operations of the payloads (`create:place_ejector`,
// `create:trigger_ejector`, `create:ejector_elytra`, `create:ejector_award`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/direction.dart';
import '../../../common/pos.dart';
import '../../../processing/depot/api.dart';
import '../../belt/transported_item.dart';
import '../../runtime.dart';
import '../transport_inventory_api.dart';
import 'depot_behaviour.dart';
import 'depot_block_entity.dart';
import 'ejector_block_entity.dart';

/// Registers the depot accessors of the two depot blocks.
void registerDepotApi(DepotApi api) {
  api.register('create:depot', (worldId, pos) => _DepotAccess(worldId, pos));
  api.register(
    'create:weighted_ejector',
    (worldId, pos) => _DepotAccess(worldId, pos),
  );
}

final class _DepotAccess implements DepotAccess {
  final String worldId;
  final Pos pos;

  _DepotAccess(this.worldId, this.pos);

  DepotBehaviour? get _behaviour {
    if (!ConveyanceRuntime.loaded) return null;
    final be = ConveyanceRuntime.i.beAt(worldId, pos);
    if (be is DepotBlockEntity) return be.depotBehaviour;
    if (be is EjectorBlockEntity) return be.depotBehaviour;
    return null;
  }

  EjectorBlockEntity? get _ejector {
    if (!ConveyanceRuntime.loaded) return null;
    final be = ConveyanceRuntime.i.beAt(worldId, pos);
    return be is EjectorBlockEntity ? be : null;
  }

  @override
  bool get isPresent => _behaviour != null;

  @override
  bool get isEjector => _ejector != null;

  @override
  DepotContents contents() {
    final behaviour = _behaviour;
    if (behaviour == null) return DepotContents.empty;
    return DepotContents(pStackOf(behaviour.getHeldItemStack()), [
      for (var slot = 0; slot < behaviour.processingOutputBuffer.slots; slot++)
        if (behaviour.processingOutputBuffer.getStack(slot).isNotEmpty)
          pStackOf(behaviour.processingOutputBuffer.getStack(slot)),
    ]);
  }

  @override
  PStack insert(PStack stack, {bool simulate = false}) {
    final behaviour = _behaviour;
    if (behaviour == null) return stack;
    return pStackOf(
      behaviour.insert(TransportedItemStack(itemValueOf(stack)), simulate),
    );
  }

  @override
  PStack extract(int amount, {bool simulate = false}) {
    final behaviour = _behaviour;
    if (behaviour == null || amount <= 0) return PStack.empty;

    var remaining = amount;
    var out = PStack.empty;
    final held = behaviour.heldItem;
    if (held != null && remaining > 0) {
      final (taken, rest) = held.stack.split(remaining);
      if (!simulate) {
        if (rest.isEmpty) {
          behaviour.heldItem = null;
        } else {
          held.stack = rest;
        }
        behaviour.owner.markDirty();
      }
      out = pStackOf(taken);
      remaining -= taken.count;
    }
    for (
      var slot = 0;
      slot < behaviour.processingOutputBuffer.slots && remaining > 0;
      slot++
    ) {
      final extracted = behaviour.processingOutputBuffer.extract(
        slot,
        remaining,
        simulate: simulate,
      );
      if (extracted.isEmpty) continue;
      out = out.isEmpty ? pStackOf(extracted) : out.grow(extracted.count);
      remaining -= extracted.count;
    }
    return out;
  }

  @override
  void setTarget(int horizontalDistance, int verticalDistance) =>
      _ejector?.setTarget(horizontalDistance, verticalDistance);

  @override
  void activate() => _ejector?.activate();

  @override
  void deployElytra(Player player) => _ejector?.deployElytra(player);

  @override
  void awardMaxed(Player player) => _ejector?.awardMaxed(player);

  @override
  void setFacing(int facing) {
    if (facing < 0 || facing >= Direction.values.length) return;
    final direction = Direction.values[facing];
    if (!direction.isHorizontal) return;
    final rt = ConveyanceRuntime.i;
    final state = rt.stateAt(worldId, pos);
    if (state.key != 'create:weighted_ejector') return;
    final next = state.setDir('facing', direction);
    if (next == state) return;
    rt.setStateLater(worldId, pos, next);
  }
}
