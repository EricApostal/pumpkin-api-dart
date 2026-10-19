// The host side of the schematics: block entities of the schematic table and the schematicannon,
// their menus, the payload handlers and the creative placement.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, cursor, click rules) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../api/blocks.dart';
import '../../api/payloads.dart';
import '../../api/sounds.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../common/nbt_convert.dart';
import '../../contraptions/blocks/actuator_contract.dart' show ActuatorHosts;
import '../../contraptions/glue/super_glue_entity.dart' show collectCroppedGlue;
import '../../core/block_entity.dart';
import '../../core/byte_buf.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../core/pos.dart';
import '../../core/registry.dart' show RegistryKind;
import '../../infrastructure/config/create_configs.dart';
import '../checklist_stacks.dart';
import '../item_requirement.dart';
import '../launched_item.dart';
import '../material_checklist.dart';
import '../schematic_export.dart';
import '../schematic_hooks.dart';
import '../schematic_printer.dart';
import '../schematic_stack.dart';
import '../schematic_world.dart';
import '../schematicannon_core.dart';
import '../upload_receiver.dart';
import 'slot_stacks.dart';
import 'template_loader.dart';
import 'world_view.dart';

const String tableBlockEntityType = 'create:schematic_table';
const String cannonBlockEntityType = 'create:schematicannon';
const String tableMenuType = 'create:schematic_table';
const String cannonMenuType = 'create:schematicannon';

/// Everything the schematic block entities and handlers share.
final class SchematicsRuntime {
  static late SchematicsRuntime instance;

  final CreateContext ctx;
  final SchematicHooks hooks;
  final SchematicLoader loader;
  final SchematicUploadReceiver receiver;
  final CreateConfigs? configs;
  final PayloadBus? bus;
  final Logger log;

  /// uuid -> the menu the player has open.
  final Map<String, ({String type, String worldId, Pos pos})> openMenus = {};

  SchematicsRuntime({
    required this.ctx,
    required this.hooks,
    required this.loader,
    required this.receiver,
    required this.configs,
    required this.bus,
  }) : log = ctx.log;

  CreateSounds? get sounds => ctx.services.find<CreateSounds>();

  Player? playerByUuid(String uuid) {
    for (final p in bus?.roster.players ?? const <Player>[]) {
      try {
        if (p.getId().asString == uuid) return p;
      } on Object {
        // stale handle
      }
    }
    return null;
  }

  Player? playerByName(String name) {
    for (final p in bus?.roster.players ?? const <Player>[]) {
      try {
        if (p.getName() == name) return p;
      } on Object {
        // stale handle
      }
    }
    return null;
  }

  T? entityAt<T extends CreateBlockEntity>(String worldId, Pos pos) =>
      ctx.blockEntities.typed<T>(worldId, pos.toBlockPos());

  /// `ItemIdResolver` for the wire stacks.
  late final ItemIdResolver itemIds = HostItemStacks.resolverFor(() => ctx.ids);

  int? itemId(String key) => itemIds.idOf(key);

  // -- menus ---------------------------------------------------------------------------------

  /// Opens the menu of [be] (`player.openMenu(be, be::sendToMenu)`).
  Future<void> openMenu(
    Player player,
    CreateBlockEntity be,
    String type,
    int slotCount,
    MenuClickRules rules,
    TextComponent title,
  ) async {
    final client = NbtCompound();
    be.write(client, clientPacket: true);
    final extra = PacketBuffer.encode((w) {
      w.writeLong(packPos(be.pos.x, be.pos.y, be.pos.z));
      NetworkNbt.write(w, valueOfCompound(client));
    });
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: type,
      title: title,
      extraData: extra,
      slotCount: slotCount,
      options: MenuOptions(
        applyVanillaClicks: true,
        playerInventory: true,
        rules: rules,
      ),
    );
    if (result is ErrorResult) {
      log.warn(
        'Could not open the $type menu: ${(result as ErrorResult).value}',
      );
      return;
    }
    openMenus[player.getId().asString] = (
      type: type,
      worldId: be.worldId,
      pos: be.pos.toPos(),
    );
    if (be is _MenuHolder) await be.fillMenu(player);
  }

  /// Refreshes the slots of every viewer of [be].
  Future<void> refreshViewers(CreateBlockEntity be) async {
    if (be is! _MenuHolder) return;
    for (final e in openMenus.entries.toList()) {
      if (e.value.worldId != be.worldId || e.value.pos != be.pos.toPos())
        continue;
      final p = playerByUuid(e.key);
      if (p != null) await be.fillMenu(p);
    }
  }
}

/// A block entity with a menu.
mixin _MenuHolder on CreateBlockEntity {
  List<SlotStack> get slots;

  MenuClickRules get rules;

  Future<void> fillMenu(Player player) async {
    for (var i = 0; i < slots.length; i++) {
      final host = await HostSlotStacks.write(slots[i]);
      try {
        if (host == null) {
          player.clearPluginMenuSlot(i);
        } else {
          player.setPluginMenuSlot(i, host);
        }
      } on Object {
        // the menu closed meanwhile
      }
    }
    try {
      raw.menus.setMenuClickRules(player: player, rules: rules);
    } on Object {
      // closed
    }
  }

  /// A slot changed by vanilla clicks.
  void slotChangedByPlayer(int slot, SlotStack stack) => slots[slot] = stack;
}

