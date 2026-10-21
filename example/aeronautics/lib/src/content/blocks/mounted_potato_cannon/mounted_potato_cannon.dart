// The mounted potato cannon: a kinetic cannon that fires Create's potato
// projectiles along its facing.
//
// Java: `content/blocks/mounted_potato_cannon/{MountedPotatoCannonBlock,
// MountedPotatoCannonBlockEntity,MountedPotatoCannonInventory}`.
//
// A shaft spins the cannon up; with ammo in its slot it charges over
// `64 * reload_ticks / |speed|` ticks, and a redstone signal fires it. The barrel
// is blocked when a collider sits in front of it (a mangrove trapdoor in front of
// a blocked barrel lets the shot through, which is how the cannon is sealed), and
// each shot applies the recoil to the sub-level the cannon rides.
//
// The state machine and the ammo slot are pure
// ([MountedPotatoCannonLogic], [MountedPotatoCannonInventory], in
// `mounted_potato_cannon_logic.dart`); the block entity below is the host glue.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/conveyance/nbt_names.dart' show enumNbtName;
import 'package:create/src/equipment/potato/potato_model.dart' show PotatoType, PotatoTypes;
import 'package:create/src/kinetics/kinetic_block_entity.dart';
import 'package:create/src/manifest/registries.g.dart' show kPotatoProjectileTypes;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../aeronautics_hooks.dart';
import 'mounted_potato_cannon_logic.dart';

/// The block and block entity key.
const String mountedPotatoCannonKey = 'aeronautics:mounted_potato_cannon';

/// `MountedPotatoCannonBlockEntity`.
final class MountedPotatoCannonBlockEntity extends KineticBlockEntity {
  MountedPotatoCannonBlockEntity(super.worldId, super.pos);

  /// The pure state machine.
  final MountedPotatoCannonLogic logic = MountedPotatoCannonLogic();

  /// The ammo slot.
  final MountedPotatoCannonInventory inventory = MountedPotatoCannonInventory();

  /// The projectile types, from Create's data (`PotatoTypes`).
  PotatoTypes get potatoTypes => _potatoTypes ??= PotatoTypes([
    for (final t in kPotatoProjectileTypes) PotatoType.fromJson(t.key, t.rawJson),
  ]);
  static PotatoTypes? _potatoTypes;

  /// The state of the block as plain data.
  BState get bState {
    final w = world;
    if (w == null) return BState.air;
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
  }

  /// `getAimingVector`: the facing, as a unit vector.
  (double, double, double) get aimingVector {
    final dir = bState.dir('facing') ?? Direction.north;
    return (dir.stepX.toDouble(), dir.stepY.toDouble(), dir.stepZ.toDouble());
  }

  @override
  void initialize() {
    super.initialize();
    inventory.readMap({}, potatoTypes);
    logic.resetAndUpdate(hasAmmo: inventory.ammo != null, reloadTicks: inventory.ammo?.type.reloadTicks ?? 0);
  }

  @override
  void tick() {
    super.tick();

    final trapdoor = _trapdoorInFront();
    if (logic.tick(speed: speed, powered: bState.flag('powered'), trapdoorInFront: trapdoor)) {
      _fire(trapdoor);
    }

    final blocked = _raycastBlocked();
    if (blocked != logic.blocked) {
      logic.blocked = blocked;
      sendData();
    }
  }

