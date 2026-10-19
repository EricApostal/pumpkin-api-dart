// The `schematics` module: schematic table, schematicannon, the schematic items, the upload
// receiver and the schematic API hooks.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/payloads.dart';
import '../common/common.dart';
import '../common/host_bridge.dart';
import '../contraptions/core/movement_checks.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../core/block_entity.dart';
import '../infrastructure/config/create_configs.dart';
import '../manifest/manifest.dart';
import 'host/schematics_host.dart';
import 'host/template_loader.dart';
import 'schematic_hooks.dart';
import 'schematic_printer.dart';
import 'schematic_state_filters.dart';
import 'item_requirement.dart';
import 'upload_receiver.dart';

BlockBox _box16(
  double x1,
  double y1,
  double z1,
  double x2,
  double y2,
  double z2,
) => BlockBox(x1 / 16, y1 / 16, z1 / 16, x2 / 16, y2 / 16, z2 / 16);

/// Rotates a box clockwise around Y by [turns] quarter turns.
BlockBox _rotateBox(BlockBox b, int turns) {
  var minX = b.minX, minZ = b.minZ, maxX = b.maxX, maxZ = b.maxZ;
  for (var i = 0; i < turns % 4; i++) {
    // (x, z) -> (1 - z, x)
    final nMinX = 1 - maxZ, nMaxX = 1 - minZ, nMinZ = minX, nMaxZ = maxX;
    minX = nMinX;
    maxX = nMaxX;
    minZ = nMinZ;
    maxZ = nMaxZ;
  }
  return BlockBox(minX, b.minY, minZ, maxX, b.maxY, maxZ);
}

/// `AllShapes.SCHEMATICS_TABLE.get(facing)`: built for south, turned for the other directions.
BlockShape _tableSelection(Direction facing) {
  final turns = switch (facing) {
    Direction.south => 0,
    Direction.west => 1,
    Direction.north => 2,
    _ => 3,
  };
  return BlockShape.boxes([
    for (final b in [_box16(4, 0, 4, 12, 12, 12), _box16(0, 11, 2, 16, 14, 14)])
      _rotateBox(b, turns),
  ]);
}

final BlockShape _tablePole = BlockShape.boxes([
  _box16(4, 0, 4, 12, 2, 12),
  _box16(5, 2, 5, 11, 14, 11),
]);
final BlockShape _cannonShape = BlockShape.boxes([
  _box16(1, 0, 1, 15, 8, 15),
  _box16(0.5, 8, 0.5, 15.5, 11, 15.5),
]);

/// Schematics: provides [SchematicHooks] (and so `SchematicRequirements`) and [SchematicUploadReceiver].
final class SchematicsModule extends CreateModule {
  @override
  String get name => 'schematics';

