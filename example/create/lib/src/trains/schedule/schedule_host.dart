// Host glue of the schedule area: the schedule item (opens the menu, hands a schedule to the
// conductor of a train), the menu bookkeeping, the three serverbound payloads
// (`create:configure_schedule`, `create:c_configure_train`, `create:submit_ghost_item`) and the
// [HostScheduleProbe] the host `TrainLevel` uses for the world questions of the conditions.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../api/payloads.dart';
import '../../api/sounds.dart' show CreateSounds;
import '../../api/util.dart' hide pos;
import '../../common/ghost_menu_layout.dart';
import '../../common/menu_mirror.dart';
import '../../core/module.dart';
import '../../core/nbt.dart' show NetworkNbt;
import '../../core/registry.dart' show RegistryKind;
import '../entity/train_level.dart' show TrainFx;
import '../support/runtime.dart';
import '../util/ctag.dart';
import 'schedule_item.dart';
import 'schedule_edit_packet.dart';
import 'schedule_menu.dart';
import 'schedule_services.dart';
import 'train_edit_packet.dart';

/// The conductor advancement (`AllAdvancements.CONDUCTOR`).
const String _conductorAdvancement = 'conductor';

/// `ScheduleMenu.addSlots`: the 36 player slots first, then the two ghost slots of the item and
/// fluid pickers (`GhostMenu.schedule`).
const GhostMenu scheduleLayout = GhostMenu.schedule;

/// The menu slot of the schedule ghost slot [i] (`36 + i`).
int scheduleGhostSlot(int i) => scheduleLayout.ghostSlot(i);

/// The host side of the world questions in [ScheduleLevel] (`overworldClockTime`, loaded chunks,
/// redstone at a station). The redstone read of the host is asynchronous: [hasNeighborSignal]
/// answers from the last completed read and starts the next one, so a change is seen within a
/// tick or two.
final class HostScheduleProbe {
  final Map<(String, Pos), bool> _powered = {};
  final Set<(String, Pos)> _reading = {};

  /// `level.getOverworldClockTime()`.
  int overworldClockTime() => Tr.i.worldById('minecraft:overworld')?.getTimeOfDay() ?? 0;

  /// `server.getLevel(dimension) != null`.
  bool hasDimension(String dimension) => Tr.i.worldById(dimension) != null;

  /// `serverLevel.isLoaded(pos)`.
  bool isLoaded(String dimension, Pos pos) {
    final world = Tr.i.worldById(dimension);
    return world != null && world.isLoaded(pos: pos.toBlockPos());
  }

  /// `serverLevel.isPositionEntityTicking(pos)`: a loaded chunk.
  bool isPositionEntityTicking(String dimension, Pos pos) => isLoaded(dimension, pos);

  /// `serverLevel.hasNeighborSignal(pos)` from the cache, refreshing it in the background.
  bool hasNeighborSignal(String dimension, Pos pos) {
    final key = (dimension, pos);
    if (_reading.add(key)) {
      final world = Tr.i.worldById(dimension);
      if (world == null) {
        _reading.remove(key);
        return false;
      }
      unawaited(
        world
            .hasRedstoneNeighborSignal(pos.toBlockPos())
            .then<void>(
              (v) {
                _powered[key] = v;
                _reading.remove(key);
              },
              onError: (Object _) {
                _reading.remove(key);
              },
            ),
      );
    }
    return _powered[key] ?? false;
  }
}

/// Installs the item, the menu bookkeeping and the payload handlers.
final class ScheduleHost {
  final CreateContext ctx;

  /// The open schedule menus by player uuid.
  final Map<String, ScheduleMenu> openMenus = {};

  ScheduleHost(this.ctx);

  ItemIdResolver get _ids => HostItemStacks.resolverFor(() => ctx.ids);

