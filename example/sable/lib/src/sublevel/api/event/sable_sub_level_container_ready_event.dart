// `dev.ryanhcode.sable.api.event.SableSubLevelContainerReadyEvent`: fired when
// a level's sub-level container finished initialization.
//
// The plugin creates one container per loaded level (see `plugin/sable_plugin.dart`);
// it fires this event once the container is initialized and registered, so other
// plugins (Simulated's assembler, Create's contraptions) can attach to a level
// that is ready to hold sub-levels. In Java the event is a NeoForge bus event;
// here the listeners are a list the plugin iterates, and `SablePlatform`
// subscribers still see it through `onSubLevelContainerReady`.
//
// Pure: no host imports.
import '../../host/sub_level_host.dart';
import '../../model/sub_level_container.dart';
import '../../platform/sable_platform.dart';

/// `onSubLevelContainerReady(level, container)`.
typedef SableSubLevelContainerReadyEvent = void Function(
  SableLevel level,
  SubLevelContainer container,
);

final List<SableSubLevelContainerReadyEvent> _listeners = [];

/// Registers [listener] for every container that becomes ready from now on.
void addSubLevelContainerReadyListener(SableSubLevelContainerReadyEvent listener) =>
    _listeners.add(listener);

/// Removes a listener registered with [addSubLevelContainerReadyListener].
void removeSubLevelContainerReadyListener(SableSubLevelContainerReadyEvent listener) =>
    _listeners.remove(listener);

/// Fires the event for [container] of [level].
///
/// Called once per level, after the container was initialized and registered.
/// Also notifies the installed [SablePlatform], which is how a host-side
/// subscriber (the physics tick hooks) sees it in Java.
void fireSubLevelContainerReady(SableLevel level, SubLevelContainer container) {
  sablePlatform.onSubLevelContainerReady(level);
  for (final listener in _listeners.toList()) {
    listener(level, container);
  }
}