  @override
  void register(CreateRegistry registry) {
    registry.item(
      const ItemRegistration(key: 'create:empty_schematic', maxStackSize: 1),
    );
    registry.item(
      const ItemRegistration(
        key: 'create:schematic_and_quill',
        maxStackSize: 1,
      ),
    );
    registry.item(
      const ItemRegistration(key: 'create:schematic', maxStackSize: 1),
    );

    registry.block(
      manifestBlock(
        'schematic_table',
        collisionShape: _tablePole,
        selectionShape: _tableSelection(Direction.south),
        shapeRules: [
          for (final d in Direction.horizontals)
            ShapeRule(
              when: {'facing': d.serializedName},
              collisionShape: _tablePole,
              selectionShape: _tableSelection(d),
            ),
        ],
        placement: const [
          PlacementRule.horizontalFacing('facing', opposite: true),
        ],
        blockEntityType: tableBlockEntityType,
        behavior: BlockBehavior(
          // `SchematicTableBlock.isPathfindable` returns false.
          isPathfindable: (server, e) => false,
          onUse: (server, e) async {
            final rt = SchematicsRuntime.instance;
            final be = rt.entityAt<SchematicTableBlockEntity>(
              e.targetWorld.getId(),
              e.pos.toPos(),
            );
            if (be == null) return BlockUseResult.pass;
            await openTableMenu(rt, e.player, be);
            return BlockUseResult.success;
          },
        ),
      ),
    );
    registry.block(
      manifestBlock(
        'schematicannon',
        collisionShape: _cannonShape,
        selectionShape: _cannonShape,
        blockEntityType: cannonBlockEntityType,
        behavior: BlockBehavior(
          onPlaced: (server, e) {
            final rt = SchematicsRuntime.instance;
            final be = rt.entityAt<SchematicannonBlockEntity>(
              e.targetWorld.getId(),
              e.pos.toPos(),
            );
            final id = e.player;
            final player = id == null ? null : server.getPlayerByUuid(id: id);
            if (be != null && player != null) {
              // (-floor((yaw + (sneaking ? 180 : 0)) * 16 / 360 + 0.5) & 15) * 360 / 16
              final yaw =
                  player.getYaw() +
                  (player.asEntity().isSneaking() ? 180.0 : 0.0);
              be.core.defaultYaw =
                  ((-((yaw * 16.0 / 360.0 + 0.5).floor()) & 15) * 360.0 / 16.0);
              be.sendData();
            }
          },
          onNeighborUpdate: (server, e) {
            SchematicsRuntime.instance
                .entityAt<SchematicannonBlockEntity>(
                  e.targetWorld.getId(),
                  e.pos.toPos(),
                )
                ?.neighbourChanged();
          },
          onUse: (server, e) async {
            final rt = SchematicsRuntime.instance;
            final be = rt.entityAt<SchematicannonBlockEntity>(
              e.targetWorld.getId(),
              e.pos.toPos(),
            );
            if (be == null) return BlockUseResult.pass;
            await openCannonMenu(rt, e.player, be);
            return BlockUseResult.success;
          },
        ),
      ),
    );
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: tableBlockEntityType,
        validBlocks: ['create:schematic_table'],
        create: SchematicTableBlockEntity.new,
      ),
    );
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: cannonBlockEntityType,
        validBlocks: ['create:schematicannon'],
        create: SchematicannonBlockEntity.new,
      ),
    );
    // `AllStructureProcessorTypes.SCHEMATIC`: `create:schematic` runs the safe-NBT processors
    // when a structure template with this processor is placed. The host does not number this
    // registry itself, so it is declared with the NeoForge registry additions.
    registry.neoForgeRegistry('minecraft:structure_processor', [
      'create:schematic',
    ]);
  }

  @override
  void onLoad(CreateContext ctx) {
    final hooks = SchematicHooks();
    // `BlockMovementChecks.isBrittle`: the printer defers brittle blocks so they do not lose
    // their support while printing.
    hooks.isBrittle = (state) => BlockMovementChecks.isBrittle(state);
    // `AllSchematicStateFilters.registerDefaults`.
    hooks.stateFilters['minecraft:chiseled_bookshelf'] =
        chiseledBookshelfFilter;
    // Block -> block entity type, from the manifest (every block of a type lists its valid blocks).
    final typeOf = <String, String>{};
    for (final t in kBlockEntityTypes) {
      for (final b in t.validBlocks) {
        typeOf.putIfAbsent('create:$b', () => 'create:${t.key}');
      }
    }
    hooks.blockEntityTypeOf = (k) => typeOf[k];
    hooks.requirements.blockEntityTypeOf = hooks.blockEntityTypeOf;
    hooks.requirements.itemOfBlock = _itemOfBlock;
    hooks.requirements.blocks['create:belt'] = (state, nbt) {
      final required = <StackRequirement>[];
      final part = state['part'];
      if (part != 'middle')
        required.add(
          const StackRequirement('create:shaft', 1, ItemUseType.consume),
        );
      if (part == 'start')
        required.add(
          const StackRequirement(
            'create:belt_connector',
            1,
            ItemUseType.consume,
          ),
        );
      return required.isEmpty
          ? ItemRequirement.none
          : ItemRequirement(required);
    };
    SchematicPrinter.entityTypeResolver = (nbt) {
      try {
        final parsed = BinaryNbt.read(nbt);
        if (parsed == null || parsed.root.kind != NbtKind.compound) return null;
        final id = parsed.root.asCompound['id'];
        return id != null && id.value is String ? id.value as String : null;
      } on Object {
        // A malformed entity tag has no requirement; the cannon skips it.
        return null;
      }
    };

    final configs = ctx.services.find<CreateConfigs>();
    final store = DataFolderSchematicStore(ctx.host.files);
    final limits = configs == null
        ? const SchematicLimits()
        : SchematicLimits(
            maxSchematics: configs.server.schematics.maxSchematics.value,
            maxTotalSchematicSize:
                configs.server.schematics.maxTotalSchematicSize.value,
            maxSchematicPacketSize:
                configs.server.schematics.maxSchematicPacketSize.value,
            schematicIdleTimeout:
                configs.server.schematics.schematicIdleTimeout.value,
          );
    final receiver = SchematicUploadReceiver(
      store,
      limits: limits,
      warn: ctx.log.warn,
      info: ctx.log.info,
    );
    configs?.server.schematics.maxSchematics.onChange(
      (v) => receiver.limits = _limits(configs),
    );
    configs?.server.schematics.maxTotalSchematicSize.onChange(
      (v) => receiver.limits = _limits(configs),
    );
    configs?.server.schematics.maxSchematicPacketSize.onChange(
      (v) => receiver.limits = _limits(configs),
    );
    configs?.server.schematics.schematicIdleTimeout.onChange(
      (v) => receiver.limits = _limits(configs),
    );

    final rt = SchematicsRuntime.instance = SchematicsRuntime(
      ctx: ctx,
      hooks: hooks,
      loader: SchematicLoader(store, ctx.log),
      receiver: receiver,
      configs: configs,
      bus: ctx.services.find<PayloadBus>(),
    );
    ctx.services.provide<SchematicHooks>(hooks);
    ctx.services.provide<SchematicUploadReceiver>(receiver);
    installSchematicHandlers(rt);
  }

  SchematicLimits _limits(CreateConfigs c) => SchematicLimits(
    maxSchematics: c.server.schematics.maxSchematics.value,
    maxTotalSchematicSize: c.server.schematics.maxTotalSchematicSize.value,
    maxSchematicPacketSize: c.server.schematics.maxSchematicPacketSize.value,
    schematicIdleTimeout: c.server.schematics.schematicIdleTimeout.value,
  );

  /// `Block.asItem()` from the host's block registry.
  static final Map<String, String?> _items = {};

  static String? _itemOfBlock(String blockKey) =>
      _items.putIfAbsent(blockKey, () {
        final b = BlockRegistry.of(blockKey);
        if (b == null) return null;
        if (b.itemId == 0 && blockKey != 'minecraft:air') {
          // Create's own blocks have their item under the same key.
          return blockKey.startsWith('create:') ? blockKey : null;
        }
        return ItemRegistries.host.keyOf(b.itemId);
      });

  @override
  void onUnload() {
    try {
      SchematicsRuntime.instance.receiver.shutdown();
    } on Object {
      // `onLoad` never ran (an earlier phase failed), so there is nothing to shut down.
    }
  }
}
