// The `redstone` module: Create's `content/redstone` (links, controllers, diodes, display
// links, nixie tubes, observers, threshold switches, contacts, rails, bells, levers, lamps).
// See `docs/ARCHITECTURE.md` for the module contract.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart';
import '../api/redstone.dart';
import '../api/util.dart' hide pos;
import '../api/wrenchable.dart';
import '../contraptions/core/movement.dart';
import '../core/block_entity.dart' show BlockEntityTypeSpec;
import '../core/module.dart';
import '../core/registry.dart';
import 'contact_movement.dart';
import 'diodes/diode_blocks.dart';
import 'display/display_env.dart';
import 'display/display_link_block.dart';
import 'display/display_sources.dart';
import 'display/display_targets.dart';
import 'link/controller_host.dart';
import 'link/controller_items.dart';
import 'link/controller_server.dart';
import 'link/link_block.dart';
import 'link/link_handler.dart';
import 'nixie/nixie_blocks.dart';
import 'nixie/nixie_logic.dart';
import 'observer/observer_blocks.dart';
import 'rail_block.dart';
import 'support/placement.dart' show directedTargetDirection;
import 'simple_blocks.dart';
import 'support/level.dart';
import 'support/rs_runtime.dart';
import 'support/value_settings.dart';

final class RedstoneModule extends CreateModule {
  final DiodeBlocks _diodes = DiodeBlocks();
  final RedstoneContactBlock _contact = RedstoneContactBlock();
  final DeskBellBlock _bell = DeskBellBlock();
  final AnalogLeverBlock _lever = AnalogLeverBlock();
  final RoseQuartzLampBlock _lamp = RoseQuartzLampBlock();
  final RedstoneLinkBlock _link = RedstoneLinkBlock();
  final LecternControllerBlock _lectern = LecternControllerBlock();
  final SmartObserverBlock _observer = SmartObserverBlock();
  final ThresholdSwitchBlock _threshold = ThresholdSwitchBlock();
  final NixieTubeBlocks _nixies = NixieTubeBlocks();
  final ControllerRailBlock _rail = ControllerRailBlock();
  final DisplayLinkBlock _displayLink = DisplayLinkBlock();

  @override
  String get name => 'redstone';

  @override
  void register(CreateRegistry registry) {
    // Blocks in the order of the manifest (AllBlocks).
    registry.block(_rail.build());
    registry.block(_contact.build());
    registry.block(_threshold.build());
    registry.block(_displayLink.build());
    for (final b in _nixies.build()) {
      registry.block(b);
    }
    registry.block(_lamp.build());
    registry.block(_link.build());
    registry.block(_lever.build());
    registry.block(_diodes.pulseRepeater.build());
    registry.block(_diodes.pulseExtender.build());
    registry.block(_diodes.pulseTimer.build());
    registry.block(_diodes.poweredLatch.build());
    registry.block(_diodes.toggleLatch.build());
    registry.block(_lectern.build());
    registry.block(_observer.build());
    registry.block(_bell.build());

    // Block entity types.
    registry.blockEntityType(_leverSpec);
    registry.blockEntityType(_link.entitySpec());
    registry.blockEntityType(_nixies.entitySpec());
    registry.blockEntityType(_displayLink.entitySpec());
    registry.blockEntityType(_threshold.entitySpec());
    registry.blockEntityType(_observer.entitySpec());
    for (final d in _diodes.brass) {
      registry.blockEntityType(d.entitySpec());
    }
    registry.blockEntityType(_lectern.entitySpec());
    registry.blockEntityType(_bellSpec);

    // The linked controller (the only item of this module that is not a block item).
    registry.item(const ItemRegistration(key: linkedControllerItem, maxStackSize: 1));
  }

  BlockEntityTypeSpec get _leverSpec => const BlockEntityTypeSpec(
    key: AnalogLeverBlockEntity.type,
    validBlocks: ['create:analog_lever'],
    create: AnalogLeverBlockEntity.new,
    tickInterval: 1,
  );

