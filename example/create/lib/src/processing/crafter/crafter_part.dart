// The mechanical crafter part of the processing module: the block and its block entity, the
// kinetic rules, the wrench (pointing rotation and connected inputs) and the vanilla crafting
// recipes the crafter may use.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../api/wrenchable.dart';
import '../../common/host_bridge.dart';
import '../../contraptions/core/nbt_map.dart';
import '../../contraptions/core/structure_transform.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../core/registry.dart';
import '../support/kinetics_bridge.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import 'crafter_block.dart';
import 'crafter_model.dart';
import 'machine_support.dart';
import 'mechanical_crafter_block_entity.dart';

/// The mechanical crafter.
final class CrafterPart extends ProcessingPart {
  @override
  String get name => 'crafter';

  @override
  void register(CreateRegistry registry) {
    final spec = crafterSpec();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:mechanical_crafter',
        validBlocks: [spec.block.key],
        create: MechanicalCrafterBlockEntity.new,
      ),
    );
    registry.block(spec.block);
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.find<KineticNetworkService>()?.registerKineticBlock(
      'create:mechanical_crafter',
      const CrafterKineticDef(),
    );

    // `MechanicalCrafterBlockEntity.transform`: the connected input offsets follow a contraption.
    MovedBlockTransformers
        .blockEntities['create:mechanical_crafter'] = (nbt, transform) {
      final input = nbt.getCompoundOrNull('ConnectedInput');
      if (input == null) return;
      for (final value in input.getList('Data')) {
        if (value.kind != NbtKind.compound) continue;
        final entry = NbtMap.of(value);
        final pos = (entry.getInt('X'), entry.getInt('Y'), entry.getInt('Z'));
        final moved = transform.applyPosWithoutOffset(pos);
        entry
          ..putInt('X', moved.$1)
          ..putInt('Y', moved.$2)
          ..putInt('Z', moved.$3);
      }
    };
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    try {
      sharedCraftingRecipes?.dispose();
    } on Object {
      // an earlier manager that is already gone
    }
    try {
      sharedCraftingRecipes = runtime.server.getRecipeManager().keep();
    } on Object catch (e) {
      rt.log.warn('The crafter cannot read the vanilla crafting recipes: $e');
      sharedCraftingRecipes = null;
    }

    runtime.services.find<WrenchRegistry>()?.register(
      'create:mechanical_crafter',
      CallbackWrenchable(onWrenchedOverride: _wrenched),
    );
  }

  @override
  void onUnload() {
    try {
      sharedCraftingRecipes?.dispose();
    } on Object {
      // already released
    }
    sharedCraftingRecipes = null;
    MovedBlockTransformers.blockEntities.remove('create:mechanical_crafter');
  }

  /// `MechanicalCrafterBlock.onWrenched`: clicking the front face cycles the pointing.
  static Future<WrenchResult> _wrenched(WrenchContext c) async {
    if (c.face.name != c.properties['facing']) return WrenchResult.pass;
    final current =
        crafterPointingByName(c.properties['pointing']) ?? CrafterPointing.up;
    final next = CrafterPointing
        .values[(current.index + 1) % CrafterPointing.values.length];
    final state = BlockStates.setValue(c.stateId, 'pointing', next.name);
    final switcher = c.registry.stateSwitcher;
    if (switcher != null) {
      await switcher(c.world, c.pos, state);
    } else {
      await c.world.setBlockState(
        pos: c.pos,
        state: state,
        updateFlags: BlockUpdateFlags.normal,
      );
    }
    return WrenchResult.success;
  }
}
