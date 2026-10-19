// The block entities of the decoration module: copycat, placard, sliding door and steam whistle.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/contraption/transformable.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../contraptions/core/nbt_map.dart';
import '../core/block_entity.dart';
import 'copycat.dart';
import 'door.dart';
import 'door_host.dart';
import 'materials.dart';
import 'runtime.dart';
import 'whistle.dart';

// -- Items in NBT ----------------------------------------------------------------------------

/// `TransferUtil.saveItem` for a plain item (no components): `{id, count}`; empty is `{}`.
NbtCompound saveItemKey(String? key, [int count = 1]) {
  final c = NbtCompound();
  if (key != null && key != 'minecraft:air') {
    c.putString('id', key);
    c.putInt('count', count);
  }
  return c;
}

/// `TransferUtil.parseItem`: the item key of a `{id, count}` compound, or `null` for empty.
String? parseItemKey(NbtCompound? c) {
  final id = c?.getString('id');
  if (id == null || id == 'minecraft:air') return null;
  return id;
}

NbtCompound _stateToNbt(BState s) {
  final c = NbtCompound()..putString('Name', s.key);
  if (s.props.isNotEmpty) {
    final p = NbtCompound();
    s.props.forEach(p.putString);
    c.putCompound('Properties', p);
  }
  return c;
}