NbtCompound _writeInventory(List<SlotStack> slots) {
  final items = <Object>[
    for (var i = 0; i < slots.length; i++)
      if (!slots[i].isEmpty) HostSlotStacks.toNbt(slots[i])..putInt('Slot', i),
  ];
  return NbtCompound()
    ..putInt('Size', slots.length)
    ..putList('Items', items);
}

void _readInventory(NbtCompound? c, List<SlotStack> slots) {
  for (var i = 0; i < slots.length; i++) {
    slots[i] = SlotStack.empty;
  }
  if (c == null) return;
  for (final e in c.getList('Items') ?? const <Object>[]) {
    if (e is! NbtCompound) continue;
    final slot = e.getInt('Slot');
    if (slot != null && slot >= 0 && slot < slots.length)
      slots[slot] = HostSlotStacks.fromNbt(e);
  }
}

// ============================================================================================
// Schematic table
// ============================================================================================

/// `SchematicTableBlockEntity`.
final class SchematicTableBlockEntity extends CreateBlockEntity
    with _MenuHolder
    implements UploadTarget {
  SchematicTableBlockEntity(super.worldId, super.pos);

  @override
  final List<SlotStack> slots = List.filled(2, SlotStack.empty);
  bool isUploading = false;
  String? uploadingSchematic;
  double uploadingProgress = 0;
  bool _sendUpdate = false;

  static const List<String> inputItems = [
    'create:empty_schematic',
    'create:schematic_and_quill',
    'create:schematic',
  ];

  @override
  MenuClickRules get rules => MenuClickRules(
    slotRules: [
      MenuSlotRule(
        slot: 0,
        kind: MenuSlotKindFilter(inputItems),
        maxStackSize: null,
      ),
      const MenuSlotRule(
        slot: 1,
        kind: MenuSlotKindOutputOnly(),
        maxStackSize: null,
      ),
    ],
    quickMoveTargets: const [MenuSlotRange(start: 0, end: 1)],
  );

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (!clientPacket) _readInventory(tag.getCompound('Inventory'), slots);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putCompound('Inventory', _writeInventory(slots));
    if (clientPacket && isUploading) {
      tag.putBool('Uploading', true);
      tag.putString('Schematic', uploadingSchematic ?? '');
      tag.putFloat('Progress', uploadingProgress);
    }
  }

  @override
  void tick() {
    super.tick();
    if (_sendUpdate) {
      _sendUpdate = false;
      sendData();
    }
  }

  @override
  void onRemoved() {
    super.onRemoved();
    unawaited(_dropContents());
  }

  Future<void> _dropContents() async {
    final w = world;
    if (w == null) return;
    for (final s in slots) {
      final host = await HostSlotStacks.write(s);
      if (host != null) await w.dropItem(this.pos.toPos().center, host);
    }
  }

  // UploadTarget
  @override
  void startUpload(String schematic) {
    isUploading = true;
    uploadingProgress = 0;
    uploadingSchematic = schematic;
    _sendUpdate = true;
    slots[0] = SlotStack.empty;
    markDirty();
    unawaited(SchematicsRuntime.instance.refreshViewers(this));
  }

  @override
  void progress(double fraction) {
    uploadingProgress = fraction;
    _sendUpdate = true;
  }

  @override
  void finishUpload() {
    isUploading = false;
    uploadingProgress = 0;
    uploadingSchematic = null;
    _sendUpdate = true;
  }

  @override
  void deliver(String schematic, String owner) {
    final rt = SchematicsRuntime.instance;
    final size = rt.loader.sizeOf(owner, schematic);
    final data = SchematicStackData.create(schematic, owner, bounds: size);
    slots[1] = SlotStack('create:schematic', 1, {
      for (final e in data.toComponents().entries)
        if (e.value != null) e.key: e.value!,
    });
    markDirty();
    unawaited(rt.refreshViewers(this));
  }

  @override
  bool get isValid => !removed;
}

// ============================================================================================
// Schematicannon
// ============================================================================================

