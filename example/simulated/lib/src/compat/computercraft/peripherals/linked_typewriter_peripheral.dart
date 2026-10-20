// The linked typewriter's peripheral: the keys that are pressed, and the
// computer that has to hear about a key being pressed.
//
// The peripheral forwards its own attach/detach to the block entity's
// [AttachedComputerHandler], which is what the typewriter broadcasts key events
// through (`LinkedTypewriterBlockEntity.computerHandler`).
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.LinkedTypewriterPeripheral

import '../../../api/sim_peripheral.dart';
import '../attached_computer_handler.dart';

/// What [LinkedTypewriterPeripheral] reads; the linked typewriter's block entity
/// implements it.
abstract interface class SimLinkedTypewriterSource {
  /// `LinkedTypewriterBlockEntity.getPressedKeys()`.
  List<int> get pressedKeys;

  /// `LinkedTypewriterBlockEntity.computerHandler`.
  AttachedComputerHandler get computerHandler;
}

/// `LinkedTypewriterPeripheral`: type `linked_typewriter`.
final class LinkedTypewriterPeripheral extends SimBlockPeripheral<SimLinkedTypewriterSource> {
  LinkedTypewriterPeripheral(super.blockEntity) {
    // `@LuaFunction public final List<Integer> getPressedKeyCodes()`. (LinkedTypewriterPeripheral.java:32-35)
    method('getPressedKeyCodes', (computer, args) => [
      [for (final key in blockEntity.pressedKeys) key.toDouble()],
    ]);
  }

  @override
  String get type => 'linked_typewriter';

  /// `attach`: the block entity hears the computer too.
  @override
  void attach(SimComputerAccess computer) {
    super.attach(computer);
    blockEntity.computerHandler.attach(computer);
  }

  /// `detach`.
  @override
  void detach(SimComputerAccess computer) {
    super.detach(computer);
    blockEntity.computerHandler.detach(computer);
  }
}
