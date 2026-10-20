// The wired element of the docking connector, as Simulated sees it.
//
// Java's interface extends CC's `WiredElement` and the `Impl` holds a
// `WiredNode` made by `ComputerCraftAPI.createWiredNodeForElement`; the element
// joins the two connectors' wired networks while they are docked. The Dart CC
// plugin (`example/cc_tweaked`) has no wired network: it implements the
// peripheral API, monitors, modems, turtles and redstone, but not
// `WiredElement`/`WiredNode`/`WiredElementCapability`. So the port has the
// interface and the noop implementation only, and [createDockingConnectorWiredElement]
// always returns the noop — see `docs/PHASE_7B_GAPS.md`.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.wired.DockingConnectorWiredElement:8-21

import 'noop_docking_connector_wired_element.dart';

/// `DockingConnectorWiredElement`: what the docking connector needs from a wired
/// element (the rest of CC's `WiredElement` is the network's business).
abstract interface class SimWiredElement {
  /// `connect(other)`: joins the two elements' networks.
  void connect(SimWiredElement other);

  /// `disconnect(other)`.
  void disconnect(SimWiredElement other);

  /// `remove`: leaves the network for good.
  void remove();
}

/// `DockingConnectorWiredElement.CC_LOADED`: whether the real element can be
/// built. False in the port, because the Dart CC plugin has no wired network.
const bool ccWiredElementAvailable = false;

/// `DockingConnectorWiredElement.create(blockEntity)`.
///
/// Java returns [DockingConnectorWiredElementImpl] when CC is loaded and the
/// noop otherwise; the port has no implementation to return, so this is always
/// the noop. The wiring still exists, so a host with a wired network only has
/// to supply its own [SimWiredElement] and swap this factory.
SimWiredElement createDockingConnectorWiredElement() => const NoopDockingConnectorWiredElement();
