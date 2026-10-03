import 'bindings.g.dart' hide Text;
import 'messages.dart';

/// A sidebar (the list of lines on the right of the screen) on a
/// [Scoreboard].
///
/// A [Sidebar] only holds plain data (a title and lines), so it can live in a
/// field. Call [render] with a scoreboard (for example `world.getScoreboard()`
/// inside a callback) to show or refresh it; it only sends what changed.
///
/// ```dart
/// final sidebar = Sidebar('stats', title: '&6&lServer');
/// sidebar.lines = ['&7Online: 3', '', '&eplay.example.com'];
/// sidebar.render(world.getScoreboard());
/// ```
final class Sidebar {
  /// The objective name (internal, unique per scoreboard).
  final String name;

  /// The title shown above the lines. A `String` with color codes or a [Text].
  Object title;

  /// The lines from top to bottom, with `&` color codes.
  List<String> lines;

  bool _created = false;
  Object? _shownTitle;
  List<String> _shown = const [];

  /// Creates a sidebar. Nothing is shown until [render].
  Sidebar(this.name, {this.title = '', this.lines = const []});

  /// Shows (the first time) or updates this sidebar on [scoreboard]. The score
  /// numbers are hidden. Nothing of [scoreboard] is consumed.
  void render(Scoreboard scoreboard) {
    if (!_created) {
      scoreboard.addObjective(
        name: name,
        displayName: Messages.component(title),
        renderType: RenderType.integer,
        numberFormat: const NumberFormatBlank(),
      );
      scoreboard.setDisplaySlot(slot: DisplaySlot.sidebar, objectiveName: name);
      _created = true;
      _shownTitle = title;
    } else if (!identical(_shownTitle, title) && '$_shownTitle' != '$title') {
      scoreboard.updateObjective(
        name: name,
        displayName: Messages.component(title),
        renderType: RenderType.integer,
        numberFormat: const NumberFormatBlank(),
      );
      _shownTitle = title;
    }
    final entries = SidebarLayout.entries(lines);
    for (final old in _shown) {
      if (!entries.contains(old)) {
        scoreboard.removeScore(entityName: old, objectiveName: name);
      }
    }
    for (var i = 0; i < entries.length; i++) {
      scoreboard.updateScore(
        entityName: entries[i],
        objectiveName: name,
        value: SidebarLayout.score(i, entries.length),
        numberFormat: const NumberFormatBlank(),
      );
    }
    _shown = entries;
  }

  /// Removes the sidebar from [scoreboard]. [render] shows it again.
  void hide(Scoreboard scoreboard) {
    if (!_created) return;
    scoreboard.clearDisplaySlot(slot: DisplaySlot.sidebar);
    scoreboard.removeObjective(name: name);
    _created = false;
    _shown = const [];
  }
}

/// Showing a [Sidebar] in a world.
extension SidebarWorld on World {
  /// Shows or refreshes [sidebar] on this world's scoreboard.
  void showSidebar(Sidebar sidebar) {
    final sb = getScoreboard();
    sidebar.render(sb);
  }

  /// Removes [sidebar] from this world's scoreboard.
  void hideSidebar(Sidebar sidebar) => sidebar.hide(getScoreboard());
}