  BlockEntityTypeSpec get _bellSpec => const BlockEntityTypeSpec(
    key: DeskBellBlockEntity.type,
    validBlocks: ['create:desk_bell'],
    create: DeskBellBlockEntity.new,
    tickInterval: 1,
  );

  @override
  void onLoad(CreateContext ctx) {
    final rs = RsRuntime(ctx);
    Rs.install(rs);

    registerDyedColorComponent();

    // Services.
    final observables = ObservableRegistry();
    ctx.services.provide<RedstoneLinkNetworkHandler>(rs.links);
    ctx.services.provide<ObservableRegistry>(observables);
    ctx.services.provide<RedstoneObservables>(observables);
    ctx.services.provide<RedstoneDisplayApi>(_DisplayApi(rs));

    _setUpDisplays(rs);

    // World events: link network spaces, controller presses.
    final handler = LinkedControllerServerHandler(
      rs.links,
      onReceiverActivated: (uuid) => unawaited(_awardLinkedController(rs, uuid)),
    );
    // The redstone contact on a contraption powers the contacts it passes over.
    MovementBehaviours.register('create:redstone_contact', const ContactMovementBehaviour());
    ctx.listen(Events.worldLoad, (server, e) => rs.links.onLoadWorld(rs.worldId(e.targetWorld)));
    ctx.listen(Events.worldUnload, (server, e) {
      if (e.cancelled) return;
      final id = e.targetWorld.getId();
      rs.links.onUnloadWorld(id);
      handler.onUnloadWorld(id);
      ReservationHolder.forget(id);
    });
    ctx.onWorldTick((t) {
      if (!handler.hasInputs) return;
      handler.tick(t.worldId);
    });

    // Interactions and payloads.
    LinkHandler.install(rs);
    LinkedControllerHooks.install(ctx, rs, handler);
    ClickToLink.install(ctx, rs);
    ValueSettingsRouter.install(rs);
    ThresholdSwitchBlock.installPacket(rs);
    DisplayLinkBlock.installPacket(rs);
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    _registerWrenchables(runtime);
  }

  @override
  void onUnload() {
    Rs.clear();
  }

  Future<void> _awardLinkedController(RsRuntime rs, String uuid) async {
    final advancements = rs.ctx.services.find<CreateAdvancements>();
    if (advancements == null) return;
    for (final p in rs.bus?.roster.players ?? const <Player>[]) {
      try {
        if (p.getId().asString == uuid) {
          await advancements.award(p, AllAdvancements.linkedController);
          return;
        }
      } on Object {
        // a handle that went invalid
      }
    }
  }

  // -- Display link registries (`AllDisplaySources` / `AllDisplayTargets`) -------------------------------

  void _setUpDisplays(RsRuntime rs) {
    final registry = rs.displays;
    for (final source in createDisplaySources()) {
      registry.addSource(source);
    }
    registry.legacySourceNames.addAll(legacyDisplaySourceNames);
    for (final color in dyeColorNames) {
      registry.legacySourceNames['${color}_seat_source_entity_name'] = 'entity_name';
    }
    for (final e in displaySourceBlocks().entries) {
      final source = registry.sourcesById['create:${e.key}'];
      if (source != null) registry.associateSource(e.value, source);
    }

    for (final target in createDisplayTargets()) {
      registry.addTarget(target);
    }
    registry.legacyTargetNames.addAll(legacyDisplayTargetNames);
    registry.associateTarget(['minecraft:lectern'], registry.targetsById['create:lectern']!);
    registry.associateTarget(['create:display_board'], registry.targetsById['create:display_board']!);
    registry.associateTarget(nixieBlockKeys, registry.targetsById['create:nixie_tube']!);
    registry.targetPredicates.add((isSignBlock, registry.targetsById['create:sign']!));
  }

  // -- Wrench ---------------------------------------------------------------------------------------------------

