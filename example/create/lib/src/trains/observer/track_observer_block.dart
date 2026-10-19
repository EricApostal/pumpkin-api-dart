// `TrackObserverBlock` (host): the train observer block `create:track_observer`, a redstone source
// that is powered while a train passes its marker.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show manifestBlock;
import '../../api/wrenchable.dart';
import '../../core/blocks.dart';
import '../support/runtime.dart';
import 'track_observer_block_entity.dart';

const String observerBlockKey = 'create:track_observer';

/// The `create:track_observer` block.
final class TrackObserverBlock {
  late final CreateBlock block;

  TrackObserverBlock() {
    block = manifestBlock(
      'track_observer',
      blockEntityType: TrackObserverBlockEntity.type,
      behavior: BlockBehavior(
        // `getSignal`
        onWeakPower: (server, e) => block.stateOf(e.stateIndex)['powered'] == 'true' ? 15 : 0,
        // `shouldRedstoneWireConnectTo`
        canConnectRedstone: (server, e) => true,
        onUse: _onUse,
      ),
    );
  }

  /// The filter slot sits on the top of the block (`ValueBoxTransform` at `(0.5, 15.5/16, 0.5)`): a
  /// click on it with an item sets that item as the filter, an empty hand clears it.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.face != BlockDirection.up) return BlockUseResult.pass;
    final (cx, cy, cz) = e.cursor;
    final dx = cx - 0.5, dy = cy - 15.5 / 16, dz = cz - 0.5;
    if (dx * dx + dy * dy + dz * dz >= 0.2 * 0.2) return BlockUseResult.pass;
    final be = Tr.i.be<TrackObserverBlockEntity>(e.targetWorld, e.pos);
    if (be == null) return BlockUseResult.pass;
    if (e.withItem && await e.item.getRegistryKey() == 'create:wrench') return BlockUseResult.pass;
    await be.filtering.onShortInteract(e.player, e.hand);
    return BlockUseResult.success;
  }

  /// Registers the wrench handler of the block (`IWrenchable` defaults).
  static void registerWrench(WrenchRegistry wrench) => wrench.registerDefault(const [observerBlockKey]);
}
