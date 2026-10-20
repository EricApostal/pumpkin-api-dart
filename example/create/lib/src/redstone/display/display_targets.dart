// The four display targets of Create (`AllDisplayTargets`): signs, lecterns, nixie tubes
// and display boards. Pure over [DisplayEnv].
import '../../common/common.dart';
import 'display_core.dart';
import 'display_sources.dart';

bool isSignBlock(String key) => key.endsWith('_sign') || key.endsWith('_hanging_sign');

/// `SignDisplayTarget` (`sign`).
final class SignDisplayTarget extends DisplayTarget {
  @override
  String get id => 'create:sign';

  /// `SignBlockEntity.getMaxTextLineWidth()`.
  static const int maxLineWidth = 90;

  @override
  Future<void> acceptText(int line, List<Txt> text, DisplayLinkContext context) async {
    if (!isSignBlock(context.targetState.key)) return;
    final lines = <int, String>{};
    for (var i = 0; i < text.length && i + line < 4; i++) {
      if (i == 0) reserve(i + line, context.targetPos, context);
      if (i > 0 && isReserved(i + line, context.targetPos, context)) break;
      final plain = text[i].plain;
      lines[i + line] = plain.length > maxLineWidth ? plain.substring(0, maxLineWidth) : plain;
    }
    if (lines.isEmpty) return;
    await context.env.writeSignLines(context.targetPos, lines);
  }

  @override
  Future<DisplayTargetStats> provideStats(DisplayLinkContext context) async => DisplayTargetStats(4, 15, this);

  @override
  bool get requiresComponentSanitization => true;
}

/// `LecternDisplayTarget` (`lectern`).
final class LecternDisplayTarget extends DisplayTarget {
  @override
  String get id => 'create:lectern';

  @override
  Future<void> acceptText(int line, List<Txt> text, DisplayLinkContext context) async {
    if (context.targetState.key != 'minecraft:lectern') return;
    final book = await context.env.lecternBook(context.targetPos);
    if (book == null) return;

    final pages = List<Object?>.of(book.pages);
    var changed = false;
    for (var i = 0; i - line < text.length && i < 50; i++) {
      if (pages.length <= i) {
        pages.add(i < line ? '' : text[i - line].toJson());
      } else if (i >= line) {
        if (i - line == 0) reserve(i, context.targetPos, context);
        if (i - line > 0 && isReserved(i - line, context.targetPos, context)) break;
        pages[i] = text[i - line].toJson();
      }
      changed = true;
    }
    if (changed || book.writable) await context.env.setLecternPages(context.targetPos, pages);
  }

  @override
  Future<DisplayTargetStats> provideStats(DisplayLinkContext context) async => DisplayTargetStats(50, 256, this);

  @override
  bool get requiresComponentSanitization => true;
}

/// `SingleLineDisplayTarget`.
abstract class SingleLineDisplayTarget extends DisplayTarget {
  @override
  Future<void> acceptText(int line, List<Txt> text, DisplayLinkContext context) => acceptLine(text.first, context);

  Future<void> acceptLine(Txt text, DisplayLinkContext context);

  int getWidth(DisplayLinkContext context);

  @override
  Future<DisplayTargetStats> provideStats(DisplayLinkContext context) async =>
      DisplayTargetStats(1, getWidth(context), this);
}

/// `NixieTubeDisplayTarget` (`nixie_tube`).
final class NixieTubeDisplayTarget extends SingleLineDisplayTarget {
  @override
  String get id => 'create:nixie_tube';

  @override
  Future<void> acceptLine(Txt text, DisplayLinkContext context) async {
    final tagElement = text.toJsonString();
    for (final (pos, rowPosition) in context.env.nixieRow(context.targetPos)) {
      context.env.setNixieText(pos, tagElement, rowPosition);
    }
  }

  @override
  int getWidth(DisplayLinkContext context) => context.env.nixieRow(context.targetPos).length * 2;
}

/// `DisplayBoardTarget` (`display_board`).
final class DisplayBoardTarget extends DisplayTarget implements FlapTarget {
  @override
  String get id => 'create:display_board';

  @override
  Future<void> acceptText(int line, List<Txt> text, DisplayLinkContext context) async {}

  FlapControllerView? _controller(DisplayLinkContext context) => context.env.flapController(context.targetPos);

  @override
  Future<void> acceptFlapText(int line, List<List<Txt>> text, DisplayLinkContext context, DisplaySource source) async {
    final controller = _controller(context);
    if (controller == null) return;
    if (!controller.speedRequirementFulfilled) return;

    final lines = controller.lineCount;
    for (var i = 0; i + line < lines; i++) {
      if (i == 0) reserve(i + line, controller.pos, context);
      if (i > 0 && isReserved(i + line, controller.pos, context)) break;

      if (i >= text.length) {
        if (source is SingleLineDisplaySource) break;
        controller.clearLine(i + line);
        continue;
      }
      // `source.loadFlapDisplayLayout(context, controller, layout, i)`: `i` is the row within the
      // source's text (Boiler's line 0 rule), not the board line.
      final layout = source.loadFlapDisplayLayout(context, controller, i);
      controller.setLine(i + line, [for (final t in text[i]) t.plain], layout: layout);
    }
    controller.sendData();
  }

  @override
  bool isReserved(int line, Pos target, DisplayLinkContext context) {
    if (super.isReserved(line, target, context)) return true;
    final c = _controller(context);
    return c != null && c.lineCount > line && c.isManualLine(line);
  }

  @override
  Future<DisplayTargetStats> provideStats(DisplayLinkContext context) async {
    final controller = _controller(context);
    if (controller == null) return DisplayTargetStats(1, 1, this);
    return DisplayTargetStats(controller.ySize * 2, controller.maxCharCount, this);
  }
}

/// The four targets.
List<DisplayTarget> createDisplayTargets() => [
  SignDisplayTarget(),
  LecternDisplayTarget(),
  DisplayBoardTarget(),
  NixieTubeDisplayTarget(),
];

/// `AllDisplayTargets.LEGACY_NAMES`.
const Map<String, String> legacyDisplayTargetNames = {
  'sign_display_target': 'sign',
  'lectern_display_target': 'lectern',
  'display_board_target': 'display_board',
  'nixie_tube_target': 'nixie_tube',
};
