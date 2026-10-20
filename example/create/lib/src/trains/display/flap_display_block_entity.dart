// `FlapDisplayBlockEntity`: the controller of a display board (the top left block of a rectangle of
// boards), its lines and the flaps. It is a kinetic block entity: the board only reacts when
// it turns fast enough (`SpeedLevel.MEDIUM`).
//
// NBT (as the Create client reads it, the same for saved data and client update): the kinetic
// data, `Controller`, `XSize`, `YSize`, `CustomLine<j>` / `GlowingLine<j>` markers, `Dye<j>`
// (the `DyeColor` name) and `Display<i>` = a layout { `Key`, `Sections` }.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/kinetics.dart' show KineticBlockEntity;
import '../../api/redstone.dart' show FlapControllerView, FlapLayoutSpec, FlapSectionSpec;
import '../../api/util.dart' hide pos;
import '../../redstone/support/text.dart' show Txt;
import '../support/ctag_host.dart';
import '../util/ctag.dart';
import 'flap_display_block.dart';
import 'flap_display_layout.dart';
import 'flap_display_section.dart';

/// `FlapDisplayBlockEntity`.
class FlapDisplayBlockEntity extends KineticBlockEntity {
  static const String type = 'create:flap_display';

  List<FlapDisplayLayout>? lines;
  bool isController = false;
  bool isRunning = false;
  int xSize = 1, ySize = 1;

  /// The dye of each line (`DyeColor`, lower case ids); `null` is white.
  List<String?> colour = List<String?>.filled(2, null);
  List<bool> glowingLines = List<bool>.filled(2, false);
  List<bool> manualLines = List<bool>.filled(2, false);

  FlapDisplayBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 10;
  }

  Pos get _pos => pos.toPos();

  /// `getBlockState()`.
  BState getBlockState() {
    final w = world;
    if (w == null) return BState.air;
    return HostBlockGetter(w).stateAt(_pos);
  }

  @override
  void lazyTick() {
    super.lazyTick();
    updateControllerStatus();
  }

  /// `updateControllerStatus()`: recomputes whether this board is the controller and the size of the
  /// board it controls.
  void updateControllerStatus() {
    final w = world;
    if (w == null) return;
    final level = HostBlockGetter(w);

    final blockState = level.stateAt(_pos);
    if (blockState.key != FlapDisplayBlock.key) return;

    final leftDirection = blockState.dir(FlapDisplayBlock.facingProperty)!.clockWise;
    final shouldBeController =
        !blockState.flag(FlapDisplayBlock.upProperty) && level.stateAt(_pos.relative(leftDirection)) != blockState;

    var newXSize = 1;
    var newYSize = 1;

    if (shouldBeController) {
      for (var xOffset = 1; xOffset < 32; xOffset++) {
        if (level.stateAt(_pos.relative(leftDirection.opposite, xOffset)) != blockState) break;
        newXSize++;
      }
      for (var yOffset = 0; yOffset < 32; yOffset++) {
        final below = level.stateAt(_pos.relative(Direction.down, yOffset));
        if (!(below.has(FlapDisplayBlock.downProperty) && below.flag(FlapDisplayBlock.downProperty))) break;
        newYSize++;
      }
    }

    if (isController == shouldBeController && newXSize == xSize && newYSize == ySize) return;

    isController = shouldBeController;
    xSize = newXSize;
    ySize = newYSize;
    colour = _copyOf(colour, ySize * 2, null);
    glowingLines = _copyOf(glowingLines, ySize * 2, false);
    manualLines = List<bool>.filled(ySize * 2, false);
    lines = null;
    sendData();
  }

  static List<T> _copyOf<T>(List<T> list, int length, T fill) =>
      [for (var i = 0; i < length; i++) i < list.length ? list[i] : fill];

  @override
  void tick() {
    super.tick();
    isRunning = super.isSpeedRequirementFulfilled;
    // The flaps spin on the client only (`level.isClientSide()` in Java); the server just tracks
    // whether the board runs.
  }

  /// `isSpeedRequirementFulfilled()`: whether the board ran at its last tick.
  @override
  bool get isSpeedRequirementFulfilled => isRunning;

  /// `applyTextManually(lineIndex, componentText)`: sets the text of a line, `null` clears it.
  /// (`DynamicComponent.parseCustomText` resolves selectors and scores of the text on the server;
  /// the host offers no such resolution, so the text is used as it is.)
  void applyTextManually(int lineIndex, Txt? componentText) {
    final lines = getLines();
    if (lineIndex >= lines.length) return;

    final layout = lines[lineIndex];
    if (!layout.isLayout('Default')) layout.loadDefault(getMaxCharCount());
    final sections = layout.getSections();

    final flapDisplaySection = sections[0];
    if (componentText == null) {
      manualLines[lineIndex] = false;
      flapDisplaySection.setText(Txt.empty());
      sendData();
      return;
    }

    manualLines[lineIndex] = true;
    flapDisplaySection.setText(componentText);
    sendData();
  }

  /// `setColour(lineIndex, color)`: [color] is a dye id (`red`); white clears the dye.
  void setColour(int lineIndex, String color) {
    colour[lineIndex] = color == 'white' ? null : color;
    sendData();
  }

  /// `setGlowing(lineIndex)`.
  void setGlowing(int lineIndex) {
    glowingLines[lineIndex] = true;
    sendData();
  }

  /// `getLines()`.
  List<FlapDisplayLayout> getLines() {
    if (lines == null) initDefaultSections();
    return lines!;
  }

  /// `initDefaultSections()`.
  void initDefaultSections() {
    lines = [for (var i = 0; i < ySize * 2; i++) FlapDisplayLayout(getMaxCharCount())];
  }

  /// `getMaxCharCount()`.
  int getMaxCharCount([int gaps = 0]) => ((xSize * 16.0 - 2.0 - 4.0 * gaps) / 3.5).toInt();

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);

    tag.putBool('Controller', isController);
    tag.putInt('XSize', xSize);
    tag.putInt('YSize', ySize);

    for (var j = 0; j < manualLines.length; j++) {
      if (manualLines[j]) NbtHelper.putMarker(tag, 'CustomLine$j');
    }

    for (var j = 0; j < glowingLines.length; j++) {
      if (glowingLines[j]) NbtHelper.putMarker(tag, 'GlowingLine$j');
    }

    for (var j = 0; j < colour.length; j++) {
      final c = colour[j];
      if (c != null) tag.putString('Dye$j', c.toUpperCase());
    }

    final lines = getLines();
    for (var i = 0; i < lines.length; i++) {
      tag.putCompound('Display$i', lines[i].write(clearTransition: clientPacket).toHost());
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final wasActive = isController;
    final prevX = xSize;
    final prevY = ySize;

    isController = tag.getBool('Controller') ?? false;
    xSize = tag.getInt('XSize') ?? 0;
    ySize = tag.getInt('YSize') ?? 0;

    manualLines = [for (var i = 0; i < ySize * 2; i++) tag.containsKey('CustomLine$i')];
    glowingLines = [for (var i = 0; i < ySize * 2; i++) tag.containsKey('GlowingLine$i')];
    colour = [for (var i = 0; i < ySize * 2; i++) tag.containsKey('Dye$i') ? _readDye(tag.getString('Dye$i') ?? '') : null];

    if ((clientPacket && wasActive != isController) || prevX != xSize || prevY != ySize) {
      this.lines = null;
    }

    final lines = getLines();
    for (var i = 0; i < lines.length; i++) {
      final display = tag.getCompound('Display$i');
      lines[i].read(display?.toCTag() ?? CTag());
    }
  }

  /// `readEnum(tag, key, DyeColor.class)`: the constant with that name, the first one (white) otherwise.
  static String? _readDye(String name) {
    for (final dye in dyeColors) {
      if (name == dye.toUpperCase()) return dye;
    }
    return 'white';
  }

  /// `getLineIndexAt(yCoord)`.
  int getLineIndexAt(double yCoord) => FlapDisplayBlock.getLineIndexAt(pos.y, ySize, yCoord);

  /// `getController()`: this board when it is the controller, else the controller of its board,
  /// `null` when there is none.
  FlapDisplayBlockEntity? getController() {
    if (isController) return this;
    final w = world;
    if (w == null) return null;
    final level = HostBlockGetter(w);
    final blockState = level.stateAt(_pos);
    if (blockState.key != FlapDisplayBlock.key) return null;

    final found = FlapDisplayBlock.findControllerPos(level, _pos, blockState, (p) {
      final be = store.typed<FlapDisplayBlockEntity>(worldId, p.toBlockPos());
      return be != null && be.isController;
    });
    if (found == null) return null;
    return store.typed<FlapDisplayBlockEntity>(worldId, found.toBlockPos());
  }

  /// `getDirection()`: the way the display faces (the opposite of its `facing`).
  Direction getDirection() => (getBlockState().dir(FlapDisplayBlock.facingProperty) ?? Direction.south).opposite;

  /// `getLineColor(line)`.
  int getLineColor(int line) {
    final color = colour[line];
    return color == null ? 0xFFD3C6BA : DyeHelper.getDyeColors(color).first | 0xFF000000;
  }

  /// `isLineGlowing(line)`.
  bool isLineGlowing(int line) => glowingLines[line];

  /// `tick` of the flap sections (the client animation, `FlapDisplaySection.tick`): the number of
  /// flaps spinning in all lines.
  int tickFlaps(bool instant, math.Random random) {
    var activeFlaps = 0;
    for (final line in getLines()) {
      for (final section in line.getSections()) {
        activeFlaps += section.tickFlaps(instant, random);
      }
    }
    return activeFlaps;
  }
}

