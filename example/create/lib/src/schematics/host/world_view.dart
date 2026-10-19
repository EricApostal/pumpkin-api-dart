// The real world as the printer sees it, and the placement of schematic blocks.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../common/nbt_convert.dart';
import '../schematic_hooks.dart';
import '../schematic_printer.dart';
import '../../core/nbt.dart';

/// [PrinterTargetView] over a host [World].
final class HostPrinterView implements PrinterTargetView {
  final World world;
  final HostBlockGetter _getter;
  final SchematicHooks hooks;

  HostPrinterView(this.world, this.hooks) : _getter = HostBlockGetter(world);

  static final Map<int, bool> _conductors = {};
  static final Map<int, double> _hardness = {};

  @override
  bool isLoaded(Pos p) => world.isLoaded(pos: p.toBlockPos());

  @override
  bool isWithinWorldBorder(Pos p) {
    try {
      return world.getBorder().containsPos(pos: p.center);
    } on Object {
      return true;
    }
  }

  @override
  BState stateAt(Pos p) => _getter.stateAt(p);

  @override
  String? blockEntityTypeAt(Pos p) => hooks.blockEntityTypeOf(stateAt(p).key);

  @override
  double destroySpeed(BState state) {
    final id = stateIdOf(state);
    if (id == null) return 1;
    return _hardness.putIfAbsent(id, () => BlockRegistry.stateFromId(id)?.hardness ?? 1);
  }

  @override
  bool isRedstoneConductor(BState state) {
    final id = stateIdOf(state);
    if (id == null) return false;
    return _conductors.putIfAbsent(id, () {
      final s = BlockRegistry.stateFromId(id);
      return s != null && s.isFullCube && s.isSolidBlock && !s.isLiquid;
    });
  }

  @override
  bool isWater(Pos p) => _getter.isWater(p);
}

/// `BlockHelper.prepareBlockEntityData` (without Create's NBT processors): the data that may be
/// placed with a block. Blocks tagged `create:safe_nbt` keep everything, registered writers filter,
/// everything else places without data.
List<int>? prepareBlockEntityData(SchematicHooks hooks, BState state, List<int>? nbt) {
  if (nbt == null) return null;
  final writer = hooks.safeNbtWriters[state.key];
  if (writer != null) return writer(state, nbt);
  if (Tags.block(state.key, 'create:safe_nbt')) return nbt;
  return null;
}

/// `BlockHelper.placeSchematicBlock`: places [state] at [target] with the block entity [data].
/// Returns false when nothing was placed.
Future<bool> placeSchematicBlock(
  World world,
  SchematicHooks hooks,
  BState state,
  Pos target, {
  List<int>? data,
}) async {
  final existing = world.getBlockEntityNbt(pos: target.toBlockPos());
  final filter = hooks.stateFilters[state.key];
  if (filter != null) state = filter(existing, state);

  // Piston, waterlogging, composter, cauldrons
  state = state.setValue('extended', 'false').setValue('waterlogged', 'false');
  if (state.key == 'minecraft:composter') state = const BState('minecraft:composter', {'level': '0'});
  if (BlockStates.isTag(stateIdOf(state) ?? 0, 'minecraft:cauldrons')) state = const BState('minecraft:cauldron', {});

  // Water in the nether: it evaporates.
  final dimension = world.getDimension();
  if (dimension.contains('nether') && (state.key == 'minecraft:water' || state.flag('waterlogged'))) {
    world.playCustomSound(
      soundName: 'minecraft:block.fire.extinguish',
      category: SoundCategory.blocks,
      pos: target.center,
      volume: 0.5,
      pitch: 2.6,
    );
    return false;
  }

  final id = stateIdOf(state);
  if (id == null) return false;
  final isBelt = state.key == 'create:belt';
  final flags = isBelt
      ? <BlockFlagsFlag>{BlockFlagsFlag.notifyListeners}
      : <BlockFlagsFlag>{BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate};

  BlockPlacementChange change;
  final typeKey = hooks.blockEntityTypeOf(state.key);
  if (data != null && typeKey != null && state.key.startsWith('create:')) {
    // A plugin block entity: its data is read by the Dart entity.
    final parsed = BinaryNbt.read(data);
    if (parsed != null && parsed.root.kind == NbtKind.compound) {
      final m = {...parsed.root.asCompound}
        ..remove('x')
        ..remove('y')
        ..remove('z')
        ..remove('id');
      change = BlockPlacementChange(
        target.toBlockPos(),
        id,
        pluginBlockEntityType: typeKey,
        pluginBlockEntitySave: valueToTree(NbtValue.compound(m)),
      );
    } else {
      change = BlockPlacementChange(target.toBlockPos(), id);
    }
  } else {
    change = BlockPlacementChange(target.toBlockPos(), id, blockEntityNbt: data);
  }
  await world.placeBlocks([change], flags: flags);
  return true;
}
