// The wired element used when there is no wired network.
//
// Java: dev.simulated_team.simulated.compat.computercraft.wired.NoopDockingConnectorWiredElement:6-19

import 'docking_connector_wired_element.dart';

/// `NoopDockingConnectorWiredElement.INSTANCE`: does nothing, because there is
/// no wired network to join.
final class NoopDockingConnectorWiredElement implements SimWiredElement {
  const NoopDockingConnectorWiredElement();

  @override
  void connect(SimWiredElement other) {}

  @override
  void disconnect(SimWiredElement other) {}

  @override
  void remove() {}
}