/// The controller of a board as the display link target sees it (`FlapControllerView`).
final class FlapControllerAdapter implements FlapControllerView {
  final FlapDisplayBlockEntity controller;

  FlapControllerAdapter(this.controller);

  @override
  Pos get pos => controller.pos.toPos();

  @override
  int get xSize => controller.xSize;

  @override
  int get ySize => controller.ySize;

  @override
  int get maxCharCount => controller.getMaxCharCount();

  @override
  int maxCharCountFor(int gaps) => controller.getMaxCharCount(gaps);

  @override
  bool get speedRequirementFulfilled => controller.isSpeedRequirementFulfilled;

  @override
  int get lineCount => controller.getLines().length;

  @override
  bool isManualLine(int line) => controller.manualLines.length > line && controller.manualLines[line];

  @override
  void setLine(int line, List<String> texts, {required FlapLayoutSpec layout}) {
    final lines = controller.getLines();
    if (line >= lines.length) return;
    final display = lines[line];
    FlapLayoutLoader.load(display, layout, controller.getMaxCharCount());
    final sections = display.getSections();
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      if (texts.length <= sectionIndex) break;
      sections[sectionIndex].setText(Txt.literal(texts[sectionIndex]));
    }
  }

  @override
  void clearLine(int line) => controller.applyTextManually(line, null);

  @override
  void sendData() => controller.sendData();
}

/// `DisplaySource.loadFlapDisplayLayout` builds the [FlapLayoutSpec]; this turns it into the
/// sections of [layout] (Java: the source configures the `FlapDisplayLayout` directly).
abstract final class FlapLayoutLoader {
  static void load(FlapDisplayLayout layout, FlapLayoutSpec spec, int maxCharCount) {
    final sections = spec.sections;
    if (sections == null) {
      // `layout.loadDefault(flapDisplay.getMaxCharCount())`.
      if (!layout.isLayout(spec.key)) layout.loadDefault(maxCharCount);
      return;
    }
    if (layout.isLayout(spec.key)) return;
    layout.configure(spec.key, [
      for (final section in sections)
        FlapDisplaySection(section.width, section.cycle, section.singleFlap, section.hasGap)
          ..rightAligned = section.rightAligned
          ..wideFlaps = section.wideFlaps,
    ]);
  }
}
