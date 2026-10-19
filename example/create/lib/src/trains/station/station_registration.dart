// Registration of the station area for the trains module: the `track_station` block and its block
// entity type, plus the wrench handler.
import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import 'station_block.dart';
import 'station_block_entity.dart';

bool _wrenchWired = false;

/// Phase 1: the block and its block entity type.
void registerStation(CreateRegistry registry) {
  registry.block(StationBlock().build());
  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: StationBlockEntity.type,
      validBlocks: [stationBlockKey],
      create: StationBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 2: the wrench.
void loadStation(CreateContext ctx) =>
    _wireWrench(ctx.services.find<WrenchRegistry>());

/// Phase 3: the wrench, if its registry came later.
void serverStationLoaded(CreateRuntime runtime) =>
    _wireWrench(runtime.services.find<WrenchRegistry>());

void _wireWrench(WrenchRegistry? wrench) {
  if (_wrenchWired || wrench == null) return;
  _wrenchWired = true;
  wrench.registerDefault(const [stationBlockKey]);
}

/// Plugin unload.
void unloadStation() {
  _wrenchWired = false;
  StationBlockEntity.assemblyAreas.clear();
}
