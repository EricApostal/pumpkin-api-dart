// The computers a block entity's peripheral is attached to, and the events it
// sends them.
//
// Java uses CC's `AttachedComputerSet`, which is a set of `IComputerAccess` plus
// `queueEvent`. The port keeps the same three operations over the seam's
// [SimComputerAccess], so a block entity can broadcast (a key press on the
// linked typewriter) without knowing which mod is listening.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.AttachedComputerHandler:9-21

import 'dart:collection';

import '../../api/sim_peripheral.dart';

/// `AttachedComputerHandler`.
final class AttachedComputerHandler {
  /// The attached computers, by identity (CC's set compares the access object).
  final Set<SimComputerAccess> _computers = LinkedHashSet<SimComputerAccess>.identity();

  /// `attach`: [computer] now sees this block entity.
  void attach(SimComputerAccess computer) => _computers.add(computer);

  /// `detach`: [computer] no longer sees it.
  void detach(SimComputerAccess computer) => _computers.remove(computer);

  /// `queueEvent`: sends [event] to every attached computer.
  void queueEvent(String event, [List<Object?> args = const []]) {
    // A listener may detach while the event is delivered; Java's set iterates a
    // copy for the same reason.
    for (final computer in List<SimComputerAccess>.of(_computers)) {
      computer.queueEvent(event, args);
    }
  }

  /// The computers currently attached, in attachment order.
  List<SimComputerAccess> get attachedComputers => List.unmodifiable(_computers);

  /// Whether any computer is attached.
  bool get isEmpty => _computers.isEmpty;
}
