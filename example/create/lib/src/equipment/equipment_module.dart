// The equipment module: Create's `content/equipment` on the server (armor and backtanks, bells,
// blueprint, clipboard, extendo grip, goggles, potato cannon, sand paper, symmetry wand, tools,
// toolbox, wrench, worldshaper). See docs of `lib/src/api/equipment.dart` and `wrenchable.dart`.

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/config.dart';
import '../api/equipment.dart';
import '../api/payloads.dart';
import '../api/wrenchable.dart';
import '../core/block_entity.dart';
import '../core/module.dart';
import '../core/registry.dart';
import 'armor/armor_host.dart';
import 'armor/backtank_block.dart';
import 'armor/backtank_host.dart';
import 'bell/bell_host.dart';
import 'blocks/shapes.dart';
import 'blueprint/blueprint_host.dart';
import 'clipboard/clipboard_host.dart';
import 'equipment_items.dart';
import 'equipment_settings.dart';
import 'host/env.dart';
import 'host/runtime.dart';
import 'potato/potato_host.dart';
import 'symmetry/symmetry_host.dart';
import 'toolbox/toolbox_host.dart';
import 'tools/misc_host.dart';
import 'wrench/wrench_host.dart';
import 'zapper/zapper_host.dart';

const List<String> _colors = [
  'white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
  'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black', //
];

final class EquipmentModule extends CreateModule {
  @override
  String get name => 'equipment';

  // Hosts exist from onLoad; blocks are declared before, so behaviours resolve them lazily.
  EquipmentEnv? _env;
  late final BellHost _bellsLazy = BellHost(_env!);
  late final BacktankBlockHost _tankBlocks = BacktankBlockHost(_env!);
  late final ClipboardHost _clipboardLazy = ClipboardHost(_env!);

  @override
  void register(CreateRegistry registry) {
    for (final k in equipmentItemKeys) {
      registry.item(equipmentItem(k));
    }
    registry.entityType(equipmentEntityType('crafting_blueprint'));
    registry.entityType(equipmentEntityType('potato_projectile'));

    // Backtank blocks (their item is `*_backtank_placeable`, linked in onLoad)
    for (final k in const ['copper_backtank', 'netherite_backtank']) {
      registry.block(manifestBlock(
        k,
        blockEntityType: backtankBlockEntityType,
        placement: const [
          PlacementRule.horizontalFacing('facing', opposite: true),
          PlacementRule.inWater('waterlogged'),
        ],
        collisionShape: BlockShape.boxes(backtankBoxes()),
        selectionShape: BlockShape.boxes(backtankBoxes()),
        drops: lootTableOf(k),
        behavior: _deferred(() => _tankBlocks.behavior()),
      ));
    }
    registry.blockEntityType(BlockEntityTypeSpec(
      key: backtankBlockEntityType,
      validBlocks: const ['create:copper_backtank', 'create:netherite_backtank'],
      create: BacktankBlockEntity.new,
    ));

    // Bells
    for (final (k, haunted) in const [('peculiar_bell', false), ('haunted_bell', true)]) {
      registry.block(manifestBlock(
        k,
        blockEntityType: haunted ? hauntedBellEntityType : peculiarBellEntityType,
        placement: const [PlacementRule.horizontalFacing('facing')],
        shapeRules: bellRules(),
        drops: lootTableOf(k),
        behavior: _deferred(() => _bellsLazy.behavior(haunted: haunted)),
      ));
    }
    registry.blockEntityType(BlockEntityTypeSpec(
      key: peculiarBellEntityType,
      validBlocks: const ['create:peculiar_bell'],
      create: (w, p) => CreateBellEntity(w, p, haunted: false),
    ));
    registry.blockEntityType(BlockEntityTypeSpec(
      key: hauntedBellEntityType,
      validBlocks: const ['create:haunted_bell'],
      create: (w, p) => CreateBellEntity(w, p, haunted: true),
    ));

    // Toolboxes
    for (final c in _colors) {
      registry.block(manifestBlock(
        '${c}_toolbox',
        blockEntityType: toolboxBlockEntityType,
        placement: const [
          PlacementRule.horizontalFacing('facing', opposite: true),
          PlacementRule.inWater('waterlogged'),
        ],
        shapeRules: horizontalRules(toolboxBoxes),
        drops: lootTableOf('${c}_toolbox'),
        behavior: _deferred(() => _toolboxBehavior()),
      ));
    }
    registry.blockEntityType(BlockEntityTypeSpec(
      key: toolboxBlockEntityType,
      validBlocks: [for (final c in _colors) 'create:${c}_toolbox'],
      create: ToolboxBlockEntity.new,
    ));

    // Clipboard
    registry.block(manifestBlock(
      'clipboard',
      blockEntityType: clipboardEntityType,
      shapeRules: clipboardRules(),
      drops: BlockDrops.nothing,
      behavior: _deferred(() => _clipboardLazy.behavior()),
    ));
    registry.blockEntityType(BlockEntityTypeSpec(
      key: clipboardEntityType,
      validBlocks: const ['create:clipboard'],
      create: ClipboardBlockEntity.new,
      tickInterval: 20,
    ));
  }

