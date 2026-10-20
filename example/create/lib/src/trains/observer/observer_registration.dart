// Registration of the observers for the trains module: the block `create:track_observer` and its
// block entity type, the wrench handler, and the filter hooks of the observer edge point.
import '../../api/filter_api.dart' show FilterItemValue, ItemFilterApi;
import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../graph/dimension_palette.dart' show overworldId;
import '../signal/track_edge_point.dart';
import '../support/runtime.dart';
import 'filter_item_stack.dart';
import 'track_observer_block.dart';
import 'track_observer_block_entity.dart';

bool _wrenchWired = false;

/// Phase 1: the block and the block entity type.
void registerObserver(CreateRegistry registry) {
  registry.block(TrackObserverBlock().block);
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: TrackObserverBlockEntity.type,
      validBlocks: const [observerBlockKey],
      create: TrackObserverBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 2: the filter hooks and the wrench.
void loadObserver(CreateContext ctx) {
  final previous = EdgePointHooks.observerFilter;
  EdgePointHooks.observerFilter = (be) =>
      be is TrackObserverBlockEntity ? FilterItemStack.ofItem(be.filtering.filter) : previous(be);

  // list and attribute filters are the logistics module's: ask its filter service when it is there
  FilterItemStack.itemMatcher = (filterItem, candidate) {
    final api = Tr.loaded ? Tr.i.service<ItemFilterApi>() : null;
    return api != null
        ? api.testItem(overworldId, FilterItemValue.key(filterItem), candidate)
        : filterItem == candidate;
  };
  FilterItemStack.fluidMatcher = (filterItem, fluid) {
    final api = Tr.loaded ? Tr.i.service<ItemFilterApi>() : null;
    if (api != null) {
      return api.testFluid(
        overworldId,
        FilterItemValue.key(filterItem),
        fluid,
      );
    }
    return filterItem.endsWith('_bucket') && filterItem.substring(0, filterItem.length - '_bucket'.length) == fluid;
  };
  _wireWrench(ctx.services.find<WrenchRegistry>());
}

/// Phase 3: the wrench, if its registry came later.
void serverObserverLoaded(CreateRuntime runtime) => _wireWrench(runtime.services.find<WrenchRegistry>());

void _wireWrench(WrenchRegistry? wrench) {
  if (_wrenchWired || wrench == null) return;
  _wrenchWired = true;
  TrackObserverBlock.registerWrench(wrench);
}

/// Plugin unload.
void unloadObserver() {
  _wrenchWired = false;
  FilterItemStack.itemMatcher = (filterItem, candidate) => filterItem == candidate;
}
