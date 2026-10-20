// The registry of peripherals, keyed by block entity type.
//
// Java has a service interface (`SimPeripheralService`) and one loader-specific
// implementation (`NeoForgeSimPeripheralService`) that turns each registration
// into a NeoForge capability. A Dart plugin has one implementation and no
// `ServiceLoader`, so this is a plain object: the host calls [peripheralFor]
// with the block entity it found next to a computer, and gets a peripheral or
// `null`.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.service.compat.SimPeripheralService:12-44 and
//       dev.simulated_team.simulated.neoforge.service.compat.NeoForgeSimPeripheralService:17-51

import '../../api/sim_peripheral.dart';
import 'wired/docking_connector_wired_element.dart';

/// `CapabilityGetter<T, IPeripheral>`: the peripheral of [blockEntity] seen
/// from [direction], or `null` when it has none on that side.
typedef SimPeripheralGetter = SimPeripheral? Function(Object blockEntity, String? direction);

/// `CapabilityGetter<T, WiredElement>`.
typedef SimWiredElementGetter = SimWiredElement? Function(Object blockEntity, String? direction);

/// `NeoForgeSimPeripheralService`: the registrations, in the order they were
/// added.
final class SimPeripheralRegistry {
  final Map<String, List<SimPeripheralGetter>> _peripherals = {};
  final Map<String, List<SimWiredElementGetter>> _wired = {};

  /// `addPeripheral`: registers [getter] for the block entity type [typeKey].
  void addPeripheral(String typeKey, SimPeripheralGetter getter) {
    (_peripherals[typeKey] ??= []).add(getter);
  }

  /// `addWired`.
  void addWired(String typeKey, SimWiredElementGetter getter) {
    (_wired[typeKey] ??= []).add(getter);
  }

  /// The peripheral of the block entity [blockEntity] of type [typeKey], or
  /// `null` when no registration applies (or the one that does returns `null`
  /// for [direction], as the docking connector does on its facing side).
  ///
  /// The getters check the entity themselves: [typeKey] is the host's word for
  /// what the entity is, and a getter that receives something else returns
  /// `null` rather than throwing.
  SimPeripheral? peripheralFor(String typeKey, Object blockEntity, {String? direction}) {
    for (final getter in _peripherals[typeKey] ?? const <SimPeripheralGetter>[]) {
      final peripheral = getter(blockEntity, direction);
      if (peripheral != null) return peripheral;
    }
    return null;
  }

  /// The wired element of the block entity [blockEntity] of type [typeKey].
  SimWiredElement? wiredFor(String typeKey, Object blockEntity, {String? direction}) {
    for (final getter in _wired[typeKey] ?? const <SimWiredElementGetter>[]) {
      final element = getter(blockEntity, direction);
      if (element != null) return element;
    }
    return null;
  }

  /// Whether [typeKey] has a peripheral registered.
  bool hasPeripheral(String typeKey) => _peripherals.containsKey(typeKey);

  /// Whether [typeKey] has a wired element registered.
  bool hasWired(String typeKey) => _wired.containsKey(typeKey);

  /// The block entity types with a peripheral, in registration order.
  Iterable<String> get peripheralTypes => _peripherals.keys;

  /// The block entity types with a wired element, in registration order.
  Iterable<String> get wiredTypes => _wired.keys;

  /// Drops every registration (the plugin does this on unload).
  void clear() {
    _peripherals.clear();
    _wired.clear();
  }
}
