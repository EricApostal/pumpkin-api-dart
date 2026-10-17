import 'dart:async';

import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import 'bindings.g.dart' hide Text;
import 'messages.dart';

String _idKey(Uuid id) => '${id.high.toRadixString(16)}:${id.low.toRadixString(16)}';

/// A boss bar that can be kept in a field and used from any callback.
///
/// The host's `BossBar` resource is created once and kept alive (`keep()`)
/// until [remove]. The title is stored as a string or [Text] and rebuilt on
/// each change, since host text components are consumed when passed on.
///
/// ```dart
/// final bar = ManagedBossBar('&cBoss', color: BossBarColor.red);
/// bar.addPlayer(event.player);            // consumes event.player!
/// bar.addPlayerById(server, someUuid);    // doesn't consume anything
/// bar.progress = 0.5;
/// bar.remove();
/// ```
final class ManagedBossBar {
  BossBar? _bar;
  Object _title;
  double _progress;
  BossBarColor _color;
  BossBarDivision _division;
  BossBarMetadata _metadata = const BossBarMetadata(
    darkenSky: false,
    dragonBar: false,
    createFog: false,
  );
  final Set<String> _players = {};
  final Set<Future<void>> _pending = {};
  Timer? _timer;

  /// Creates a boss bar. [title] is a `String` with color codes or a [Text];
  /// [progress] is 0 to 1.
  ManagedBossBar(
    Object title, {
    BossBarColor color = BossBarColor.white,
    BossBarDivision division = BossBarDivision.noDivision,
    double progress = 1,
  }) : _title = title,
       _color = color,
       _division = division,
       _progress = progress.clamp(0.0, 1.0).toDouble() {
    final bar = BossBar.create(
      title: Messages.component(title),
      color: color,
      division: division,
    ).keep();
    _bar = bar;
    if (_progress != 1) _track(bar.setHealth(health: _progress));
  }

  BossBar get _live =>
      _bar ?? (throw StateError('This boss bar was removed'));

  /// Remembers [call], a change that is on its way to the host, so [remove]
  /// can wait for it before it releases the bar.
  void _track(Future<void> call) {
    _pending.add(call);
    call.whenComplete(() => _pending.remove(call));
  }

  /// Completes once every change made so far has reached the host.
  Future<void> flush() => Future.wait(_pending.toList());

  /// Whether [remove] was called.
  bool get isRemoved => _bar == null;

  /// The title as it was set (a `String` or [Text]).
  Object get title => _title;
  set title(Object value) {
    _title = value;
    _track(_live.setTitle(title: Messages.component(value)));
  }

  /// The fill, 0 (empty) to 1 (full). Values are clamped.
  double get progress => _progress;
  set progress(double value) {
    _progress = value.clamp(0.0, 1.0).toDouble();
    _track(_live.setHealth(health: _progress));
  }

  /// The bar color.
  BossBarColor get color => _color;
  set color(BossBarColor value) {
    _color = value;
    _track(_live.setColor(color: value));
  }

  /// The notches of the bar.
  BossBarDivision get division => _division;
  set division(BossBarDivision value) {
    _division = value;
    _track(_live.setDivision(division: value));
  }

  void _setMetadata(BossBarMetadata value) {
    _metadata = value;
    _track(_live.setMetadata(metadata: value));
  }

  /// Whether the sky darkens for viewers.
  bool get darkenSky => _metadata.darkenSky;
  set darkenSky(bool value) =>
      _setMetadata(_metadata.copyWith(darkenSky: value));

  /// Whether viewers get the ender dragon style bar.
  bool get dragonBar => _metadata.dragonBar;
  set dragonBar(bool value) =>
      _setMetadata(_metadata.copyWith(dragonBar: value));

  /// Whether fog appears around viewers.
  bool get createFog => _metadata.createFog;
  set createFog(bool value) =>
      _setMetadata(_metadata.copyWith(createFog: value));

  /// Shows the bar to [player]. The [player] handle is CONSUMED by the host:
  /// don't use it afterwards. Use [addPlayerById] to avoid that.
  Future<void> addPlayer(Player player) async {
    final key = _idKey(player.getId());
    _players.add(key);
    await _live.addPlayer(player: player);
  }

  /// Shows the bar to the online player with [id], if there is one. Returns
  /// whether the player was found. [server] must be used within its callback.
  Future<bool> addPlayerById(Server server, Uuid id) async {
    final p = server.getPlayerByUuid(id: id);
    if (p == null) return false;
    await addPlayer(p);
    return true;
  }

  /// Hides the bar from [player]. The [player] handle is CONSUMED.
  Future<void> removePlayer(Player player) async {
    final key = _idKey(player.getId());
    _players.remove(key);
    await _live.removePlayer(player: player);
  }

  /// Hides the bar from the online player with [id], if there is one.
  Future<bool> removePlayerById(Server server, Uuid id) async {
    final p = server.getPlayerByUuid(id: id);
    _players.remove(_idKey(id));
    if (p == null) return false;
    await _live.removePlayer(player: p);
    return true;
  }

  /// Whether the player with [id] was added and not removed since.
  bool hasPlayer(Uuid id) => _players.contains(_idKey(id));

  /// Number of players the bar was shown to (as tracked by this object).
  int get playerCount => _players.length;

  /// Hides the bar from everybody. It stays usable.
  Future<void> clearPlayers() async {
    _players.clear();
    await _live.removeAll();
  }

  /// Calls [update] every [interval] (resolution of one tick, 50ms) until
  /// [remove] or [stopUpdating]. Replaces an earlier updater.
  ///
  /// ```dart
  /// bar.updateEvery(Duration(seconds: 1), (b) => b.title = 'Time: ${clock()}');
  /// ```
  void updateEvery(Duration interval, void Function(ManagedBossBar bar) update) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (isRemoved) return;
      update(this);
    });
  }

  /// Stops the updater of [updateEvery] or [countdown].
  void stopUpdating() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drains [progress] from full to empty over [total], then calls [onFinish]
  /// (and removes the bar if [removeWhenDone]). Uses the wall clock.
  void countdown(
    Duration total, {
    void Function(ManagedBossBar bar)? onFinish,
    bool removeWhenDone = true,
    Duration interval = const Duration(milliseconds: 250),
  }) {
    final start = DateTime.now();
    progress = 1;
    updateEvery(interval, (b) {
      final elapsed = DateTime.now().difference(start);
      if (elapsed >= total) {
        b.stopUpdating();
        b.progress = 0;
        onFinish?.call(b);
        if (removeWhenDone && !b.isRemoved) unawaited(b.remove());
      } else {
        b.progress = 1 - elapsed.inMilliseconds / total.inMilliseconds;
      }
    });
  }

  /// Hides the bar from everybody and releases it. Safe to call twice.
  Future<void> remove() async {
    stopUpdating();
    final bar = _bar;
    if (bar == null) return;
    _bar = null;
    _players.clear();
    // The host call has to be done with the bar before the handle is dropped.
    await flush();
    await bar.removeAll();
    bar.dispose();
  }
}
