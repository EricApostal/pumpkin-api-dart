// The `trains` module: Create's `content/trains` (tracks, bogeys, signals, observers, stations,
// schedules, the display boards, the carriage entities and the railway manager).
//
// The areas register themselves through the `register*` / `load*` functions of their folders; this
// class only runs them in the module phases (see `docs/ARCHITECTURE.md`).
import '../core/module.dart';
import '../core/registry.dart';
import 'bogey/bogey_registration.dart';
import 'display/display_registration.dart';
import 'entity/entity_registration.dart';
import 'entity/honk_packet.dart';
import 'entity/train_host.dart';
import 'entity/train_hud_packet.dart';
import 'entity/train_relocation_packet.dart';
import 'graph/graph_registration.dart';
import 'manager/manager_registration.dart';
import 'manager/train_map_sync.dart';
import 'observer/observer_registration.dart';
import 'schedule/schedule_registration.dart';
import 'signal/signal_registration.dart';
import 'station/station_edit_packet.dart';
import 'station/station_registration.dart';
import 'support/runtime.dart';
import 'track/curved_track_packets.dart';
import 'track/all_portal_tracks.dart';
import 'track/track_registration.dart';

final class TrainsModule extends CreateModule {
  @override
  String get name => 'trains';

  @override
  void register(CreateRegistry registry) {
    registerGraph(registry);
    registerBogey(registry);
    registerSchedule(registry);
    registerObserver(registry);
    registerSignal(registry);
    registerDisplay(registry);
    registerTrack(registry);
    registerStation(registry);
    registerEntity(registry);
    registerManager(registry);
  }

  @override
  void onLoad(CreateContext ctx) {
    Tr.install(TrainsRuntime(ctx));
    loadGraph(ctx);
    loadBogey(ctx);
    loadSchedule(ctx);
    loadObserver(ctx);
    loadSignal(ctx);
    loadDisplay(ctx);
    // `AllPortalTracks.registerDefaults()`: without this the portal-track registry is empty,
    // so tracks beside a nether portal never connect and any portal track turns to air.
    AllPortalTracks.registerDefaults();
    loadTrack(ctx);
    loadStation(ctx);
    // `GlobalStation.mailHooks` stays uninstalled: the logistics module has no postbox block
    // entity and no package inventory yet, so there is no `MailTransferHooks` provider and mail
    // is not moved when a train arrives or a carriage is disassembled.
    loadEntity(ctx);
    loadManager(ctx);

    // The payload handlers of the areas and the train effects the train logic reaches through
    // `TrainFx`.
    installTrainEffects(ctx);
    installStationEditPacket(ctx);
    installCurvedTrackPackets(ctx);
    installTrainRelocationPacket(ctx);
    installTrainHudPacket(ctx);
    installHonkPacket(ctx);
    installTrainMapSync(ctx);
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    serverGraphLoaded(runtime);
    serverBogeyLoaded(runtime);
    serverObserverLoaded(runtime);
    serverSignalLoaded(runtime);
    serverDisplayLoaded(runtime);
    serverTrackLoaded(runtime);
    serverStationLoaded(runtime);
    serverEntityLoaded(runtime);
    serverManagerLoaded(runtime);
  }

  @override
  void onUnload() {
    unloadTrainMapSync();
    uninstallTrainEffects();
    unloadGraph();
    unloadBogey();
    unloadSchedule();
    unloadObserver();
    unloadSignal();
    unloadDisplay();
    unloadTrack();
    unloadStation();
    unloadEntity();
    unloadManager();
    Tr.clear();
  }
}