/// `SchematicannonBlockEntity`.
final class SchematicannonBlockEntity extends CreateBlockEntity
    with _MenuHolder {
  SchematicannonBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 30;
  }

  final SchematicannonCore core = SchematicannonCore();
  bool hasCreativeCrate = false;
  final List<BlockDirection> _attached = [];
  bool _ticking = false;

  @override
  List<SlotStack> get slots => core.inventory;

  @override
  MenuClickRules get rules => MenuClickRules(
    slotRules: [
      const MenuSlotRule(
        slot: 0,
        kind: MenuSlotKindFilter(['create:schematic']),
        maxStackSize: null,
      ),
      const MenuSlotRule(
        slot: 1,
        kind: MenuSlotKindOutputOnly(),
        maxStackSize: null,
      ),
      const MenuSlotRule(
        slot: 2,
        kind: MenuSlotKindFilter([
          'create:clipboard',
          'minecraft:book',
          'minecraft:written_book',
        ]),
        maxStackSize: null,
      ),
      const MenuSlotRule(
        slot: 3,
        kind: MenuSlotKindOutputOnly(),
        maxStackSize: null,
      ),
      const MenuSlotRule(
        slot: 4,
        kind: MenuSlotKindFilter(['minecraft:gunpowder']),
        maxStackSize: null,
      ),
    ],
    quickMoveTargets: const [
      MenuSlotRange(start: 0, end: 1),
      MenuSlotRange(start: 2, end: 3),
      MenuSlotRange(start: 4, end: 5),
    ],
  );

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    _readInventory(tag.getCompound('Inventory'), core.inventory);
    core.statusMsg = tag.getString('Status') ?? 'idle';
    core.remainingFuel = tag.getInt('RemainingFuel') ?? 0;
    core.state = switch (tag.getString('State')) {
      'RUNNING' => CannonState.running,
      'PAUSED' => CannonState.paused,
      _ => CannonState.stopped,
    };
    core.blocksPlaced = tag.getInt('AmountPlaced') ?? 0;
    core.blocksToPlace = tag.getInt('AmountToPlace') ?? 0;
    core.schematicProgress = tag.getDouble('Progress') ?? 0;
    core.bookPrintingProgress = tag.getDouble('PaperProgress') ?? 0;
    final missing = tag.getCompound('MissingItem');
    if (missing != null) {
      final id = missing.getString('id');
      final count = missing.getInt('count') ?? 1;
      core.missingItem = id == null || count <= 0 ? null : SlotStack(id, count);
    } else {
      core.missingItem = null;
    }
    final o = tag.getCompound('Options');
    if (o != null) {
      core.replaceMode = o.getInt('replace_mode') ?? 2;
      core.skipMissing = o.getBool('skip_missing') ?? false;
      core.replaceBlockEntities = o.getBool('replace_block_entities') ?? false;
    }
    core.defaultYaw = tag.getDouble('DefaultYaw') ?? 0;
    final printer = tag.getCompound('Printer');
    if (printer != null) core.printer.fromTag(_printerMap(printer));
    core.flyingBlocks
      ..clear()
      ..addAll([
        for (final e in tag.getList('FlyingBlocks') ?? const <Object>[])
          if (e is NbtCompound) ?_launchedFromNbt(e),
      ]);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (!clientPacket) {
      tag.putCompound('Inventory', _writeInventory(core.inventory));
      if (core.state == CannonState.running) tag.putBool('Running', true);
    }
    // The Java client reads these with `getFloatOr`.
    tag.putFloat('Progress', core.schematicProgress);
    tag.putFloat('PaperProgress', core.bookPrintingProgress);
    tag.putInt('RemainingFuel', core.remainingFuel);
    tag.putString('Status', core.statusMsg);
    tag.putString('State', core.state.name.toUpperCase());
    tag.putInt('AmountPlaced', core.blocksPlaced);
    tag.putInt('AmountToPlace', core.blocksToPlace);
    final missing = core.missingItem;
    if (missing != null)
      tag.putCompound('MissingItem', HostSlotStacks.toClientNbt(missing));
    tag.putCompound(
      'Options',
      NbtCompound()
        ..putInt('replace_mode', core.replaceMode)
        ..putBool('skip_missing', core.skipMissing)
        ..putBool('replace_block_entities', core.replaceBlockEntities),
    );
    tag.putCompound('Printer', _printerNbt(core.printer));
    tag.putList('FlyingBlocks', [
      for (final f in core.flyingBlocks) ?_launchedToNbt(f),
    ]);
    tag.putFloat('DefaultYaw', core.defaultYaw);
  }

  // The tag floats above are written as floats in the client format; the save reads them back as doubles.

  @override
  void tick() {
    super.tick();
    if (_ticking) return;
    _ticking = true;
    unawaited(_run().whenComplete(() => _ticking = false));
  }

  Future<void> _run() async {
    final env = _CannonEnvImpl(this, SchematicsRuntime.instance);
    final before = core.inventory.map((s) => '$s').join('|');
    await core.tick(env);
    final after = core.inventory.map((s) => '$s').join('|');
    if (core.sendUpdate) {
      core.sendUpdate = false;
      sendData();
    }
    if (before != after) {
      markDirty();
      await SchematicsRuntime.instance.refreshViewers(this);
    }
  }

  @override
  void lazyTick() {
    super.lazyTick();
    unawaited(_findInventories());
  }

  /// A neighbour changed.
  void neighbourChanged() => core.neighbourCheckCooldown = 0;

  Future<void> _findInventories() async {
    final w = world;
    if (w == null) return;
    hasCreativeCrate = false;
    _attached.clear();
    for (final d in BlockDirection.values) {
      final np = this.pos.toPos().relative(d.toDirection());
      if (!w.isLoaded(pos: np.toBlockPos())) continue;
      if (w.getBlock(pos: np.toBlockPos()).name == 'create:creative_crate')
        hasCreativeCrate = true;
      final h = ItemHandlers.at(
        w,
        np.toBlockPos(),
        side: d.toDirection().opposite.toHost(),
      );
      if (h != null) _attached.add(d);
    }
  }

  @override
  void onRemoved() {
    super.onRemoved();
    unawaited(_dropContents());
  }

  Future<void> _dropContents() async {
    final w = world;
    if (w == null) return;
    for (final s in core.inventory) {
      final host = await HostSlotStacks.write(s);
      if (host != null) await w.dropItem(this.pos.toPos().center, host);
    }
  }
}

