// `TrackObserverBlockEntity` (host): the block entity of the train observer. It powers the block while
// the observer edge point it is attached to is activated by a passing train.
import 'dart:async';

import '../../api/redstone.dart' show RedstoneDisplayApi;
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../../core/block_entity.dart';
import '../../redstone/observer/filter_behaviour.dart';
import '../graph/edge_point_type.dart';
import '../support/level.dart';
import '../support/runtime.dart';
import '../track/track_targeting_behaviour.dart';
import 'filter_item_stack.dart';
import 'track_observer.dart';

class TrackObserverBlockEntity extends CreateBlockEntity {
  static const String type = 'create:track_observer';

  late final TrackTargetingBehaviour<TrackObserver> edgePoint;
  late final FilterBehaviour filtering;

  TrackObserverBlockEntity(super.worldId, super.pos) {
    edgePoint = addBehaviour(
      TrackTargetingBehaviour<TrackObserver>(EdgePointType.OBSERVER),
    );
    filtering = addBehaviour(FilterBehaviour(callback: _onFilterChanged));
  }

  Pos get _pos => pos.toPos();

  void _onFilterChanged(String? newFilter) {
    final observer = getObserver();
    if (observer != null) {
      observer.setFilterAndNotify(worldId, FilterItemStack.ofItem(newFilter));
    }
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;

    var shouldBePowered = false;
    final observer = getObserver();
    if (observer != null) shouldBePowered = observer.isActivated();
    if (isBlockPowered() == shouldBePowered) return;

    final lvl = Lvl(w);
    final pos = _pos;
    final props = lvl.info(pos)?.properties;
    if (props != null && props.containsKey('powered')) {
      unawaited(
        lvl.setProps(pos, {'powered': '$shouldBePowered'}, neighbors: true),
      );
    }
    final api = Tr.i.service<RedstoneDisplayApi>();
    if (api != null) unawaited(api.notifyGatherers(w, this.pos));
  }

  /// `getObserver()`.
  TrackObserver? getObserver() => edgePoint.getEdgePoint();

  /// `getFilter()`: the filter item key.
  String? getFilter() => filtering.filter;

  /// `isBlockPowered()`.
  bool isBlockPowered() {
    final w = world;
    if (w == null) return false;
    return Lvl(w).info(_pos)?.properties['powered'] == 'true';
  }

  /// `clearContent()`.
  void clearContent() => filtering.setFilter(null);
}