  /// The block the cannon faces is a mangrove trapdoor (`Blocks.MANGROVE_TRAPDOOR
  /// == state.getBlock()`).
  bool _trapdoorInFront() {
    final w = world;
    if (w == null) return false;
    final dir = bState.dir('facing') ?? Direction.north;
    final at = BlockPos(x: pos.x + dir.stepX, y: pos.y + dir.stepY, z: pos.z + dir.stepZ);
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: at)).key == 'minecraft:mangrove_trapdoor';
  }

  /// `updateBlockedState`: a collider within 0.65 to 1.15 blocks of the centre.
  bool _raycastBlocked() {
    final w = world;
    if (w == null) return false;
    final aim = aimingVector;
    final center = (pos.x + 0.5, pos.y + 0.5, pos.z + 0.5);
    final beginning = (
      center.$1 + aim.$1 * 0.65,
      center.$2 + aim.$2 * 0.65,
      center.$3 + aim.$3 * 0.65,
    );
    final end = (
      center.$1 + aim.$1 * 1.15,
      center.$2 + aim.$2 * 1.15,
      center.$3 + aim.$3 * 1.15,
    );

    final hit = w.rayTraceBlock(start: beginning, end: end, includeFluids: false);
    if (hit == null) {
      logic.blockedLength = 0;
      return false;
    }

    final length = _length(beginning, end);
    final traveled = _length(beginning, (hit.hitPos.$1, hit.hitPos.$2, hit.hitPos.$3));
    logic.blockedLength = (1 - traveled / length) + 3 / 16;
    return true;
  }

  /// `FIRING`: spawn one projectile per `type.split()`, then take the recoil.
  ///
  /// TODO(parity): `MountedPotatoCannonBlockEntity.java:163-200` spawns
  /// `AllEntityTypes.POTATO_PROJECTILE` with `aeronautics$setDamageMultiplier(2)`.
  /// Create's `PotatoHost._onEntityTick` removes any `create:potato_projectile`
  /// that its own `_live` map does not know, so a projectile spawned from here
  /// dies on its first tick until Create exposes a spawn seam; the shot is
  /// therefore consumed without an entity (see the port report).
  void _fire(bool trapdoor) {
    final ammo = inventory.ammo;
    if (ammo == null) return;

    inventory.extract(1);
    logic.applyRecoil(ammo.type.split);
    sendData();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('inventory', _inventoryTag());
    tag.putInt('ItemTimer', logic.itemTimer);
    tag.putDouble('ChargeTimer', logic.chargeTimer);
    // `State`: `state.name()`, the Java constant name
    // (`MountedPotatoCannonBlockEntity.java:297`).
    tag.putString('State', enumNbtName(logic.state.name));
    tag.putInt('BarrelTimer', logic.barrelTimer);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final inv = tag.getCompound('inventory');
    if (inv != null) {
      inventory
        ..item = inv.getString('item')
        ..count = inv.getInt('count') ?? 0
        ..projectileType = inventory.item == null ? null : potatoTypes.forItem(inventory.item!, inTag: Tags.item);
    }
    logic.readMap({
      'ChargeTimer': tag.getDouble('ChargeTimer'),
      'BarrelTimer': tag.getInt('BarrelTimer'),
      'ItemTimer': tag.getInt('ItemTimer'),
      'State': tag.getString('State'),
    });
  }

  NbtCompound _inventoryTag() {
    final compound = NbtCompound();
    final item = inventory.item;
    if (item != null) compound.putString('item', item);
    compound.putInt('count', inventory.count);
    return compound;
  }
}

/// `MountedPotatoCannonBlock`.
CreateBlock buildMountedPotatoCannonBlock() => CreateBlock(
  key: mountedPotatoCannonKey,
  properties: [
    CreateProps.facing,
    BlockProperty.boolean('axis_along_first_coordinate'),
    CreateProps.powered,
    BlockProperty.boolean('blocked'),
  ],
  defaultState: {'facing': 'north'},
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'copper',
  canOcclude: false,
  blockEntityType: mountedPotatoCannonKey,
  behavior: BlockBehavior(
    onUseWithItem: (server, e) async {
      final be = AeronauticsHooks.store?.at(e.targetWorld.getId(), e.pos);
      if (be is! MountedPotatoCannonBlockEntity) return BlockUseResult.tryEmptyHand;

      final held = e.item;
      final heldKey = await held.getRegistryKey();
      final type = be.potatoTypes.forItem(heldKey, inTag: Tags.item);
      final slot = be.inventory;

      if (type == null && slot.isEmpty) return BlockUseResult.tryEmptyHand;

      final inserted = slot.insert(type, heldKey, 16, apply: true);
      if (inserted > 0) {
        be.logic.resetAndUpdate(hasAmmo: true, reloadTicks: type!.reloadTicks);
        be.sendData();
        return BlockUseResult.success;
      }
      return BlockUseResult.tryEmptyHand;
    },
  ),
);

/// `Vec3` distance.
double _length((double, double, double) a, (double, double, double) b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2, dz = b.$3 - a.$3;
  return (dx * dx + dy * dy + dz * dz) == 0 ? 0 : _sqrt(dx * dx + dy * dy + dz * dz);
}

double _sqrt(double v) {
  var x = v;
  if (x <= 0) return 0;
  for (var i = 0; i < 32; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}