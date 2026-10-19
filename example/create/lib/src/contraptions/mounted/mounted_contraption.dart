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

class MountedContraption extends Contraption {
  CartMovementMode rotationMode;
  MinecartRef? connectedCart;

  MountedContraption([this.rotationMode = CartMovementMode.rotate]);

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
    Direction? direction,
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
  bool customBlockPlacement(ContraptionLevel level, Pos pos, BState state) =>
      state.key == minecartAnchorKey;

  @override
  bool customBlockRemoval(ContraptionLevel level, Pos pos, BState state) =>
      state.key == minecartAnchorKey;

  @override
  bool canBeStabilized(Direction facing, Pos localPos) => true;

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
