// `MountedContraption`: the structure a cart assembler captures. The assembler block becomes a
// minecart anchor; the cart the assembler sits on becomes the entity's vehicle.
//
// Java: `content/contraptions/mounted/MountedContraption`.
import 'dart:collection';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../storage/stacks.dart';

/// `CartAssemblerBlockEntity.CartMovementMode`.
enum CartMovementMode {
  rotate('ROTATE'),
  rotatePaused('ROTATE_PAUSED'),
  rotationLocked('ROTATION_LOCKED');

  const CartMovementMode(this.javaName);

  final String javaName;

  static CartMovementMode byName(String? name) {
    for (final m in values) {
      if (m.javaName == name) return m;
    }
    return rotate;
  }
}

/// `CartAssemblerBlock.RAIL_SHAPE` / the anchor's axis.
const String cartAssemblerKey = 'create:cart_assembler';
const String minecartAnchorKey = 'create:minecart_anchor';

/// Hooks the host installs for a mounted contraption. Java asks the cart entity for its
/// `Container` (`cart instanceof Container`); the host only exposes entities by id and has no
/// entity container access, so [externalInventory] is `null` until it grows one.
abstract final class MountedContraptionHooks {
  /// The item handler of a cart entity (`ContainerItemHandler(container)`), `null` when the
  /// entity has no container.
  static ItemSlots? Function(Object cart)? externalInventory;
}

class MountedContraption extends Contraption {
  CartMovementMode rotationMode;
  MinecartRef? connectedCart;

  MountedContraption([this.rotationMode = CartMovementMode.rotate]);

  /// `rotationMode == ROTATION_LOCKED`: the cart keeps the contraption's orientation fixed.
  bool get rotationLocked => rotationMode == CartMovementMode.rotationLocked;

  /// `rotationMode == ROTATE_PAUSED`: the actors do not tick while the contraption rotates.
  bool get rotationPaused => rotationMode == CartMovementMode.rotatePaused;

  @override
  String get typeId => 'create:mounted';

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    final state = level.stateAt(pos);
    if (!state.has('shape')) return false;
    if (!searchMovedStructure(level, pos, null)) return false;

    final axis = state['shape'] == 'east_west' ? Axis.x : Axis.z;
    addBlock(
      level,
      pos,
      CapturedBlock(
        StructureBlockInfo(
          pos,
          BState(minecartAnchorKey, {'axis': axis.serializedName}),
        ),
        null,
      ),
    );

    return blocks.length != 1;
  }

  @override
  bool addToInitialFrontier(
    ContraptionLevel level,
    Pos pos,
    Direction? forcedDirection,
    Queue<Pos> frontier,
  ) {
    frontier.clear();
    frontier.add(pos.above);
    return true;
  }

  @override
  CapturedBlock capture(ContraptionLevel level, Pos pos) {
    final captured = super.capture(level, pos);
    if (captured.info.state.key != cartAssemblerKey) return captured;

    final state = captured.info.state;
    final anchorSwap = CapturedBlock(
      StructureBlockInfo(
        pos,
        BState(minecartAnchorKey, {
          'axis': state['shape'] == 'north_south' ? 'z' : 'x',
        }),
      ),
      captured.blockEntity,
    );
    if (pos == anchor || connectedCart != null) return anchorSwap;

    for (final axis in Axis.values) {
      if (axis.isVertical) continue;
      if (!VecHelper.onSameAxis(anchor, pos, axis)) continue;
      for (final cart in level.minecartsAt(pos)) {
        if (!cart.canAssemble) break;
        connectedCart = cart;
        level.moveMinecart(cart, (pos.$1 + .5, pos.$2.toDouble(), pos.$3 + .5));
      }
    }
    return anchorSwap;
  }

  @override
  bool movementAllowed(BState state, ContraptionLevel level, Pos pos) {
    if (pos != anchor && state.key == cartAssemblerKey) {
      return _testSecondaryCartAssembler(level, pos);
    }
    return super.movementAllowed(state, level, pos);
  }

  /// `testSecondaryCartAssembler`: another assembler only joins the structure when a cart that
  /// can be assembled sits on it, on the anchor's axis.
  bool _testSecondaryCartAssembler(ContraptionLevel level, Pos pos) {
    for (final axis in Axis.values) {
      if (axis.isVertical) continue;
      if (!VecHelper.onSameAxis(anchor, pos, axis)) continue;
      for (final cart in level.minecartsAt(pos)) {
        if (!cart.canAssemble) break;
        return true;
      }
    }
    return false;
  }

  @override
  bool customBlockPlacement(ContraptionLevel level, Pos pos, BState state) =>
      state.key == minecartAnchorKey;

  @override
  bool customBlockRemoval(ContraptionLevel level, Pos pos, BState state) =>
      state.key == minecartAnchorKey;

  @override
  bool canBeStabilized(Direction facing, Pos localPos) => true;

  /// `addExtraInventories(cart)`: the items of the container the riding cart carries (a chest or
  /// hopper minecart) join the contraption inventory. The host resolves the container
  /// ([MountedContraptionHooks.externalInventory]); without one nothing is attached.
  void addExtraInventories(Object? cart) {
    if (cart == null) return;
    final external = MountedContraptionHooks.externalInventory?.call(cart);
    if (external != null) storage.attachExternal(external);
  }

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putString('RotationMode', rotationMode.javaName);
    return tag;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    rotationMode = CartMovementMode.byName(nbt.getString('RotationMode'));
    super.readNbt(level, nbt, spawnData: spawnData);
  }
}