Map<String, Object?> _printerMap(NbtCompound c) {
  List<int>? posOf(NbtCompound c, String k) {
    final a = c.getIntArray(k);
    return a != null && a.length == 3 ? a : null;
  }

  return {
    'CurrentPos': posOf(c, 'CurrentPos'),
    'EntityProgress': c.getInt('EntityProgress') ?? 0,
    'PrintStage': c.getString('PrintStage') ?? 'BLOCKS',
    'DeferredBlocks': [
      for (final e in c.getList('DeferredBlocks') ?? const <Object>[])
        if (e is NbtCompound) posOf(e, 'Pos'),
    ],
  };
}

NbtCompound _printerNbt(SchematicPrinter p) {
  final t = p.toTag();
  final c = NbtCompound();
  final cp = t['CurrentPos'];
  if (cp is List<int>) c.putIntArray('CurrentPos', cp);
  final a = t['Anchor'];
  if (a is List<int>) c.putIntArray('Anchor', a);
  c.putInt('EntityProgress', t['EntityProgress']! as int);
  c.putString('PrintStage', t['PrintStage']! as String);
  c.putList('DeferredBlocks', [
    for (final d in t['DeferredBlocks']! as List<Object?>)
      NbtCompound()..putIntArray('Pos', (d as List).cast<int>()),
  ]);
  return c;
}

NbtCompound _stateNbt(BState s) {
  final c = NbtCompound()..putString('Name', s.key);
  if (s.props.isNotEmpty) {
    final p = NbtCompound();
    for (final e in s.props.entries) {
      p.putString(e.key, e.value);
    }
    c.putCompound('Properties', p);
  }
  return c;
}

BState? _stateFromNbt(NbtCompound c) {
  final name = c.getString('Name');
  if (name == null) return null;
  final props = <String, String>{};
  final p = c.getCompound('Properties');
  if (p != null) {
    for (final k in p.keys) {
      final v = p.getString(k);
      if (v != null) props[k] = v;
    }
  }
  return BState(name, props);
}

NbtCompound? _launchedToNbt(LaunchedItem l) {
  final c = NbtCompound()
    ..putInt('TotalTicks', l.totalTicks)
    ..putInt('TicksLeft', l.ticksRemaining)
    // `TransferUtil.saveItem`: an empty icon is an empty compound, not a placeholder item.
    ..putCompound(
      'Stack',
      l.stack.isEmpty ? NbtCompound() : HostSlotStacks.toClientNbt(l.stack),
    )
    ..putIntArray('Target', [l.target.$1, l.target.$2, l.target.$3]);
  switch (l) {
    case LaunchedBlock():
      c.putCompound('BlockState', _stateNbt(l.state));
      final data = l.data;
      if (data != null) {
        final parsed = BinaryNbt.read(data);
        if (parsed != null && parsed.root.kind == NbtKind.compound) {
          final m = {...parsed.root.asCompound}
            ..removeWhere(
              (k, _) => k == 'x' || k == 'y' || k == 'z' || k == 'id',
            );
          c.putCompound('Data', compoundOf(NbtValue.compound(m)));
        }
      }
    case LaunchedBelt():
      c.putCompound('BlockState', _stateNbt(l.state));
      c.putInt('Length', l.length);
      c.putIntArray('Casing', l.casings);
    case LaunchedEntity():
      // `ForEntity.serializeNBT`: the client needs the entity to render the flight, and the
      // server recreates it from this tag after a reload.
      final parsed = BinaryNbt.read(l.entity.withPosition(l.position));
      if (parsed != null && parsed.root.kind == NbtKind.compound) {
        c.putCompound('Entity', compoundOf(parsed.root));
      }
  }
  return c;
}

LaunchedItem? _launchedFromNbt(NbtCompound c) {
  final t = c.getIntArray('Target');
  if (t == null || t.length != 3) return null;
  final stackTag = c.getCompound('Stack');
  final stack = SlotStack(
    stackTag?.getString('id') ?? 'minecraft:air',
    stackTag?.getInt('count') ?? 0,
  );
  final total = c.getInt('TotalTicks') ?? 0, left = c.getInt('TicksLeft') ?? 0;
  final target = (t[0], t[1], t[2]);
  final stateTag = c.getCompound('BlockState');
  final state = stateTag == null ? null : _stateFromNbt(stateTag);
  if (c.containsKey('Length') && state != null) {
    final length = c.getInt('Length') ?? 0;
    final cas = c.getIntArray('Casing') ?? const <int>[];
    return LaunchedBelt(target, stack, total, left, state, length, [
      for (var i = 0; i < length; i++) i < cas.length ? cas[i] : 0,
    ]);
  }
  if (state != null) {
    List<int>? data;
    final d = c.getCompound('Data');
    if (d != null) data = BinaryNbt.write(valueOfCompound(d));
    return LaunchedBlock(target, stack, total, left, state, data);
  }
  final entity = c.getCompound('Entity');
  if (entity != null) {
    final data = BinaryNbt.write(valueOfCompound(entity));
    // `LaunchedItem.ForEntity` saves the entity with its `Pos`; the client and the reloaded
    // server both spawn it there.
    final posList = entity.getList('Pos') ?? const <Object>[];
    final position = posList.length == 3 && posList.every((v) => v is num)
        ? (
            (posList[0] as num).toDouble(),
            (posList[1] as num).toDouble(),
            (posList[2] as num).toDouble(),
          )
        : (target.$1 + 0.5, target.$2.toDouble(), target.$3 + 0.5);
    return LaunchedEntity(
      target,
      stack,
      total,
      left,
      SchematicEntity(position, target, data),
      position,
    );
  }
  return null;
}