BState? _stateFromNbt(NbtCompound? c) {
  final name = c?.getString('Name');
  if (c == null || name == null) return null;
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

// -- Copycat ---------------------------------------------------------------------------------

/// `CopycatBlockEntity`: the block the copycat imitates and the item that was used up for it.
final class CopycatBlockEntity extends CreateBlockEntity {
  static const String type = 'create:copycat';

  CopycatBlockEntity(super.worldId, super.pos);

  BState _material = const BState(copycatBaseKey);

  /// The key of the item (`minecraft:stone`) that gave the material, `null` for none.
  String? _consumedItem;

  BState get material => _material;

  String? get consumedItem => _consumedItem;

  bool get hasCustomMaterial => _material.key != copycatBaseKey;

  /// `setMaterial`: adopts the exact state of a neighbouring identical copycat that already holds the
  /// same block (so orientations match), then syncs to the clients.
  void setMaterial(BState blockState) {
    final w = world;
    if (w != null && _material.key != blockState.key) {
      final level = HostBlockGetter(w);
      final here = this.pos.toPos();
      final wrapper = level.stateAt(here);
      for (final side in d.Direction.values) {
        final n = here.relative(side);
        if (level.stateAt(n) != wrapper) continue;
        final other = store.typed<CopycatBlockEntity>(worldId, n.toBlockPos());
        if (other == null) continue;
        final otherMaterial = other._material;
        if (otherMaterial.key != blockState.key) continue;
        blockState = otherMaterial;
        break;
      }
    }
    _material = blockState;
    sendData();
  }

  /// `cycleMaterial`: turns the material to its next orientation.
  bool cycleMaterial() {
    final next = copycatCycleMaterial(_material, stateExists);
    if (next == null) return false;
    setMaterial(next);
    return true;
  }

  void setConsumedItem(String? itemKey) {
    _consumedItem = itemKey;
    markDirty();
  }

  /// `clearContent`.
  void clearContent() {
    _material = const BState(copycatBaseKey);
    _consumedItem = null;
    sendData();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    _consumedItem = parseItemKey(tag.getCompound('Item'));
    final material = _stateFromNbt(tag.getCompound('Material'));
    if (material == null) {
      _consumedItem = null;
      return;
    }
    _material = material;
    if (clientPacket) return;
    // Validate the material against the item it was made from (`getAcceptedBlockState`).
    final item = _consumedItem;
    final candidate = item == null ? null : materialCandidateOfItem(item);
    final accepted = candidate == null
        ? null
        : copycatAcceptedState(
            candidate,
            isAcceptedRegardless: (m) => false,
            valid: stateExists,
            checkShape: false,
          );
    if (accepted != null && material.key == accepted.key) return;
    // Panels also accept bars and trapdoors (`isAcceptedRegardless`).
    if (candidate != null &&
        (isBarsMaterial(candidate.defaultState) ||
            isTrapdoorMaterial(candidate.defaultState)) &&
        material.key == candidate.defaultState.key) {
      return;
    }
    _consumedItem = null;
    _material = const BState(copycatBaseKey);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putCompound('Item', saveItemKey(_consumedItem));
    tag.putCompound('Material', _stateToNbt(_material));
  }
}

/// Transforms the `{Name, Properties}` block state stored under [key] in [nbt] like a moved
/// contraption does. Both `CopycatBlockEntity` and `BracketedBlockEntityBehaviour` store their
/// state in that form.
void _transformStateInPlace(
  NbtMap nbt,
  String key,
  StructureTransform transform,
) {
  final compound = nbt.getCompoundOrNull(key);
  if (compound == null) return;
  final name = compound.getString('Name');
  if (name.isEmpty) return;
  final props = <String, String>{};
  final properties = compound.getCompoundOrNull('Properties');
  if (properties != null) {
    for (final property in properties.keys) {
      final value = properties.getString(property);
      if (value.isNotEmpty) props[property] = value;
    }
  }
  final transformed = transform.applyState(BState(name, props));
  final out = NbtMap()..putString('Name', transformed.key);
  if (transformed.props.isNotEmpty) {
    final outProperties = NbtMap();
    transformed.props.forEach(outProperties.putString);
    out.putCompound('Properties', outProperties);
  }
  nbt.putCompound(key, out);
}

/// `CopycatBlockEntity.transform`: the material follows a contraption that rotates or mirrors it.
void registerCopycatTransform() {
  MovedBlockTransformerRegistries.registerBlockEntity(
    CopycatBlockEntity.type,
    (nbt, transform) => _transformStateInPlace(nbt, 'Material', transform),
  );
}

/// `BracketedBlockEntityBehaviour.transformBracket`: the bracket follows a moved contraption.
/// The type keys are the block entities that carry the behaviour (shafts/cogwheels and pipes).
void registerBracketTransform() {
  for (final type in const [
    'create:simple_kinetic',
    'create:fluid_pipe',
    'create:encased_fluid_pipe',
    'create:glass_fluid_pipe',
  ]) {
    MovedBlockTransformerRegistries.registerBlockEntity(
      type,
      (nbt, transform) => _transformStateInPlace(nbt, 'Bracket', transform),
    );
  }
}

// -- Placard ---------------------------------------------------------------------------------

/// `PlacardBlockEntity`: the item shown on the placard and the ticks the redstone output stays on.
final class PlacardBlockEntity extends CreateBlockEntity {
  static const String type = 'create:placard';

  PlacardBlockEntity(super.worldId, super.pos);

  String? heldItem;
  int poweredTicks = 0;

  void setHeldItem(String? key) {
    heldItem = key;
    sendData();
  }

  @override
  void tick() {
    super.tick();
    if (poweredTicks == 0) return;
    poweredTicks--;
    if (poweredTicks > 0) return;
    final w = world;
    if (w == null) return;
    final here = this.pos.toPos();
    final state = HostBlockGetter(w).stateAt(here);
    if (state.key != 'create:placard') return;
    // `level.setBlock(pos, state.setValue(POWERED, false), UPDATE_ALL)` then `updateNeighbours`.
    setBlockState(w, here, state.setFlag('powered', false)).then((_) async {
      await updatePlacardNeighbours(w, here, state);
    });
    sendData();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    poweredTicks = tag.getInt('PoweredTicks') ?? 0;
    heldItem = parseItemKey(tag.getCompound('Item'));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('PoweredTicks', poweredTicks);
    tag.putCompound('Item', saveItemKey(heldItem));
  }
}

/// `PlacardBlock.updateNeighbours`: updates the placard and the block it hangs on.
Future<void> updatePlacardNeighbours(World world, Pos pos, BState state) async {
  await world.notifyNeighbors(pos.toBlockPos());
  final face = state['face'];
  final connected = switch (face) {
    'ceiling' => d.Direction.down,
    'floor' => d.Direction.up,
    _ => state.dir('facing'),
  };
  if (connected != null)
    await world.notifyNeighbors(pos.relative(connected.opposite).toBlockPos());
}

// -- Sliding door ----------------------------------------------------------------------------

/// `SlidingDoorBlockEntity`: only the lower half has one. It keeps the door's animation clock so
/// the block model comes back once the closing animation is over.
final class SlidingDoorBlockEntity extends CreateBlockEntity
    implements DoorDeferrable {
  static const String type = 'create:sliding_door';

  SlidingDoorBlockEntity(super.worldId, super.pos);

  late final SlidingDoorAnimation _animation = SlidingDoorAnimation(
    open: _isOpen(),
  );

  @override
  bool get deferUpdate => _animation.deferUpdate;

  set deferUpdate(bool v) => _animation.deferUpdate = v;

  bool _isOpen() {
    final w = world;
    if (w == null) return false;
    return HostBlockGetter(w).stateAt(this.pos.toPos()).flag('open');
  }

  @override
  void onLoad() {
    super.onLoad();
    // Touch the animation so it starts from the door's current state.
    _animation;
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;
    final here = this.pos.toPos();
    final rt = DecorationHost.rt;
    if (_animation.deferUpdate) {
      _animation.deferUpdate = false;
      slidingDoorNeighborChange(rt, w, here, sourceIsSameBlock: false);
    }
    final state = HostBlockGetter(w).stateAt(here);
    if (!slidingDoorKeys.contains(state.key)) return;
    final open = state.flag('open');
    final visible = state.has('visible') ? state.flag('visible') : true;
    if (_animation.tick(open: open, visible: visible)) {
      // `showBlockModel`
      setBlockState(w, here, state.setFlag('visible', true));
      rt.playSound(w, here, doorCloseSound, volume: .5);
    }
  }
}

// -- Steam whistle ---------------------------------------------------------------------------

/// `WhistleBlockEntity`: the pitch comes from the extensions stacked above the whistle.
final class WhistleBlockEntity extends CreateBlockEntity {
  static const String type = 'create:steam_whistle';

  WhistleBlockEntity(super.worldId, super.pos);

  int pitch = 0;

  @override
  bool get syncsToClient => true;

  /// `updatePitch`.
  void updatePitch() {
    final w = world;
    if (w == null) return;
    final newPitch = whistlePitchAt(HostBlockGetter(w), this.pos.toPos());
    if (pitch == newPitch) return;
    pitch = newPitch;
    sendData();
  }

  /// `getPitchId`.
  int pitchId(String size) => whistlePitchId(pitch, size);

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    pitch = tag.getInt('Pitch') ?? 0;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('Pitch', pitch);
  }
}

/// The spec list for registration.
List<BlockEntityTypeSpec> decorationBlockEntityTypes() => [
  BlockEntityTypeSpec(
    key: CopycatBlockEntity.type,
    validBlocks: const ['create:copycat_panel', 'create:copycat_step'],
    create: CopycatBlockEntity.new,
    tickInterval: 0,
  ),
  BlockEntityTypeSpec(
    key: PlacardBlockEntity.type,
    validBlocks: const ['create:placard'],
    create: PlacardBlockEntity.new,
    tickInterval: 1,
  ),
  BlockEntityTypeSpec(
    key: SlidingDoorBlockEntity.type,
    validBlocks: const [
      'create:train_door',
      'create:framed_glass_door',
      'create:andesite_door',
      'create:brass_door',
      'create:copper_door',
    ],
    create: SlidingDoorBlockEntity.new,
    tickInterval: 1,
  ),
  BlockEntityTypeSpec(
    key: WhistleBlockEntity.type,
    validBlocks: const ['create:steam_whistle'],
    create: WhistleBlockEntity.new,
    tickInterval: 0,
  ),
];
