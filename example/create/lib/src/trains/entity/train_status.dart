// `TrainStatus` (pure): the chat messages a train sends its owner about navigation, drivers and
// the track. Messages are queued and delivered on the next tick the owner is online.
import '../../common/pos.dart';
import '../../redstone/support/text.dart' show Txt;
import 'train.dart';
import 'train_level.dart';

/// `ChatFormatting.GRAY` / `GOLD`.
const int _gray = 0xAAAAAA;
const int _gold = 0xFFAA00;

/// `TrainStatus.StatusMessage`: components shown one per line.
final class StatusMessage {
  final List<Txt> messages;

  const StatusMessage(this.messages);

  void displayToPlayer(String playerUuid) {
    for (final m in messages) {
      TrainFx.effects.sendSystemMessage(playerUuid, m);
    }
  }
}

class TrainStatus {
  final Train train;

  bool navigation = false;
  bool track = false;
  bool conductor = false;

  final List<StatusMessage> queued = [];

  TrainStatus(this.train);

  void failedNavigation() {
    if (navigation) return;
    displayInformation('no_path', false);
    navigation = true;
  }

  void failedNavigationNoTarget(String filter) {
    if (navigation) return;
    displayInformation('no_match', false, [filter]);
    navigation = true;
  }

  void failedPackageNoTarget(String address) {
    if (navigation) return;
    displayInformation('no_package_target', false, [address]);
    navigation = true;
  }

  void successfulNavigation() {
    if (!navigation) return;
    displayInformation('navigation_success', true);
    navigation = false;
  }

  void foundConductor() {
    if (!conductor) return;
    displayInformation('found_driver', true);
    conductor = false;
  }

  void missingConductor() {
    if (conductor) return;
    displayInformation('missing_driver', false);
    conductor = true;
  }

  void missingCorrectConductor() {
    if (conductor) return;
    displayInformation('opposite_driver', false);
    conductor = true;
  }

  void manualControls() {
    displayInformation('paused_for_manual', true);
  }

  void failedMigration() {
    if (track) return;
    displayInformation('track_missing', false);
    track = true;
  }

  void highStress() {
    if (track) return;
    displayInformation('coupling_stress', false);
    track = true;
  }

  void doublePortal() {
    if (track) return;
    displayInformation('double_portal', false);
    track = true;
  }

  void endOfTrack() {
    if (track) return;
    displayInformation('end_of_track', false);
    track = true;
  }

  void crash() {
    final component = Txt.literal(' - ').withColor(_gray).append(
      Txt.translate('create.train.status.collision').withColor(0xFFD3B4),
    );
    final messages = <Txt>[component];
    for (final key in train.getPresentDimensions()) {
      final where = train.getPositionInDimension(key);
      messages.add(
        Txt.literal(' - ').withColor(_gray).append(
          Txt.translate('create.train.status.collision.where', [
            Txt.literal(key),
            Txt.literal(where == null ? '' : where.toShortString()),
          ]).withColor(0xFFD3B4),
        ),
      );
    }
    addMessage(StatusMessage(messages));
  }

  void successfulMigration() {
    if (!track) return;
    displayInformation('back_on_track', true);
    track = false;
  }

  void trackOK() {
    track = false;
  }

  void tick(TrainLevel level) {
    if (queued.isEmpty) return;
    final owner = train.getOwner(level);
    if (owner == null) return;
    TrainFx.effects.sendSystemMessage(
      owner,
      Txt.translate('create.train.status', [train.name]).withColor(_gold),
    );
    for (final message in queued) {
      message.displayToPlayer(owner);
    }
    queued.clear();
  }

  /// `displayInformation(key, itsAGoodThing, args)`: [args] are strings or [Txt]s.
  void displayInformation(String key, bool itsAGoodThing, [List<Object> args = const []]) {
    final component = Txt.literal(' - ').withColor(_gray).append(
      Txt.translate('create.train.status.$key', [
        for (final a in args) a is Txt ? a : Txt.literal('$a'),
      ]).withColor(itsAGoodThing ? 0xD5ECC2 : 0xFFD3B4),
    );
    addMessage(StatusMessage([component]));
  }

  void addMessage(StatusMessage message) {
    queued.add(message);

    if (queued.length > 3) queued.removeAt(0);
  }

  void newSchedule() {
    navigation = false;
    conductor = false;
  }
}
