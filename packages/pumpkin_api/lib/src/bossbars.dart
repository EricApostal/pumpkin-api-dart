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
  final Set<String> _players = {};
  Timer? _timer;

  /// Creates a boss bar. [title] is a `String` with color codes or a [Text];
  /// [progress] is 0 to 1.
  ManagedBossBar(
    Object title, {
    BossBarColor color = BossBarColor.white,
    BossBarDivision division = BossBarDivision.noDivision,
    double progress = 1,
  }) : _title = title,
       _progress = progress.clamp(0.0, 1.0).toDouble() {
    final bar = BossBar.create(
      title: Messages.component(title),
      color: color,
      division: division,
    ).keep();
    _bar = bar;
    if (_progress != 1) bar.setHealth(health: _progress);
  }

  BossBar get _live =>
      _bar ?? (throw StateError('This boss bar was removed'));

  /// Whether [remove] was called.
  bool get isRemoved => _bar == null;

  /// The title as it was set (a `String` or [Text]).
  Object get title => _title;
  set title(Object value) {
    _title = value;
    _live.setTitle(title: Messages.component(value));
  }

  /// The fill, 0 (empty) to 1 (full). Values are clamped.
  double get progress => _progress;
  set progress(double value) {
    _progress = value.clamp(0.0, 1.0).toDouble();
    _live.setHealth(health: _progress);
  }

  /// The bar color.
  BossBarColor get color => _live.getColor();
  set color(BossBarColor value) => _live.setColor(color: value);

  /// The notches of the bar.
  BossBarDivision get division => _live.getDivision();
  set division(BossBarDivision value) => _live.setDivision(division: value);

  /// Whether the sky darkens for viewers.
  bool get darkenSky => _live.getMetadata().darkenSky;
  set darkenSky(bool value) =>
      _live.setMetadata(metadata: _live.getMetadata().copyWith(darkenSky: value));

  /// Whether viewers get the ender dragon style bar.
  bool get dragonBar => _live.getMetadata().dragonBar;
  set dragonBar(bool value) =>
      _live.setMetadata(metadata: _live.getMetadata().copyWith(dragonBar: value));

  /// Whether fog appears around viewers.
  bool get createFog => _live.getMetadata().createFog;
  set createFog(bool value) =>
      _live.setMetadata(metadata: _live.getMetadata().copyWith(createFog: value));

  /// Shows the bar to [player]. The [player] handle is CONSUMED by the host:
  /// don't use it afterwards. Use [addPlayerById] to avoid that.
  void addPlayer(Player player) {
    final key = _idKey(player.getId());
    _live.addPlayer(player: player);
    _players.add(key);
  }

  /// Shows the bar to the online player with [id], if there is one. Returns
  /// whether the player was found. [server] must be used within its callback.
  bool addPlayerById(Server server, Uuid id) {
    final p = server.getPlayerByUuid(id: id);
    if (p == null) return false;
    addPlayer(p);
    return true;
  }

  /// Hides the bar from [player]. The [player] handle is CONSUMED.
  void removePlayer(Player player) {
    final key = _idKey(player.getId());
    _live.removePlayer(player: player);
    _players.remove(key);
  }

  /// Hides the bar from the online player with [id], if there is one.
  bool removePlayerById(Server server, Uuid id) {
    final p = server.getPlayerByUuid(id: id);
    _players.remove(_idKey(id));
    if (p == null) return false;
    _live.removePlayer(player: p);
    return true;
  }

  /// Whether the player with [id] was added and not removed since.
  bool hasPlayer(Uuid id) => _players.contains(_idKey(id));

  /// Number of players the bar was shown to (as tracked by this object).
  int get playerCount => _players.length;

  /// Hides the bar from everybody. It stays usable.
  void clearPlayers() {
    _live.removeAll();
    _players.clear();
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
        if (removeWhenDone && !b.isRemoved) b.remove();
      } else {
        b.progress = 1 - elapsed.inMilliseconds / total.inMilliseconds;
      }
    });
  }

  /// Hides the bar from everybody and releases it. Safe to call twice.
  void remove() {
    stopUpdating();
    final bar = _bar;
    if (bar == null) return;
    bar.removeAll();
    bar.dispose();
    _bar = null;
    _players.clear();
  }
}
