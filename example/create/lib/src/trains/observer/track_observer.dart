// `TrackObserver` (pure): an edge point that reports the passing of trains (optionally only those
// carrying something that passes the filter).
import '../graph/dimension_palette.dart';
import '../entity/train.dart';
import '../manager/create.dart';
import '../signal/signal_propagator.dart';
import '../signal/single_block_entity_edge_point.dart';
import '../signal/track_edge_point.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../util/ctag.dart';
import 'filter_item_stack.dart';

class TrackObserver extends SingleBlockEntityEdgePoint {
  int _activated = 0;
  FilterItemStack _filter = FilterItemStack.empty();
  String? _currentTrain;

  TrackObserver();

  @override
  void blockEntityAdded(Object blockEntity, bool front) {
    super.blockEntityAdded(blockEntity, front);
    final filteringBehaviour = EdgePointHooks.observerFilter(blockEntity);
    if (filteringBehaviour != null) setFilterAndNotify(null, filteringBehaviour);
  }

  @override
  void tick(TrackGraph graph, bool preTrains) {
    super.tick(graph, preTrains);
    if (isActivated()) _activated--;
    if (!isActivated()) _currentTrain = null;
  }

  /// `setFilterAndNotify(level, filter)`.
  void setFilterAndNotify(Object? level, FilterItemStack filter) {
    _filter = FilterItemStack.of(filter.serializeNBT());
    _notifyTrains(level);
  }

  void _notifyTrains(Object? level) {
    final graph = Create.RAILWAYS.sided(level).getGraph(level, edgeLocation.getFirst());
    if (graph == null) return;
    final edge = graph.getConnection(edgeLocation.map<TrackNode?>(graph.locateNode));
    if (edge == null) return;
    SignalPropagator.notifyTrains(graph, edge);
  }

  FilterItemStack getFilter() => _filter;

  String? getCurrentTrain() => _currentTrain;

  bool isActivated() => _activated > 0;

  void keepAlive(Train train) {
    _activated = 8;
    _currentTrain = train.id;
  }

  @override
  void read(CTag nbt, bool migration, DimensionPalette dimensions) {
    super.read(nbt, migration, dimensions);
    _activated = nbt.getInt('Activated');
    _filter = FilterItemStack.of(nbt.getCompound('Filter'));
    if (nbt.contains('TrainId')) {
      _currentTrain = nbt.getUuid('TrainId') ?? (throw const FormatException('bad TrainId'));
    }
  }

  @override
  void write(CTag nbt, DimensionPalette dimensions) {
    super.write(nbt, dimensions);
    nbt.putInt('Activated', _activated);
    nbt.putCompound('Filter', _filter.serializeNBT());
    final train = _currentTrain;
    if (train != null) nbt.putUuid('TrainId', train);
  }
}