/// The cannon's environment over the host.
final class _CannonEnvImpl implements CannonEnv {
  final SchematicannonBlockEntity be;
  final SchematicsRuntime rt;

  _CannonEnvImpl(this.be, this.rt);

  World get _world => be.world!;

  @override
  PrinterTargetView get view => HostPrinterView(_world, rt.hooks);

  @override
  Pos get cannonPos => be.pos.toPos();

  @override
  SchematicRequirements get requirements => rt.hooks.requirements;

  @override
  bool isBrittle(BState state) => rt.hooks.isBrittle(state);

  @override
  int get cannonDelay =>
      rt.configs?.server.schematics.schematicannonDelay.value ?? 10;

  @override
  int get shotsPerGunpowder =>
      rt.configs?.server.schematics.schematicannonShotsPerGunpowder.value ??
      400;

  @override
  bool get hasCreativeCrate => be.hasCreativeCrate;

  @override
  bool isClipboard(SlotStack stack) => stack.item == 'create:clipboard';

  @override
  bool isBlueprintItem(SlotStack stack) => stack.item == 'create:schematic';

  @override
  BlueprintLoad loadBlueprint(SlotStack blueprint) {
    final data = SchematicStackData.fromComponents(blueprint.components);
    if (data.anchor == null)
      return const BlueprintLoad(BlueprintStatus.invalid);
    if (data.deployed != true)
      return const BlueprintLoad(BlueprintStatus.notPlaced);
    final file = data.file, owner = data.owner;
    if (file == null || owner == null)
      return const BlueprintLoad(BlueprintStatus.invalid);
    try {
      final w = rt.loader.world(
        owner,
        file,
        data.anchor!,
        data.rotation,
        data.mirror,
      );
      if (w == null) return const BlueprintLoad(BlueprintStatus.expired);
      return BlueprintLoad(BlueprintStatus.ok, w);
    } on Object catch (e) {
      rt.log.error('Failed to load the schematic for printing: $e');
      return const BlueprintLoad(BlueprintStatus.errored);
    }
  }

  @override
  Future<void> findInventories() => be._findInventories();

  @override
  Future<bool> grabItems(
    StackRequirement required, {
    required bool simulate,
  }) async {
    if (be.hasCreativeCrate) return true;
    final w = be.world;
    if (w == null) return false;
    var found = 0;
    for (final d in List.of(be._attached)) {
      final np = be.pos.toPos().relative(d.toDirection());
      final h = ItemHandlers.at(
        w,
        np.toBlockPos(),
        side: d.toDirection().opposite.toHost(),
      );
      if (h == null) continue;
      for (var slot = 0; slot < h.slotCount(); slot++) {
        final peek = h.take(slot, 1, simulate: true);
        if (peek == null) continue;
        if (await peek.getRegistryKey() != required.item) continue;
        if (required.usage == ItemUseType.damage) {
          final comps = await peek.getComponents();
          int? maxDamage;
          var damage = 0;
          for (final c in comps) {
            if (c.component == DataComponent.maxDamage)
              maxDamage = _varInt(c.value);
            if (c.component == DataComponent.damage) damage = _varInt(c.value);
          }
          if (maxDamage == null) continue;
          if (!simulate) {
            final taken = h.take(slot, 1);
            if (taken != null) {
              if (damage + 1 <= maxDamage) {
                await taken.setComponent(
                  component: DataComponent.damage,
                  value: PacketBuffer.encode((w) => w.writeVarInt(damage + 1)),
                );
                await h.insertStack(taken);
              }
            }
          }
          return true;
        }
        final want = required.count - found;
        final taken = h.take(slot, want, simulate: simulate);
        if (taken != null) found += await taken.getCount();
        if (found >= required.count) return true;
      }
    }
    return required.usage == ItemUseType.consume && found >= required.count;
  }

  static int _varInt(List<int> bytes) => PacketReader(bytes).readVarInt();

  @override
  Future<bool> takeExternalGunpowder() async {
    final w = be.world;
    if (w == null) return false;
    for (final d in List.of(be._attached)) {
      final np = be.pos.toPos().relative(d.toDirection());
      final h = ItemHandlers.at(
        w,
        np.toBlockPos(),
        side: d.toDirection().opposite.toHost(),
      );
      if (h == null) continue;
      for (var slot = 0; slot < h.slotCount(); slot++) {
        final peek = h.take(slot, 1, simulate: true);
        if (peek == null ||
            await peek.getRegistryKey() != 'minecraft:gunpowder')
          continue;
        if (h.take(slot, 1) != null) return true;
      }
    }
    return false;
  }

