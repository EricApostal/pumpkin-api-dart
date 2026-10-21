// The seam on the CC: Tweaked side: Simulated's peripherals as CC peripherals.
//
// `simulated` declares what a computer sees (`SimPeripheral`, `SimComputerAccess`
// in `example/simulated/lib/src/api/sim_peripheral.dart`) and never imports this
// package; this file is the thin adapter, and it is the only place that knows
// both sides. The dependency therefore points cc_tweaked -> simulated, which is
// the reverse of the Java direction (there, `simulated/compat/computercraft`
// implements CC's `IPeripheral`). The reason is the constraint the Java code
// cannot have: `simulated` must load, and be tested, without CC installed.
//
// This file is the adapter only, and it imports nothing that needs the host, so
// a VM test can load it. The other half of the compat, the driver that finds
// the block entities around a computer and attaches their peripherals, is split
// the same way: `simulated_attach.dart` (which side sees which neighbour, and
// the attach/detach rules, driven by the tests) and `simulated_driver.dart`
// (the same over `SimulatedHost`, which imports the host and is not).
//
// Java: dev.simulated_team.simulated.compat.computercraft.AttachedComputerHandler
//       and NeoForgeSimPeripheralService (the capability registration).
//
// `simulated` does not export these from its barrel yet (the barrel also
// carries the content, which a VM test cannot load).
// ignore_for_file: implementation_imports
import 'package:simulated/src/api/sim_peripheral.dart' as sim;
import 'package:simulated/src/compat/computercraft/computer_craft_peripherals.dart' as compat;
import 'package:simulated/src/compat/computercraft/sim_peripheral_registry.dart' show SimPeripheralRegistry;

import '../lua/lua.dart' show LuaError;
import '../machine/peripheral.dart';

/// A CC peripheral backed by a Simulated one.
final class SimulatedPeripheral implements Peripheral {
  /// The peripheral on the Simulated side.
  final sim.SimPeripheral device;

  /// The seam wrapper of each computer, by identity, so that `attach` and
  /// `detach` see the same [sim.SimComputerAccess] and a block entity that
  /// broadcasts events keeps reaching the right computer.
  final Map<PeripheralAccess, _SimAccess> _accesses = Map<PeripheralAccess, _SimAccess>.identity();

  SimulatedPeripheral(this.device);

  _SimAccess _access(PeripheralAccess computer) =>
      _accesses.putIfAbsent(computer, () => _SimAccess(computer));

  @override
  String get type => device.type;

  @override
  Set<String> get additionalTypes => device.additionalTypes;

  @override
  List<String> get methodNames => device.methodNames;

  @override
  List<Object?> call(PeripheralAccess computer, String method, List<Object?> args) {
    try {
      return device.call(_access(computer), method, args);
    } on sim.SimPeripheralException catch (e) {
      // The peripheral reports the argument and state errors CC would raise.
      throw LuaError.message(e.message);
    }
  }

  @override
  void attach(PeripheralAccess computer) => device.attach(_access(computer));

  @override
  void detach(PeripheralAccess computer) {
    final access = _accesses.remove(computer);
    if (access != null) device.detach(access);
  }

  @override
  bool sameAs(Peripheral other) => other is SimulatedPeripheral && device.sameAs(other.device);
}

/// `IComputerAccess` over a [PeripheralAccess].
final class _SimAccess implements sim.SimComputerAccess {
  final PeripheralAccess _computer;

  _SimAccess(this._computer);

  @override
  int get computerId => _computer.computerId;

  @override
  String get attachmentName => _computer.attachmentName;

  @override
  void queueEvent(String name, List<Object?> args) => _computer.queueEvent(name, args);
}

/// The registration of Simulated's peripherals with this package.
abstract final class CcSimulatedPeripherals {
  /// The registrations of `ComputerCraftPeripherals.init`.
  static final SimPeripheralRegistry registry = SimPeripheralRegistry();

  static bool _installed = false;

  /// The adapter of a block entity per side, so that re-attaching the same
  /// block entity does not look like a different device (`sameAs`).
  static Expando<Map<String?, SimulatedPeripheral>> _adapters = Expando<Map<String?, SimulatedPeripheral>>();

  /// Registers Simulated's peripherals with this package. Idempotent, and
  /// harmless when the Simulated plugin is not loaded: no block entity is then
  /// ever found around a computer.
  static void install() {
    if (_installed) return;
    compat.ComputerCraftPeripherals.init(registry);
    _installed = true;
  }

  /// Forgets the registrations and the cached adapters (plugin unload).
  static void uninstall() {
    registry.clear();
    _adapters = Expando<Map<String?, SimulatedPeripheral>>();
    _installed = false;
  }

  /// The peripheral of [blockEntity] of type [typeKey], as [direction] sees it,
  /// or `null` when Simulated has none for it.
  ///
  /// The adapter of a block entity is created once: the same entity on the same
  /// side always answers with the same object, so `Peripheral.sameAs` holds
  /// across a re-attach (the Java side gets that from NeoForge's capability
  /// cache).
  static SimulatedPeripheral? peripheralFor(Object blockEntity, String typeKey, {String? direction}) {
    install();
    final bySide = _adapters[blockEntity] ??= <String?, SimulatedPeripheral>{};
    final existing = bySide[direction];
    if (existing != null) return existing;

    final device = registry.peripheralFor(typeKey, blockEntity, direction: direction);
    if (device == null) return null;
    return bySide[direction] = SimulatedPeripheral(device);
  }
}