  /// A behaviour whose hooks resolve the real behaviour on first use (the hosts need `onLoad`).
  BlockBehavior _deferred(BlockBehavior Function() make) {
    late final BlockBehavior real = make();
    return BlockBehavior(
      onPlaced: (s, e) => real.onPlaced?.call(s, e),
      onNeighborUpdate: (s, e) => real.onNeighborUpdate?.call(s, e),
      onUse: (s, e) async => await real.onUse?.call(s, e) ?? BlockUseResult.pass,
      onAttack: (s, e) => real.onAttack?.call(s, e),
      onPlayerWillDestroy: (s, e) async => await real.onPlayerWillDestroy?.call(s, e) ?? true,
      onComparatorOutput: (s, e) => real.onComparatorOutput?.call(s, e),
    );
  }

  BlockBehavior _toolboxBehavior() {
    final env = _env!;
    final rt = EquipmentRuntime.instance;
    ToolboxBlockEntity? be(World w, BlockPos p) => env.ctx.blockEntities.typed<ToolboxBlockEntity>(w.getId(), p);
    return BlockBehavior(
      onPlaced: (server, e) async {
        final uuid = e.player;
        final b = be(e.targetWorld, e.pos);
        if (uuid == null || e.moved || b == null) return;
        final player = server.getPlayerByUuid(id: uuid);
        final held = player?.getInventory().getItemInHand(hand: Hand.right);
        if (held == null) return;
        await rt.toolbox.applyItemData(b, held, env);
      },
      onUse: (server, e) async {
        final player = e.player;
        if (player.asEntity().isSneaking()) return BlockUseResult.tryEmptyHand;
        final b = be(e.targetWorld, e.pos);
        if (b == null) return BlockUseResult.pass;
        // dyeing: another colour keeps the contents
        final key = await stackKey(e.item);
        if (key.endsWith('_dye')) {
          final color = key.substring('minecraft:'.length, key.length - 4);
          if ('create:${color}_toolbox' != e.block && _colors.contains(color)) {
            await rt.toolbox.recolor(e.targetWorld, e.pos, b, 'create:${color}_toolbox');
            return BlockUseResult.success;
          }
        }
        await rt.toolbox.openMenu(player, b);
        return BlockUseResult.success;
      },
      onAttack: (server, e) async {
        final b = be(e.targetWorld, e.pos);
        if (b == null) return;
        await rt.toolbox.collectBox(e.player, e.targetWorld, b, e.block);
      },
      onComparatorOutput: (server, e) => be(e.targetWorld, e.pos)?.inv.comparatorSignal() ?? 0,
    );
  }

