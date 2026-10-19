// Registration of the signals for the trains module: the block `create:track_signal` and its block
// entity type, the wrench handler, and the edge point hook that tells a boundary whether the signal
// block entity reports redstone power.
import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import 'signal_block.dart';
import 'signal_block_entity.dart';
import 'track_edge_point.dart';

bool _wrenchWired = false;

/// Phase 1: the block and the block entity type.
void registerSignal(CreateRegistry registry) {
  registry.block(SignalBlock().block);
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: SignalBlockEntity.type,
      validBlocks: const [signalBlockKey],
      create: SignalBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 2: hooks and the wrench.
void loadSignal(CreateContext ctx) {
  final previous = EdgePointHooks.reportedPower;
  EdgePointHooks.reportedPower = (be) => be is SignalBlockEntity ? be.getReportedPower() : previous(be);
  _wireWrench(ctx.services.find<WrenchRegistry>());
}

/// Phase 3: the wrench, if its registry came later.
void serverSignalLoaded(CreateRuntime runtime) => _wireWrench(runtime.services.find<WrenchRegistry>());

void _wireWrench(WrenchRegistry? wrench) {
  if (_wrenchWired || wrench == null) return;
  _wrenchWired = true;
  SignalBlock.registerWrench(wrench);
}

/// Plugin unload.
void unloadSignal() {
  _wrenchWired = false;
}
