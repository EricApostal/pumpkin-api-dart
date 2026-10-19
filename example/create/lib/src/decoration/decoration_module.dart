// The decoration module: Create's `content/decoration` (brackets, copycats, encasing, girders,
// palettes, placards, sliding doors, steam whistles) and the palette block families.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/wrenchable.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../manifest/manifest.dart';
import 'behaviour_support.dart';
import 'block_entities.dart';
import 'blocks_copycat.dart';
import 'bracket.dart';
import 'bracketed_behaviour.dart';
import 'catalog.dart';
import 'copycat.dart';
import 'encasing.dart';
import 'roles.dart';
import 'girder.dart';
import 'runtime.dart';
import 'sliding_door_movement.dart';
import 'sliding_doors.dart';
import 'whistle.dart';

/// The decoration module.
final class DecorationModule extends CreateModule {
  @override
  String get name => 'decoration';

  final DecorationRuntime _rt = DecorationHost.rt;
  final BracketRegistry _brackets = BracketRegistry();
  final EncasingRegistry _encasing = EncasingRegistry();
  bool _wrenchRegistered = false;

  @override
  void register(CreateRegistry registry) {
    for (final spec in decorationBlockEntityTypes()) {
      registry.blockEntityType(spec);
    }
    for (final m in kBlocks) {
      if (!ownsBlock(m)) continue;
      final block = buildDecorationBlock(m, _rt);
      _rt.blocks[block.key] = block;
      registry.block(block);
    }
    // `BuilderTransformers.slidingDoor` gives every sliding door the movement behaviour that
    // opens it while its contraption stands at a station or elevator floor.
    registerSlidingDoorMovementBehaviour();
    // `CopycatBlockEntity.transform` / `BracketedBlockEntityBehaviour.transformBracket`: the
    // stored state follows a moved contraption.
    registerCopycatTransform();
    registerBracketTransform();
  }

  @override
  void onLoad(CreateContext ctx) {
    _rt.init(ctx);
    ctx.services.provide<BracketRegistry>(_brackets);
    ctx.services.provide<EncasingRegistry>(_encasing);
    ctx.services.provide<SlidingDoors>(SlidingDoors(_rt));

    // Records the last click of each player (the placement context of the blocks) and handles the
    // bracket items, which never place their block: `BracketBlockItem.useOn`.
    ctx.host.intercept(Events.playerUseBlock, (server, e) async {
      _rt.clicks[e.player.uuidString] = ClickContext(
        e.blockPos.toPos(),
        dirOf(e.face),
        e.cursor,
        e.sneaking,
        e.hand,
        _rt.serverTick,
      );
      final key = await e.item.getRegistryKey();
      if (key == woodenBracketKey || key == metalBracketKey) {
        await _bracketUse(server, e, key);
        return e.cancel();
      }
      // `EncasableBlock.tryEncase`: casings applied to shafts, cogwheels, pipes, ... (not while sneaking,
      // when vanilla skips the block's `useItemOn`).
      if (!e.sneaking &&
          _encasing.getVariants(e.block).any((v) => v.casingItemKey == key)) {
        final world = e.player.getWorld();
        final state = HostBlockGetter(world).stateAt(e.blockPos.toPos());
        final result = await _encasing.tryEncase(
          world: world,
          pos: e.blockPos,
          state: state,
          heldItemKey: key,
          player: e.player,
          hand: e.hand,
        );
        if (result == BlockUseResult.success) return e.cancel();
      }
      return e;
    }, priority: EventPriority.lowest);

    ctx.listen(Events.serverTickStart, (server, _) => _rt.serverTick++);

    _registerWrench(ctx.services.find<WrenchRegistry>());
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    if (!_wrenchRegistered)
      _registerWrench(runtime.services.find<WrenchRegistry>());
  }

  // -- Brackets ----------------------------------------------------------------------------

  /// `BracketBlockItem.useOn`.
  Future<void> _bracketUse(
    Server server,
    PlayerUseBlockEventData e,
    String bracketKey,
  ) async {
    final player = e.player;
    final world = player.getWorld();
    final pos = e.blockPos.toPos();
    final level = HostBlockGetter(world);
    final state = level.stateAt(pos);
    final behaviour = BracketedBlockEntityBehaviour.at(
      _rt.store,
      world.getId(),
      pos,
    );
    if (behaviour == null || !behaviour.canHaveBracket()) return;
    final block = _rt.blocks[bracketKey]!;
    final defaultState = BState(block.key, block.definition.defaultState);
    var suitable = _brackets.suitableBracket(
      defaultState,
      state,
      dirOf(e.face),
    );
    suitable ??= _brackets.suitableBracket(
      defaultState,
      state,
      _rt.nearestLooking(player).first.opposite,
    );
    if (suitable == null) return;
    final bracket = behaviour.bracket;
    if (bracket == suitable) return;
    _rt.playSound(
      world,
      pos,
      'minecraft:block.scaffolding.place',
      volume: 0.75,
    );
    await behaviour.applyBracket(suitable);
    if (!player.isCreative) {
      await _rt.shrinkHeld(player, e.hand);
      if (bracket != null)
        await _rt.giveOrDrop(player, world, pos, bracket.key);
    }
  }

  // -- Wrench ------------------------------------------------------------------------------