  @override
  void onLoad(CreateContext ctx) {
    final bus = ctx.services.require<PayloadBus>();
    final wrench = WrenchRegistry();
    ctx.services.provide<WrenchRegistry>(wrench);
    final settings = EquipmentSettings(() => ctx.services.find<CreateConfigs>());
    final env = EquipmentEnv(ctx: ctx, settings: settings, bus: bus, wrench: wrench);
    _env = env;

    final backtanks = BacktankHost(env);
    final armor = ArmorHost(env, backtanks);
    final toolbox = ToolboxHost(env);
    final bells = _bellsLazy;
    EquipmentRuntime(env: env, backtanks: backtanks, armor: armor, toolbox: toolbox, bells: bells);

    final misc = MiscItemsHost(env, armor, backtanks);
    ctx.services.provide<BacktankApi>(backtanks);
    ctx.services.provide<GogglesApi>(armor);
    ctx.services.provide<CardboardArmorApi>(armor);
    ctx.services.provide<ExtendoGripApi>(misc);
    ctx.services.provide<SandPaperApi>(misc);

    // order matters: ArmorHost keeps the worn-gear map the later hosts read
    armor.install(ctx);
    WrenchHost(env).install(ctx);
    SymmetryHost(env).install(ctx);
    ZapperHost(env).install(ctx);
    PotatoHost(env, backtanks).install(ctx);
    misc.install(ctx);
    toolbox.install(ctx);
    bells.install(ctx);
    _clipboardLazy.install(ctx);
    BlueprintHost(env).install(ctx);
    _tankBlocks.install(ctx);
    _installDrops(ctx, env);

    // Wrench defaults for the equipment blocks that are `IWrenchable`.
    wrench.registerDefault(const ['create:clipboard']);
    wrench.registerAll(
      const ['create:copper_backtank', 'create:netherite_backtank'],
      CallbackWrenchable(onSneakOverride: (c) async {
        final be = ctx.blockEntities.typed<BacktankBlockEntity>(c.world.getId(), c.pos);
        final stack = await _tankBlocks.cloneItem(c.blockKey, be);
        await c.world.destroyBlock(pos: c.pos, drop: false, player: null, withParticles: true);
        await EquipmentRuntime.instance.toolbox.giveItem(c.player, c.world, stack);
        return WrenchResult.success;
      }),
    );

    // The placeable backtank items place the backtank blocks.
    for (final k in const ['copper', 'netherite']) {
      try {
        BlockRegistries.host.setBlockItem('create:${k}_backtank_placeable', 'create:${k}_backtank');
      } on Object catch (e) {
        ctx.log.warn('could not link ${k}_backtank_placeable: $e');
      }
    }
  }

  /// Items dropped by the toolbox and backtank blocks get the data of the block entity.
  void _installDrops(CreateContext ctx, EquipmentEnv env) {
    ctx.host.intercept(Events.blockDropItem, (server, e) async {
      final world = e.targetWorld;
      final be = ctx.blockEntities.at(world.getId(), e.blockPos);
      if (be == null) return e;
      for (final stack in e.items) {
        final key = await stack.getRegistryKey();
        if (be is BacktankBlockEntity && EqItems.isBacktank(key)) {
          final data = await _tankBlocks.cloneItem(key, be);
          final air = data.customComponent('create:banktank_air');
          if (air != null) stack.setCustomComponent('create:banktank_air', air);
          if (be.capacityEnchantLevel > 0) {
            await stack.addCustomEnchantment(enchantmentId: 'create:capacity', level: be.capacityEnchantLevel);
          }
        } else if (be is ToolboxBlockEntity && key.endsWith('_toolbox')) {
          final data = await EquipmentRuntime.instance.toolbox.itemWithData(be, key);
          for (final c in const ['create:toolbox_inventory', 'create:toolbox_uuid']) {
            final v = data?.customComponent(c);
            if (v != null) stack.setCustomComponent(c, v);
          }
          final name = be.customName;
          if (name != null) await stack.setCustomName(name: TextComponent.text(plain: name));
        }
      }
      return e;
    });
  }

  @override
  void onUnload() {
    if (EquipmentRuntime.isLoaded) EquipmentRuntime.instance.dispose();
  }
}