  void _registerWrenchables(CreateRuntime runtime) {
    final wrench = runtime.services.find<WrenchRegistry>();
    if (wrench == null) return;

    // IWrenchable defaults: rotate on click, dismantle on sneak click.
    wrench.registerDefault([
      'create:display_link',
      'create:desk_bell',
      'create:powered_latch',
      'create:powered_toggle_latch',
      'create:pulse_repeater',
      'create:pulse_extender',
      'create:pulse_timer',
      'create:analog_lever',
      ...nixieBlockKeys,
    ]);

    // RedstoneContactBlock.onWrenched: after the rotation, a contact in a live elevator
    // column becomes an elevator contact.
    wrench.register(
      'create:redstone_contact',
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          final result = await c.registry.defaultRotate(c);
          if (result != WrenchResult.success) return result;
          await RedstoneContactBlock.wrenchIntoElevatorContact(Lvl(c.world), c.pos.toPos());
          return result;
        },
      ),
    );

    // RedstoneLinkBlock.onWrenched: toggles between transmitter and receiver.
    wrench.register(
      'create:redstone_link',
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          final lvl = Lvl(c.world);
          if (await RedstoneLinkBlock.toggleMode(lvl, c.pos.toPos())) {
            lvl.scheduleTick(c.pos.toPos(), 1);
            return WrenchResult.success;
          }
          return WrenchResult.pass;
        },
      ),
    );

    // RoseQuartzLampBlock: the wrench flips POWERING and updates the cluster.
    wrench.register(
      'create:rose_quartz_lamp',
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          await RoseQuartzLampBlock.wrench(Lvl(c.world), c.pos.toPos());
          return WrenchResult.success;
        },
      ),
    );

    // ControllerRailBlock.onWrenched.
    wrench.register(
      'create:controller_rail',
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          await ControllerRailBlock.wrench(Lvl(c.world), c.pos.toPos());
          return WrenchResult.success;
        },
      ),
    );

    // DirectedDirectionalBlock.getRotatedBlockState.
    final directed = CallbackWrenchable(
      rotatedState: (c) {
        final props = c.properties;
        final facing = Direction.byName(props['facing'] ?? 'north') ?? Direction.north;
        final face = c.face.toDirection();
        Map<String, String> next;
        if (face.axis == Axis.y) {
          next = {'facing': facing.clockWise.serializedName};
        } else {
          final target = directedTargetDirection(props['target'] ?? 'wall', facing);
          var newFacing = target.clockWiseAround(face.axis);
          if (face.axisDirection == AxisDirection.negative) newFacing = newFacing.opposite;
          next = newFacing.axis == Axis.y
              ? {'target': newFacing == Direction.up ? 'ceiling' : 'floor'}
              : {'target': 'wall', 'facing': newFacing.serializedName};
        }
        return BlockStates.withProperties(c.blockKey, {...props, ...next});
      },
    );
    wrench.registerAll(['create:content_observer', 'create:stockpile_switch'], directed);
  }
}

/// [RedstoneDisplayApi] over the module.
final class _DisplayApi implements RedstoneDisplayApi {
  final RsRuntime rs;

  _DisplayApi(this.rs);

  @override
  void registerSource(DisplaySource source, Iterable<String> blockKeys) {
    final existing = rs.displays.sourcesById[source.id];
    if (existing == null) rs.displays.addSource(source);
    rs.displays.associateSource(blockKeys, existing ?? source);
  }

  @override
  void registerTarget(DisplayTarget target, Iterable<String> blockKeys) {
    final existing = rs.displays.targetsById[target.id];
    if (existing == null) rs.displays.addTarget(target);
    rs.displays.associateTarget(blockKeys, existing ?? target);
  }

  @override
  Future<void> notifyGatherers(World world, BlockPos pos) => DisplayLinkBlock.notifyGatherers(Lvl(world), pos.toPos());

  @override
  Future<void> itemReceived(World world, BlockPos pos, int amount) =>
      DisplayLinkBlock.itemReceived(Lvl(world), pos.toPos(), amount);

  @override
  Future<void> onFunnelTransfer(World world, BlockPos funnelPos, String itemKey) =>
      SmartObserverBlock.onFunnelTransfer(world, funnelPos, itemKey);
}
