// `CartAssembleRailType`: the rail a cart assembler pretends to be, and the rail block it places.
//
// Java: `content/contraptions/mounted/CartAssembleRailType`.
import '../../api/block_state.dart';

enum CartAssembleRailType {
  regular('regular', 'minecraft:rail'),
  poweredRail('powered_rail', 'minecraft:powered_rail'),
  detectorRail('detector_rail', 'minecraft:detector_rail'),
  activatorRail('activator_rail', 'minecraft:activator_rail'),
  controllerRail('controller_rail', 'create:controller_rail');

  const CartAssembleRailType(this.serializedName, this.blockKey);

  final String serializedName;
  final String blockKey;

  bool matches(BState rail) => rail.key == blockKey;

  static CartAssembleRailType byName(String? name) {
    for (final t in values) {
      if (t.serializedName == name) return t;
    }
    return poweredRail;
  }

  /// `getRailBlock`: the rail block with the assembler's shape and backwards flag.
  BState railState(BState assembler) {
    final shape = assembler['shape'] ?? 'north_south';
    return BState(blockKey, {
      'shape': shape,
      if (blockKey == 'create:controller_rail')
        'backwards': assembler['backwards'] ?? 'false',
    });
  }
}

/// `CartAssemblerBlock.CartAssemblerAction`.
enum CartAssemblerAction {
  assemble,
  disassemble,
  assembleAccelerate,
  disassembleBrake,
  assembleAccelerateDirectional,
  pass;

  bool get shouldAssemble =>
      this == assemble ||
      this == assembleAccelerate ||
      this == assembleAccelerateDirectional;

  bool get shouldDisassemble => this == disassemble || this == disassembleBrake;

  /// `getActionForCart(state, cart)`: [hasPassengers] is `!cart.getPassengers().isEmpty`.
  static CartAssemblerAction forCart(
    BState state, {
    bool hasPassengers = false,
  }) {
    final type = CartAssembleRailType.byName(state['rail_type']);
    final powered = state.flag('powered');
    return switch (type) {
      CartAssembleRailType.activatorRail => powered ? disassemble : pass,
      CartAssembleRailType.controllerRail =>
        powered ? assembleAccelerateDirectional : disassembleBrake,
      CartAssembleRailType.detectorRail =>
        hasPassengers ? disassemble : assembleAccelerate,
      CartAssembleRailType.poweredRail =>
        powered ? assembleAccelerate : disassembleBrake,
      CartAssembleRailType.regular => powered ? assemble : disassemble,
    };
  }
}
