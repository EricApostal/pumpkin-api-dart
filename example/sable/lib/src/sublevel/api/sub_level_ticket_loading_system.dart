// `dev.ryanhcode.sable.api.sublevel.SubLevelTicketLoadingSystem`: keeps the live
// `activeTickets` map in sync with the container's observers.
//
// Pure: no host imports.
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../storage/sub_level_removal_reason.dart';
import '../model/sub_level.dart';
import 'sub_level_observer.dart';

/// Manages the `activeTickets` map in [ServerSubLevelContainer].
final class SubLevelTicketLoadingSystem with SubLevelObserver {
  final ServerSubLevelContainer container;

  SubLevelTicketLoadingSystem(this.container);

  @override
  void onSubLevelAdded(SubLevel subLevel) {
    if (subLevel is! ServerSubLevel) return;
    final info = container.allTickets[subLevel.uniqueId];
    if (info != null && info.tickets.isNotEmpty) {
      container.activeTickets[subLevel] = {...info.tickets};
    }
  }

  @override
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) {
    if (subLevel is! ServerSubLevel) return;
    final uuid = subLevel.uniqueId;

    if (reason == SubLevelRemovalReason.unloaded) {
      container.activeTickets.remove(subLevel);
      final info = container.allTickets[uuid];
      if (info != null) {
        info.pointer = subLevel.getLastSerializationPointer();
      }
    } else if (reason == SubLevelRemovalReason.removed) {
      container.activeTickets.remove(subLevel);
      // Java drops the ticket here. The port keeps it unless the removal was an
      // explicit delete (`ServerSubLevelContainer.forgetTickets`, called by
      // `/sable remove`), because a ticket is the *only* pointer that can bring
      // the sub-level back: a transient failure on restore (a tracker that reads
      // empty for one tick, a plot whose chunks have not come back yet) would
      // otherwise delete the last way to load the ship, and leave nothing in the
      // log to say why. A kept ticket re-arms the force-load on the next start;
      // an explicitly deleted sub-level must not come back, so the delete path
      // clears it.
      if (!container.forgottenTickets.remove(uuid)) {
        final info = container.allTickets[uuid];
        if (info != null) info.pointer = subLevel.getLastSerializationPointer();
      } else {
        container.allTickets.remove(uuid);
      }
    }
  }
}
