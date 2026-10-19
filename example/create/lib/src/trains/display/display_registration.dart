// Registration of the display board: block `display_board`, block entity type `flap_display`, the
// kinetic rules of the board, the wrench handler and the `FlapDisplayAccess` service the display
// link reads boards through (`DisplayBoardTarget`).
import '../../api/kinetics.dart' show KineticNetworkService;
import '../../api/redstone.dart' show FlapDisplayAccess;
import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import 'flap_display_block_entity.dart';
import 'flap_display_blocks.dart';

bool _kineticWired = false;
bool _wrenchWired = false;

/// Phase 1: the block and its block entity type.
void registerDisplay(CreateRegistry registry) {
  registry.block(buildFlapDisplayBlock());
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: FlapDisplayBlockEntity.type,
      validBlocks: const [displayBoardKey],
      create: FlapDisplayBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 2: provides [FlapDisplayAccess], registers the kinetic rules of the board and its wrench handler.
void loadDisplay(CreateContext ctx) {
  ctx.services.provide<FlapDisplayAccess>(FlapDisplayAccessImpl());
  _wire(ctx.services.find<KineticNetworkService>(), ctx.services.find<WrenchRegistry>());
}

/// Phase 3: wires what was not available in phase 2.
void serverDisplayLoaded(CreateRuntime runtime) {
  _wire(runtime.services.find<KineticNetworkService>(), runtime.services.find<WrenchRegistry>());
}

void _wire(KineticNetworkService? kinetics, WrenchRegistry? wrench) {
  if (!_kineticWired && kinetics != null) {
    _kineticWired = true;
    kinetics.registerKineticBlock(displayBoardKey, const FlapDisplayKineticDef());
  }
  if (!_wrenchWired && wrench != null) {
    _wrenchWired = true;
    wrench.registerDefault(const [displayBoardKey]);
  }
}

/// Plugin unload.
void unloadDisplay() {
  _kineticWired = false;
  _wrenchWired = false;
}