  void install() {
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.host.intercept(Events.playerUseItem, _onUseItem);
    ctx.host.intercept(Events.playerInteractEntity, _onInteractEntity);
    ctx.listen(Events.menuClosed, (Server server, MenuClosedEventData e) {
      if (e.menuType == scheduleMenuType) openMenus.remove(e.player.getId().asString);
    });
    ctx.listen(Events.menuSlotChanged, (Server server, MenuSlotChangedEventData e) {
      if (e.menuType != scheduleMenuType) return;
      unawaited(_onMenuSlotChanged(e.player, e));
    });
    ctx.listen(Events.playerLeave, (Server server, PlayerLeaveEventData e) {
      openMenus.remove(e.player.getId().asString);
    });

    final bus = ctx.services.find<PayloadBus>();
    if (bus == null) return;
    bus.onServerbound('create:configure_schedule', (player, f) => unawaited(_onConfigureSchedule(player, f)));
    bus.onServerbound('create:c_configure_train', (player, f) => _onConfigureTrain(bus, f));
    bus.onServerbound('create:submit_ghost_item', (player, f) => _onSubmitGhostItem(player, f));
  }

  // -- Item: `ScheduleItem.use` / `useOn` ---------------------------------------------------

  Future<bool> _isSchedule(ItemStack? stack) async =>
      stack != null && await stack.getCount() > 0 && await stack.getRegistryKey() == scheduleItemKey;

  Future<ItemUseFirstEventData> _onUseFirst(Server server, ItemUseFirstEventData e) async {
    if (!await _isSchedule(e.stack)) return e;
    if (e.hand != Hand.right) return e;
    if (e.player.asEntity().isSneaking()) return e;
    await _openMenu(e.player);
    return e.copyWith(useResult: ItemUseFirstResult.success);
  }

  Future<PlayerUseItemEventData> _onUseItem(Server server, PlayerUseItemEventData e) async {
    if (e.clickedPos != null) return e;
    if (!await _isSchedule(e.item)) return e;
    if (e.hand != Hand.right) return e;
    if (e.player.asEntity().isSneaking()) return e;
    await _openMenu(e.player);
    return e.cancel();
  }

  static final MenuClickRules _rules = MenuClickRules(
    slotRules: [
      for (var i = 0; i < ScheduleMenu.slots; i++)
        MenuSlotRule(
          slot: scheduleGhostSlot(i),
          kind: const MenuSlotKindGhost(),
          maxStackSize: null,
        ),
    ],
    quickMoveTargets: const [],
  );

