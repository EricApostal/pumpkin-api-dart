// `dev.ryanhcode.sable.api.event.SableSubLevelContainerReadyEvent`: fired when
// a level's sub-level container finished initialization.
//
// Pure: no host imports.
import '../../host/sub_level_host.dart';
import '../../model/sub_level_container.dart';

/// `onSubLevelContainerReady(level, container)`.
typedef SableSubLevelContainerReadyEvent = void Function(
  SableLevel level,
  SubLevelContainer container,
);