  @override
  Future<List<SlotStack>> attachedStacks() async {
    final w = be.world;
    final out = <SlotStack>[];
    if (w == null) return out;
    for (final d in List.of(be._attached)) {
      final np = be.pos.toPos().relative(d.toDirection());
      final h = ItemHandlers.at(
        w,
        np.toBlockPos(),
        side: d.toDirection().opposite.toHost(),
      );
      if (h == null) continue;
      for (var slot = 0; slot < h.slotCount(); slot++) {
        if (h.take(slot, 1, simulate: true) == null) continue;
        out.add(
          await HostSlotStacks.read(
            h.getStack(slot: slot),
            vanillaComponents: false,
          ),
        );
      }
    }
    return out;
  }

  @override
  void playFiringSound() => _sound('schematicannon_launch_block');

  @override
  void playFinishSound() => _sound('schematicannon_finish');

  void _sound(String name) {
    final w = be.world;
    if (w == null) return;
    rt.sounds?.playAtBlock(w, be.pos.toPos(), name);
  }

  @override
  void scheduleWaterTick(Pos pos) =>
      be.world?.scheduleFluidFlow(pos.toBlockPos(), delayTicks: 5);

  @override
  Future<void> place(LaunchedItem item) async {
    final w = be.world;
    if (w == null) return;
    switch (item) {
      case LaunchedBlock():
        await placeSchematicBlock(
          w,
          rt.hooks,
          item.state,
          item.target,
          data: item.data,
        );
      case LaunchedBelt():
        await _placeBelt(w, item);
      case LaunchedEntity():
        final p = item.position;
        await w.spawnFromNbt(
          item.entity.withPosition(p, blockPos: item.target),
          p,
        );
    }
  }

  Future<void> _placeBelt(World w, LaunchedBelt item) async {
    final state = item.state;
    final isStart = state['part'] == 'start';
    final offset = nextBeltSegment(state, posZero, isStart) ?? posZero;
    final i = item.length - 1;
    final axis = state['slope'] == 'sideways'
        ? Axis.y
        : (Direction.byName(state['facing'] ?? 'north') ?? Direction.north)
              .clockWise
              .axis;
    await setBlockState(
      w,
      item.target,
      BState('create:shaft', {
        'axis': axis.serializedName,
        'waterlogged': 'false',
      }),
    );
    final hooks = rt.hooks.beltHooks;
    if (hooks == null) return; // the kinetics module connects the belts
    final end = item.target.offset(offset.$1 * i, offset.$2 * i, offset.$3 * i);
    await hooks.createBelts(w.getId(), item.target, end);
    for (var seg = 0; seg < item.length; seg++) {
      if (item.casings[seg] == 0) continue;
      await hooks.setCasing(
        w.getId(),
        item.target.offset(offset.$1 * seg, offset.$2 * seg, offset.$3 * seg),
        item.casings[seg],
      );
    }
  }

  @override
  List<int>? prepareBlockEntityData(BState state, List<int>? nbt) =>
      prepareBlockEntityData_(rt.hooks, state, nbt);

  @override
  Future<SlotStack> createChecklistStack(
    MaterialChecklist checklist, {
    required bool clipboard,
  }) async {
    await _fillMaxDamage(checklist);
    final name = PacketBuffer.encode((w) => w.writeNbt(checklistName()));
    if (clipboard) {
      final content = clipboardContent(checklist, rt.itemId);
      return SlotStack('create:clipboard', 1, {
        'create:clipboard_content': content,
        'custom-name': name,
      });
    }
    return SlotStack('minecraft:written_book', 1, {
      'written-book-content': writtenBookContent(checklist),
      'custom-name': name,
    });
  }

  /// `new ItemStack(item).getMaxDamage()` of the damage requirements: the checklist turns the
  /// required damage into a number of items with it.
  Future<void> _fillMaxDamage(MaterialChecklist checklist) async {
    if (checklist.damageRequired.isEmpty) return;
    final maxDamage = <String, int>{};
    for (final item in checklist.damageRequired.keys) {
      try {
        final stack = ItemStack.create(registryKey: item, count: 1);
        for (final c in await stack.getComponents()) {
          if (c.component == DataComponent.maxDamage) {
            maxDamage[item] = _varInt(c.value);
          }
        }
      } on Object {
        // an item the host does not know; the default of 1 applies
      }
    }
    checklist.maxDamageOf = (item) => maxDamage[item] ?? 1;
  }
}

List<int>? prepareBlockEntityData_(
  SchematicHooks hooks,
  BState state,
  List<int>? nbt,
) => prepareBlockEntityData(hooks, state, nbt);

// ============================================================================================
// Menus and packets
// ============================================================================================

