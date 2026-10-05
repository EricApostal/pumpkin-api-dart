import 'package:wasm_components/wasm_components.dart'
    show ErrorResult, OkResult;

import 'bindings.g.dart' as generated;
import 'block_registry_core.dart';

/// The host's block registry (`block-registry.wit`), for plugins that add
/// blocks.
///
/// Registration needs the `registry.blocks` permission
/// ([Permissions.registryBlocks] in `PluginInfo.permissions`) and is only
/// possible while the server loads (`Plugin.onLoad` and `ServerLoadEvent`);
/// once it accepts connections the registry is closed. Custom blocks get the
/// ids `vanillaBlockCount + n`, `n` being the order of registration across all
/// plugins, and their states follow the vanilla states
/// (`docs/block-registry.md`, [BlockStateLayout]).
///
/// A block that has an item registers the item first (`ItemRegistries.host`),
/// then the block, then links them:
///
/// ```dart
/// final id = BlockRegistries.host.register(
///   BlockDefinition(
///     key: 'my_plugin:ruby_block',
///     hardness: 5,
///     blastResistance: 6,
///     requiresCorrectTool: true,
///     tags: ['minecraft:mineable/pickaxe', 'minecraft:needs_iron_tool'],
///   ),
/// );
/// BlockRegistries.host.setBlockItem('my_plugin:ruby_block', 'my_plugin:ruby_block');
/// ```
abstract final class BlockRegistries {
  /// The server's block registry.
  static final BlockRegistryBackend host = const HostBlockRegistry();
}

/// [BlockRegistryBackend] over the generated host bindings.
final class HostBlockRegistry implements BlockRegistryBackend {
  const HostBlockRegistry();

  @override
  int register(BlockDefinition block) {
    // The host would reject the same things with the same words, but a plugin
    // author sees all of them at once this way, before any host call.
    block.check();
    final result = generated.blockRegistry.registerBlock(
      definition: _toWire(block),
    );
    return switch (result) {
      OkResult(:final value) => value,
      ErrorResult(:final value) => throw BlockRegistryException(
        'Registering ${block.key} failed: $value',
      ),
    };
  }

  @override
  void registerTag(String tag, List<String> entries) {
    final result = generated.blockRegistry.registerBlockTag(
      tag: tag,
      entries: entries,
    );
    if (result case ErrorResult(:final value)) {
      throw BlockRegistryException(
        'Registering the block tag $tag failed: $value',
      );
    }
  }

  @override
  void setBlockItem(String itemKey, String blockKey) {
    final result = generated.blockRegistry.setBlockItem(
      itemKey: itemKey,
      blockKey: blockKey,
    );
    if (result case ErrorResult(:final value)) {
      throw BlockRegistryException(
        'Linking the item $itemKey to the block $blockKey failed: $value',
      );
    }
  }

  @override
  int? idOf(String key) => generated.blockRegistry.getBlockId(key: key);

  @override
  String? keyOf(int id) => generated.blockRegistry.getBlockKey(id: id);

  @override
  int get vanillaBlockCount => generated.blockRegistry.getVanillaBlockCount();

  @override
  int get vanillaStateCount => generated.blockRegistry.getVanillaStateCount();

  @override
  int? stateId(String block, Map<String, String> properties) =>
      generated.blockRegistry.getStateId(
        block: block,
        properties: [
          for (final e in properties.entries)
            generated.PropertyValue(name: e.key, value: e.value),
        ],
      );

  @override
  List<RegisteredBlock> get registeredBlocks => [
    for (final e in generated.blockRegistry.getRegisteredBlocks())
      RegisteredBlock(
        key: e.key,
        id: e.id,
        baseStateId: e.baseStateId,
        stateCount: e.stateCount,
        itemId: e.itemId,
      ),
  ];

  static generated.BlockDefinition _toWire(BlockDefinition b) =>
      generated.BlockDefinition(
        key: b.key,
        properties: [
          for (final p in b.properties)
            generated.BlockProperty(name: p.name, kind: _kind(p.kind)),
        ],
        defaultState: [
          for (final e in b.defaultState.entries)
            generated.PropertyValue(name: e.key, value: e.value),
        ],
        hardness: b.hardness,
        blastResistance: b.blastResistance,
        requiresCorrectTool: b.requiresCorrectTool,
        soundType: b.soundType,
        luminance: b.luminance,
        canOcclude: b.canOcclude,
        suffocating: b.suffocating,
        replaceable: b.replaceable,
        mapColor: b.mapColor,
        collisionShape: _shape(b.collisionShape),
        selectionShape: _shape(b.selectionShape),
        connectRules: [
          for (final r in b.connectRules)
            generated.ConnectRule(
              property: r.property,
              direction: generated.ConnectDirection.values.byName(
                r.direction.name,
              ),
              target: switch (r.target) {
                ConnectSameBlock() => const generated.ConnectTargetSameBlock(),
                ConnectBlock(:final key) => generated.ConnectTargetBlock(key),
                ConnectTag(:final tag) => generated.ConnectTargetTag(tag),
              },
            ),
        ],
        drops: switch (b.drops) {
          DropsSelfItem() => const generated.BlockDropsSelfItem(),
          DropsNothing() => const generated.BlockDropsNothing(),
          DropsLootTable(:final key) => generated.BlockDropsLootTable(key),
        },
        tags: b.tags,
      );

  static generated.PropertyKind _kind(BlockPropertyKind kind) => switch (kind) {
    BoolKind() => const generated.PropertyKindBoolean(),
    IntRangeKind(:final min, :final max) => generated.PropertyKindIntRange(
      generated.IntBounds(min: min, max: max),
    ),
    EnumKind(:final values) => generated.PropertyKindEnumeration(values),
  };

  static generated.BlockShape _shape(BlockShape shape) => switch (shape) {
    EmptyShape() => const generated.BlockShapeEmpty(),
    FullCubeShape() => const generated.BlockShapeFullCube(),
    BoxesShape(:final boxes) => generated.BlockShapeBoxes([
      for (final b in boxes)
        generated.BlockBox(
          minX: b.minX,
          minY: b.minY,
          minZ: b.minZ,
          maxX: b.maxX,
          maxY: b.maxY,
          maxZ: b.maxZ,
        ),
    ]),
  };
}