  void _registerWrench(WrenchRegistry? wrench) {
    if (wrench == null) return;
    _wrenchRegistered = true;
    _rt.wrench = wrench;
    final keys = _rt.blocks.keys.toList();
    bool roleIs(String key, DecorationRole role) {
      final m = manifestBlocksByKey[key.substring(key.indexOf(':') + 1)];
      return m != null && roleOf(m) == role;
    }

    // Plain `IWrenchable`: rotate and dismantle.
    wrench.registerDefault([
      for (final k in keys)
        if (roleIs(k, DecorationRole.ladder) ||
            roleIs(k, DecorationRole.scaffolding) ||
            roleIs(k, DecorationRole.trapdoor) ||
            roleIs(k, DecorationRole.slidingDoor) ||
            roleIs(k, DecorationRole.placard))
          k,
    ]);

    // `CasingBlock.onWrenched` is FAIL: casings cannot be rotated, only dismantled.
    wrench.registerAll([
      for (final k in keys)
        if (roleIs(k, DecorationRole.casing)) k,
    ], CallbackWrenchable(onWrenchedOverride: (c) async => WrenchResult.fail));

    // Directional blocks rotate around the clicked face (`WrenchableDirectionalBlock`).
    wrench.registerAll(
      [
        for (final k in keys)
          if (roleIs(k, DecorationRole.bracket) ||
              roleIs(k, DecorationRole.copycatBars))
            k,
      ],
      CallbackWrenchable(
        rotatedState: (c) {
          final s = BState(c.blockKey, c.properties);
          final targeted = d.Direction.values[c.face.index];
          return stateIdOf(wrenchableDirectionalRotated(s, targeted));
        },
      ),
    );

    // `GirderBlock.onWrenched` passes; the sneaking click dismantles.
    wrench.register(
      girderKey,
      CallbackWrenchable(onWrenchedOverride: (c) async => WrenchResult.pass),
    );

    // The encased girder turns back into a girder and gives the shaft back.
    wrench.register(
      girderEncasedShaftKey,
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          final girder = _rt.blocks[girderKey]!;
          final back = girderFromEncasedShaft(
            BState(c.blockKey, c.properties),
            BState(girder.key, girder.definition.defaultState),
          );
          final id = stateIdOf(back);
          if (id == null) return WrenchResult.pass;
          final switcher = c.registry.stateSwitcher;
          if (switcher != null) {
            await switcher(c.world, c.pos, id);
          } else {
            await setBlockState(c.world, c.pos.toPos(), back);
          }
          _rt.playCreateSound(
            c.world,
            c.pos.toPos(),
            'wrench_rotate',
            pitch: .5 + .5,
          );
          if (!c.player.isCreative)
            await _rt.giveOrDrop(
              c.player,
              c.world,
              c.pos.toPos(),
              'create:shaft',
            );
          return WrenchResult.success;
        },
      ),
    );

    // Copycats: the wrench takes the material off (and gives the item back); sneaking also dismantles.
    final copycat = CallbackWrenchable(
      onWrenchedOverride: (c) async =>
          await copycatRemoveMaterial(_rt, c.world, c.pos, c.player)
          ? WrenchResult.success
          : WrenchResult.pass,
      onSneakOverride: (c) async {
        await copycatRemoveMaterial(_rt, c.world, c.pos, c.player);
        return c.registry.defaultDismantle(c);
      },
    );
    wrench.register(copycatPanelKey, copycat);
    wrench.register(copycatStepKey, copycat);

    // Whistles cycle their size; extensions act on the whistle below them.
    wrench.register(
      whistleKey,
      CallbackWrenchable(
        rotatedState: (c) {
          final s = BState(c.blockKey, c.properties);
          final i = whistleSizes.indexOf(s['size'] ?? 'medium');
          return stateIdOf(
            s.setValue('size', whistleSizes[(i + 1) % whistleSizes.length]),
          );
        },
      ),
    );
    wrench.register(
      whistleExtensionKey,
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          final level = HostBlockGetter(c.world);
          final root = whistleFindRoot(level, c.pos.toPos());
          final rootState = level.stateAt(root);
          if (rootState.key != whistleKey) return WrenchResult.pass;
          final handler = c.registry.of(whistleKey);
          if (handler == null) return WrenchResult.pass;
          final rootId = stateIdOf(rootState) ?? c.stateId;
          return handler.onWrenched(
            WrenchContext(
              registry: c.registry,
              player: c.player,
              world: c.world,
              pos: root.toBlockPos(),
              face: c.face,
              blockKey: whistleKey,
              stateId: rootId,
              properties: rootState.props,
              hand: c.hand,
              stack: c.stack,
              cursor: c.cursor,
            ),
          );
        },
        onSneakOverride: (c) async {
          // `WhistleExtenderBlock.onSneakWrenched`: the upper half of a double extension is split off.
          final state = BState(c.blockKey, c.properties);
          if (c.cursor.$2 < .5 || state['shape'] == 'single')
            return c.registry.defaultDismantle(c);
          await setBlockState(
            c.world,
            c.pos.toPos(),
            state.setValue('shape', 'single'),
          );
          _rt.playCreateSound(
            c.world,
            c.pos.toPos(),
            'wrench_remove',
            pitch: .5 + .5,
          );
          return WrenchResult.success;
        },
      ),
    );
  }
}