/// Registers the menu events and payload handlers.
void installSchematicHandlers(SchematicsRuntime rt) {
  final ctx = rt.ctx;
  ctx.listen(Events.menuSlotChanged, (
    Server server,
    MenuSlotChangedEventData e,
  ) async {
    if (e.menuType != tableMenuType && e.menuType != cannonMenuType) return;
    final open = rt.openMenus[e.player.getId().asString];
    if (open == null) return;
    final be = rt.ctx.blockEntities.at(open.worldId, open.pos.toBlockPos());
    if (be is! _MenuHolder) return;
    for (final c in e.changes) {
      if (c.slot < 0 || c.slot >= be.slots.length) continue;
      be.slotChangedByPlayer(c.slot, await HostSlotStacks.read(c.stack));
    }
    be.markDirty();
    await rt.refreshViewers(be);
  });
  ctx.listen(Events.menuClosed, (Server server, MenuClosedEventData e) {
    if (e.menuType == tableMenuType || e.menuType == cannonMenuType)
      rt.openMenus.remove(e.player.getId().asString);
  });
  ctx.listen(
    Events.playerLeave,
    (Server server, PlayerLeaveEventData e) =>
        rt.openMenus.remove(e.player.getId().asString),
  );
  ctx.listen(
    Events.serverTickEnd,
    (Server server, ServerTickEndEventData e) => rt.receiver.tick(),
  );

  final bus = rt.bus;
  if (bus == null) {
    rt.log.warn('No payload bus: schematic uploads and the cannon GUI are off');
    return;
  }
  bus.onServerbound(
    'create:upload_schematic',
    (player, f) => _onUpload(rt, player, f),
  );
  bus.onServerbound(
    'create:place_schematic',
    (player, f) => unawaited(_onPlace(rt, player, f)),
  );
  bus.onServerbound(
    'create:sync_schematic',
    (player, f) => unawaited(_onSync(rt, player, f)),
  );
  bus.onServerbound(
    'create:instant_schematic',
    (player, f) => unawaited(_onInstant(rt, player, f)),
  );
  bus.onServerbound('create:configure_schematicannon', (player, f) {
    final open = rt.openMenus[player.getId().asString];
    if (open == null || open.type != cannonMenuType) return;
    final be = rt.entityAt<SchematicannonBlockEntity>(open.worldId, open.pos);
    if (be == null) return;
    final opt = f['option'] as int;
    if (opt < 0 || opt >= CannonOption.values.length) return;
    be.core.configure(CannonOption.values[opt], f['set'] as bool);
    be.sendData();
  });
}

void _onUpload(SchematicsRuntime rt, Player player, Map<String, Object?> f) {
  final code = f['code'] as int;
  final schematic = f['schematic'] as String? ?? '';
  final name = player.getName();
  if (code == 0) {
    final open = rt.openMenus[player.getId().asString];
    if (open == null || open.type != tableMenuType) return;
    final table = rt.entityAt<SchematicTableBlockEntity>(
      open.worldId,
      open.pos,
    );
    final result = rt.receiver.handleNewUpload(
      name,
      schematic,
      f['size'] as int,
      table,
      onTooLarge: (a, b) {
        player.sendSystemMessage(
          text: TextComponent.text(plain: a),
          overlay: false,
        );
        player.sendSystemMessage(
          text: TextComponent.text(plain: b),
          overlay: false,
        );
      },
    );
    if (result == UploadResult.started) table?.sendData();
  } else if (code == 1) {
    final data = f['data'];
    if (data is Uint8List)
      rt.receiver.handleWriteRequest(name, schematic, data);
  } else if (code == 2) {
    rt.receiver.handleFinishedUpload(name, schematic);
  }
}

/// The custom components of a wire stack by key.
Map<String, List<int>> _wireComponents(SchematicsRuntime rt, Object? stack) {
  final out = <String, List<int>>{};
  if (stack is! ItemStackData) return out;
  for (final key in SchematicStackData.allKeys) {
    final id = rt.ctx.ids.of(RegistryKind.dataComponents, key);
    if (id == null) continue;
    for (final (cid, bytes) in stack.patch.added) {
      if (cid == id) out[key] = bytes;
    }
  }
  return out;
}

Future<void> _onPlace(
  SchematicsRuntime rt,
  Player player,
  Map<String, Object?> f,
) async {
  if (!player.isCreative) return;
  final stack = f['stack'];
  if (stack is! ItemStackData ||
      rt.itemIds.keyOf(stack.itemId) != 'create:schematic')
    return;
  final data = SchematicStackData.fromComponents(_wireComponents(rt, stack));
  if (data.anchor == null || data.file == null || data.owner == null) return;
  final world = player.getWorld();
  final schematic = rt.loader.world(
    data.owner!,
    data.file!,
    data.anchor!,
    data.rotation,
    data.mirror,
  );
  if (schematic == null) return;
  final printer = SchematicPrinter()
    ..requirements = rt.hooks.requirements
    ..isBrittle = rt.hooks.isBrittle
    ..load(schematic);
  final view = HostPrinterView(world, rt.hooks);
  final includeAir =
      rt.configs?.server.schematics.creativePrintIncludesAir.value ?? false;
  while (printer.advanceCurrentPos()) {
    if (!printer.shouldPlaceCurrent(view)) continue;
    final blocks = <(Pos, BState, List<int>?)>[];
    final entities = <SchematicEntity>[];
    printer.handleCurrentTarget(
      (pos, state, nbt) => blocks.add((pos, state, nbt)),
      (pos, e) => entities.add(e),
    );
    for (final (pos, state, nbt) in blocks) {
      if (state.isAir && !includeAir) continue;
      await placeSchematicBlock(
        world,
        rt.hooks,
        state,
        pos,
        data: prepareBlockEntityData_(rt.hooks, state, nbt),
      );
    }
    for (final e in entities) {
      final p = (
        e.relativePos.$1 + data.anchor!.$1,
        e.relativePos.$2 + data.anchor!.$2,
        e.relativePos.$3 + data.anchor!.$3,
      );
      final blockPos = (
        e.relativeBlockPos.$1 + data.anchor!.$1,
        e.relativeBlockPos.$2 + data.anchor!.$2,
        e.relativeBlockPos.$3 + data.anchor!.$3,
      );
      await world.spawnFromNbt(e.withPosition(p, blockPos: blockPos), p);
    }
  }
}

