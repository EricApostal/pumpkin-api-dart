// Registration of the bogeys: blocks `small_bogey` / `large_bogey`, the block entity type `bogey`,
// the wrench handler and the schematic requirement (a railway casing).
import '../../api/block_state.dart';
import '../../api/schematics.dart';
import '../../api/wrenchable.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import 'bogey_blocks.dart';
import 'abstract_bogey_block_entity.dart';

bool _wired = false;

/// Phase 1: the two bogey blocks and the `create:bogey` block entity type.
void registerBogey(CreateRegistry registry) {
  registerBogeyLogic();
  registry.block(buildBogeyBlock('small_bogey'));
  registry.block(buildBogeyBlock('large_bogey'));
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: bogeyBlockEntityType,
      validBlocks: const [smallBogeyKey, largeBogeyKey],
      create: StandardBogeyBlockEntity.new,
      // the bogey block entity never ticks
      tickInterval: 0,
    ),
  );
}

/// Phase 2: wrench rotation (the bogey cycle) and the schematic item requirement.
void loadBogey(CreateContext ctx) {
  _wire(ctx.services.find<WrenchRegistry>(), ctx.services.find<SchematicHooks>());
}

/// Phase 3: wires what the services that were not there in phase 2 offer.
void serverBogeyLoaded(CreateRuntime runtime) {
  _wire(runtime.services.find<WrenchRegistry>(), runtime.services.find<SchematicHooks>());
}

void _wire(WrenchRegistry? wrench, SchematicHooks? schematics) {
  if (_wired || wrench == null) return;
  _wired = true;
  wrench.registerAll(const [smallBogeyKey, largeBogeyKey], bogeyWrenchable());
  schematics?.requirements.blocks[smallBogeyKey] = _casing;
  schematics?.requirements.blocks[largeBogeyKey] = _casing;
}

// `getRequiredItems`: a railway casing, consumed.
ItemRequirement _casing(BState state, List<int>? nbt) => ItemRequirement.of1(ItemUseType.consume, railwayCasingKey);

/// Plugin unload.
void unloadBogey() {
  _wired = false;
}
