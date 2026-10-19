// The mechanical arm part of the processing module: the block and its block entity, the kinetic
// rules, the `create:place_arm` payload and the contraption transform of the interaction points.
// The `arm_interaction_point_type` synced registry is declared by the content module from the
// manifest (`kCustomRegistries`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../api/wrenchable.dart';
import '../../contraptions/core/nbt_map.dart';
import '../../contraptions/core/structure_transform.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'arm_block.dart';
import 'arm_block_entity.dart';
import 'arm_interaction_point.dart';

/// The mechanical arm.
final class ArmPart extends ProcessingPart {
  @override
  String get name => 'arm';

  @override
  void register(CreateRegistry registry) {
    final spec = armSpec();
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:mechanical_arm',
        validBlocks: [spec.block.key],
        create: ArmBlockEntity.new,
      ),
    );
    registry.block(spec.block);
  }

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.find<KineticNetworkService>()?.registerKineticBlock(
      'create:mechanical_arm',
      const ArmKineticDef(),
    );

    // `ArmBlockEntity.transform`: the saved points follow a contraption.
    MovedBlockTransformers.blockEntities['create:mechanical_arm'] =
        (nbt, transform) {
          for (final value in nbt.getList('InteractionPoints')) {
            if (value.kind != NbtKind.compound) continue;
            ArmInteractionPoint.transformPos(NbtMap.of(value), transform);
          }
        };

    // `ArmPlacementPacket.handle`: the client sends the points it selected.
    ctx.services.find<PayloadBus>()?.onServerbound('create:place_arm', (
      player,
      fields,
    ) {
      final pos = fields['pos'];
      if (pos is! (int, int, int)) return;
      final raw = fields['tag'];
      if (raw is! List) return;

      final tag = <NbtMap>[
        for (final value in raw)
          if (value is NbtValue && value.kind == NbtKind.compound)
            NbtMap.of(value),
      ];

      final world = player.getWorld();
      try {
        final worldId = ProcessingRuntime.instance.worlds.touch(world);
        ProcessingRuntime.instance.store
            .typed<ArmBlockEntity>(
              worldId,
              BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
            )
            ?.setInteractionPoints(tag);
      } finally {
        world.dispose();
      }
    });
  }

  @override
  void onServerLoaded(CreateRuntime runtime, ProcessingRuntime rt) {
    runtime.services.find<WrenchRegistry>()?.registerDefault([
      'create:mechanical_arm',
    ]);
  }

  @override
  void onUnload() {
    MovedBlockTransformers.blockEntities.remove('create:mechanical_arm');
  }
}