Future<void> _onSync(
  SchematicsRuntime rt,
  Player player,
  Map<String, Object?> f,
) async {
  final slot = f['slot'] as int;
  final inv = player.getInventory();
  final storage = inv.asInventory();
  final index = slot == -1 ? inv.getSelectedSlot() : slot;
  if (index < 0 || index >= storage.getSize()) return;
  final stack = storage.getItem(slot: index);
  if (stack == null || await stack.getRegistryKey() != 'create:schematic')
    return;
  final current = await HostSlotStacks.read(stack, vanillaComponents: false);
  final data = SchematicStackData.fromComponents(current.components).copyWith(
    deployed: f['deployed'] as bool,
    anchor: f['anchor'] as Pos,
    rotation: BlockRotation.values[(f['rotation'] as int).clamp(0, 3)],
    mirror: BlockMirror.values[(f['mirror'] as int).clamp(0, 2)],
    clearHash: true,
  );
  for (final e in data.toComponents().entries) {
    if (e.value == null) {
      stack.removeCustomComponent(e.key);
    } else {
      stack.setCustomComponent(e.key, e.value!);
    }
  }
  await storage.setItem(slot: index, item: stack);
}

Future<void> _onInstant(
  SchematicsRuntime rt,
  Player player,
  Map<String, Object?> f,
) async {
  final name = player.getName();
  final schematic = f['name'] as String;
  if (!SchematicUploadReceiver.isSafeName(name) ||
      !SchematicUploadReceiver.isSafeName(schematic)) {
    rt.log.warn(
      'Attempted Schematic Upload with path traversal: $name/$schematic',
    );
    return;
  }
  if (!schematic.endsWith('.nbt')) {
    rt.log.warn(
      'Attempted Schematic Upload with non-supported Format: $name/$schematic',
    );
    return;
  }
  final held = player.getInventory().asInventory().getItem(
    slot: player.getInventory().getSelectedSlot(),
  );
  if (held == null ||
      await held.getRegistryKey() != 'create:schematic_and_quill')
    return;
  if (!rt.receiver.makeRoom(name)) return;
  final origin = f['origin'] as Pos, bounds = f['bounds'] as Pos;
  final world = player.getWorld();
  final box = BlockBounds.fromCorners(origin, origin + bounds - (1, 1, 1));
  try {
    final saved = await StructureTemplates.save(
      world,
      box.minPos.toBlockPos(),
      box.maxPos.toBlockPos(),
    );
    // `SchematicAndQuillItem.replaceStructureVoidWithAir` and `clampGlueBoxes`.
    final area = box.toAabb();
    final glue = ActuatorHosts.glue;
    final cropped = glue == null
        ? const <Aabb>[]
        : collectCroppedGlue(glue.gluesIn(world.getId(), area), area);
    final bytes = prepareSchematicExport(
      saved,
      area: area,
      croppedGlueBoxes: cropped,
    );
    final file = rt.receiver.exportName(name, schematic, overwrite: true);
    rt.receiver.store.write(SchematicUploadReceiver.pathOf(name, file), bytes);
    final size = rt.loader.sizeOf(name, file);
    final data = SchematicStackData.create(file, name, bounds: size);
    final stack = ItemStack.create(registryKey: 'create:schematic', count: 1);
    for (final e in data.toComponents().entries) {
      if (e.value != null) stack.setCustomComponent(e.key, e.value!);
    }
    final inv = player.getInventory();
    await inv.asInventory().setItem(slot: inv.getSelectedSlot(), item: stack);
  } on Object catch (e) {
    rt.log.error('Instant schematic failed: $e');
    player.sendSystemMessage(
      text: TextComponent.text(
        plain: 'Schematic instant-upload failed, check logs for details',
      ),
      overlay: true,
    );
  }
}

/// Opens the menu of a table / cannon (the block's right click).
Future<void> openTableMenu(
  SchematicsRuntime rt,
  Player player,
  SchematicTableBlockEntity be,
) => rt.openMenu(
  player,
  be,
  tableMenuType,
  2,
  be.rules,
  TextComponent.translate(
    key: 'create.gui.schematicTable.title',
    with_: const [],
  ),
);

Future<void> openCannonMenu(
  SchematicsRuntime rt,
  Player player,
  SchematicannonBlockEntity be,
) => rt.openMenu(
  player,
  be,
  cannonMenuType,
  5,
  be.rules,
  TextComponent.translate(
    key: 'create.gui.schematicannon.title',
    with_: const [],
  ),
);