  /// `player.openMenu(this, buf -> ItemStack.STREAM_CODEC.encode(buf, heldItem))`.
  Future<void> _openMenu(Player player) async {
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    if (held == null) return;
    final itemId = ctx.ids.of(RegistryKind.items, scheduleItemKey);
    if (itemId == null) return;
    final count = await held.getCount();
    final component = held.customComponent(trainScheduleComponent);
    final componentId = ctx.ids.of(RegistryKind.dataComponents, trainScheduleComponent);
    final patch = component != null && componentId != null
        ? ItemComponentPatch(added: [(componentId, Uint8List.fromList(component))])
        : ItemComponentPatch.empty;
    final extra = PacketBuffer.encode((w) => ItemStackData(itemId, count, patch).write(w, allowEmpty: false));
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: scheduleMenuType,
      title: TextComponent.translate(key: 'item.create.schedule', with_: const []),
      extraData: extra,
      slotCount: scheduleLayout.menuSlots,
      options: MenuOptions(
        applyVanillaClicks: true,
        // The client's menu adds the player inventory first (`ScheduleMenu.addSlots`), so the
        // server tracks a mirror of it instead of the host's player-inventory layout.
        playerInventory: false,
        rules: _rules,
      ),
    );
    if (result is ErrorResult) {
      ctx.log.warn('Could not open the schedule menu: ${(result as ErrorResult).value}');
      return;
    }
    openMenus[player.getId().asString] = ScheduleMenu(player.getId().asString);
    await fillPlayerMirror(player);
  }

  // -- Entity interaction: `ScheduleItemEntityInteraction` ---------------------------------

  Future<PlayerInteractEntityEventData> _onInteractEntity(Server server, PlayerInteractEntityEventData e) async {
    if (e.cancelled || e.action != EntityInteractionAction.interact) return e;
    final player = e.player;
    if (player.getGamemode() == GameMode.spectator) return e;
    final lookup = ctx.services.find<ConductorSeatLookup>();
    if (lookup == null) return e;
    final world = player.getWorld();
    final passenger = lookup.passengerOf(world.getId(), e.entityId);
    if (passenger == null || !passenger.living) return e;
    if (player.isOnCooldown(group: scheduleItemKey)) return e;

    final held = player.getInventory().getItemInHand(hand: Hand.right);
    final heldIsSchedule = await _isSchedule(held);
    if (heldIsSchedule) {
      final schedule = ScheduleItem.getSchedule(held!.customComponent(trainScheduleComponent));
      final outcome = ScheduleItem.handScheduleTo(schedule, passenger);
      if (outcome != HandScheduleOutcome.pass) {
        await _handOutcome(player, world, held, outcome);
        player.startCooldown(group: scheduleItemKey, durationTicks: scheduleCooldownTicks);
        return e.cancel();
      }
    }

    final handEmpty = held == null || await held.getCount() <= 0;
    final click = interactWithConductor(passenger, handEmpty: handEmpty);
    switch (click.outcome) {
      case ConductorClickOutcome.ignore:
        return e;
      case ConductorClickOutcome.resumed:
        _sound(player, world, 'confirm');
        _overlay(player, 'create.schedule.continued');
        player.startCooldown(group: scheduleItemKey, durationTicks: scheduleCooldownTicks);
        return e.cancel();
      case ConductorClickOutcome.denyHeldItem:
        _sound(player, world, 'deny');
        _overlay(player, 'create.schedule.remove_with_empty_hand');
        return e.cancel();
      case ConductorClickOutcome.returned:
        _itemPickupSound(player, world);
        _overlay(
          player,
          click.wasAuto ? 'create.schedule.auto_removed_from_train' : 'create.schedule.removed_from_train',
        );
        final tag = click.returned;
        if (tag != null) await _placeBack(player, world, tag);
        player.startCooldown(group: scheduleItemKey, durationTicks: scheduleCooldownTicks);
        return e.cancel();
    }
  }

  Future<void> _handOutcome(Player player, World world, ItemStack held, HandScheduleOutcome outcome) async {
    switch (outcome) {
      case HandScheduleOutcome.pass:
      case HandScheduleOutcome.success:
        break;
      case HandScheduleOutcome.nonControllingSeat:
        _overlay(player, 'create.schedule.non_controlling_seat');
        _sound(player, world, 'deny');
      case HandScheduleOutcome.removeWithEmptyHand:
        _sound(player, world, 'deny');
        _overlay(player, 'create.schedule.remove_with_empty_hand');
      case HandScheduleOutcome.noStops:
        _sound(player, world, 'deny');
        _overlay(player, 'create.schedule.no_stops');
      case HandScheduleOutcome.applied:
        TrainFx.effects.awardAdvancement(player.getId().asString, _conductorAdvancement);
        _sound(player, world, 'confirm');
        _overlay(player, 'create.schedule.applied_to_train');
        final count = await held.getCount();
        if (count <= 1) {
          await player.setItemInHand(hand: Hand.right, stack: null);
        } else {
          await held.setCount(count: count - 1);
          await player.setItemInHand(hand: Hand.right, stack: held);
        }
    }
  }

  /// `player.getInventory().placeItemBackInInventory(schedule item)`.
  Future<void> _placeBack(Player player, World world, CTag tag) async {
    final stack = ItemStack.create(registryKey: scheduleItemKey, count: 1);
    stack.setCustomComponent(trainScheduleComponent, NetworkNbt.encode(tag.toNbt()));
    final storage = player.getInventory().asInventory();
    final size = storage.getSize();
    for (var i = 0; i < size; i++) {
      if (storage.getItem(slot: i) != null) continue;
      await storage.setItem(slot: i, item: stack);
      return;
    }
    final (x, y, z) = player.getPosition();
    await world.dropItem((x, y, z), stack);
  }

  // -- Payloads ---------------------------------------------------------------------------------

  /// `ScheduleEditPacket.handle(sender)`.
  Future<void> _onConfigureSchedule(Player player, Map<String, Object?> fields) async {
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    if (!await _isSchedule(held)) return;
    final packet = ScheduleEditPacket.fromFields(fields);
    final component = packet.scheduleComponent();
    if (component == null) {
      try {
        held!.removeCustomComponent(trainScheduleComponent);
      } on Object {
        // nothing to remove
      }
    } else {
      held!.setCustomComponent(trainScheduleComponent, NetworkNbt.encode(component.toNbt()));
    }
    await player.setItemInHand(hand: Hand.right, stack: held);
    player.startCooldown(group: scheduleItemKey, durationTicks: scheduleCooldownTicks);
  }

  /// `TrainEditPacket.Serverbound.handle(sender)`.
  void _onConfigureTrain(PayloadBus bus, Map<String, Object?> fields) {
    final reply = TrainEditPacket.fromFields(fields).handleServer();
    if (reply == null) return;
    bus.sendClientboundAll('create:s_configure_train', bus.roster.players, reply.toFields());
  }

  /// `Events.menuSlotChanged` of the schedule screen: the player inventory mirror is written back
  /// to the real inventory, and a click on a ghost slot becomes the menu's ghost inventory
  /// (`GhostItemMenu.clicked`).
  Future<void> _onMenuSlotChanged(
    Player player,
    MenuSlotChangedEventData e,
  ) async {
    final menu = openMenus[player.getId().asString];
    if (menu == null) return;
    for (final change in e.changes) {
      if (await applyPlayerMirrorChange(player, change)) continue;
      final slot = scheduleLayout.ghostIndexAt(change.slot);
      if (slot == null) continue;
      menu.setGhost(slot, await HostItemStacks.fromHost(change.stack, _ids));
    }
  }

  /// `GhostItemSubmitPacket.handle(player)` for the schedule menu.
  void _onSubmitGhostItem(Player player, Map<String, Object?> fields) {
    final menu = openMenus[player.getId().asString];
    if (menu == null) return;
    final item = fields['item'] as ItemStackData? ?? ItemStackData.empty;
    final slot = fields['slot'] as int;
    if (!menu.setGhost(slot, item)) return;
    final stack = HostItemStacks.toHost(item, _ids);
    unawaited(setMenuSlot(player, scheduleGhostSlot(slot), stack));
  }

  // -- Feedback ---------------------------------------------------------------------------------

  void _overlay(Player player, String key) {
    player.sendSystemMessage(
      text: TextComponent.translate(key: key, with_: const []),
      overlay: true,
    );
  }

  /// `AllSoundEvents.X.playOnServer(level, pos, 1, 1)`.
  void _sound(Player player, World world, String name) {
    final (x, y, z) = player.getPosition();
    final pos = (x.floor(), y.floor(), z.floor());
    final sounds = ctx.services.find<CreateSounds>();
    if (sounds != null) {
      sounds.playAtBlock(world, pos, name);
      return;
    }
    world.playCustomSound(
      soundName: 'create:$name',
      category: SoundCategory.blocks,
      pos: (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
      volume: 1,
      pitch: 1,
    );
  }

  /// `AllSoundEvents.playItemPickup(player)`.
  void _itemPickupSound(Player player, World world) {
    final (x, y, z) = player.getPosition();
    world.playSound(
      sound: Sound.entityItemPickup,
      category: SoundCategory.players,
      pos: (x, y, z),
      volume: 0.2,
      pitch: 1 + _random.nextDouble(),
    );
  }

  static final _random = Random();
}
