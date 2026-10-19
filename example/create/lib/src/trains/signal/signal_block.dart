// `SignalBlock` (host): the train signal block `create:track_signal`. The redstone input of the block
// (`powered`) is reported to its signal boundary by the block entity; the comparator reads whether the
// signal shows red.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show manifestBlock;
import '../../api/wrenchable.dart';
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import '../station/host_ops.dart' show sendOverlay;
import '../support/level.dart';
import '../support/runtime.dart';
import 'signal_block_entity.dart';
import 'signal_types.dart';

export 'signal_types.dart' show SignalType;

const String signalBlockKey = 'create:track_signal';

/// The `create:track_signal` block.
final class SignalBlock {
  late final CreateBlock block;

  SignalBlock() {
    block = manifestBlock(
      'track_signal',
      blockEntityType: SignalBlockEntity.type,
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _neighborChanged,
        onScheduledTick: _tick,
        onComparatorOutput: (server, e) => Tr.i.be<SignalBlockEntity>(e.targetWorld, e.pos)?.isPowered() == true ? 15 : 0,
      ),
    );
  }

  /// `getStateForPlacement`: `POWERED` is whether a neighbour signal reaches the block.
  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final powered = await lvl.hasNeighborSignal(pos);
    final props = block.stateOf(e.stateIndex);
    if ((props['powered'] == 'true') != powered) {
      await lvl.setProps(pos, {'powered': '$powered'});
    }
  }

  /// `neighborChanged`.
  Future<void> _neighborChanged(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final powered = block.stateOf(e.stateIndex)['powered'] == 'true';
    final neighborPowered = await lvl.hasNeighborSignal(pos);
    if (powered == neighborPowered) return;
    if (powered) {
      lvl.scheduleTick(pos, 4);
    } else {
      await lvl.setProps(pos, {'powered': 'true'});
    }
  }

  /// `tick`.
  Future<void> _tick(Server server, CustomBlockTickEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final powered = lvl.info(pos)?.properties['powered'] == 'true';
    if (powered && !await lvl.hasNeighborSignal(pos)) {
      await lvl.setProps(pos, {'powered': 'false'});
    }
  }

  /// `onWrenched`: cycles the signal type of the boundary.
  static Future<WrenchResult> onWrenched(WrenchContext c) async {
    final ste = Tr.i.be<SignalBlockEntity>(c.world, c.pos);
    if (ste == null) return WrenchResult.success;
    final signal = ste.getSignal();
    final pos = c.pos.toPos();
    if (signal != null) {
      signal.cycleSignalType(pos);
      sendOverlay(c.player, switch (signal.getTypeFor(pos)) {
        SignalType.ENTRY_SIGNAL => '-> Allow passage if section unoccupied',
        SignalType.CROSS_SIGNAL => '-> Allow passage if section fully traversable',
      });
    } else {
      sendOverlay(c.player, 'Unable to switch mode of this Signal');
    }
    return WrenchResult.success;
  }

  /// Registers the wrench handler of the block.
  static void registerWrench(WrenchRegistry wrench) {
    wrench.register(signalBlockKey, const CallbackWrenchable(onWrenchedOverride: onWrenched));
  }
}
