// `AbstractBogeyBlockEntity` and `StandardBogeyBlockEntity`: the bogey data (style and the data a
// carriage bogey carries) stored in a block entity.
//
// NBT (saved data and client update tag, as `saveAdditional` does in Java): `BogeyData` { `BogeyStyle`:
// the style id (string), `UpsideDown`: byte, + the style's default data }.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../support/ctag_host.dart';
import '../util/ctag.dart';
import 'abstract_bogey_block.dart';
import 'bogey_sizes.dart';
import 'bogey_style.dart';

/// `AbstractBogeyBlockEntity`.
abstract class AbstractBogeyBlockEntity extends CreateBlockEntity {
  static const String bogeyStyleKey = 'BogeyStyle';
  static const String bogeyDataKey = 'BogeyData';

  /// `CarriageBogey.UPSIDE_DOWN_KEY`.
  static const String upsideDownKey = 'UpsideDown';

  CTag? _bogeyData;

  AbstractBogeyBlockEntity(super.worldId, super.pos);

  /// `getDefaultStyle()`.
  BogeyStyle getDefaultStyle();

  /// The state of the bogey block at this position (`getBlockState()`), air when the world is gone.
  BState getBlockState() {
    final w = world;
    if (w == null) return BState.air;
    return HostBlockGetter(w).stateAt(pos.toPos());
  }

  /// `getBogeyData()`: creates the data when missing or without a style.
  CTag getBogeyData() {
    final data = _bogeyData;
    if (data == null || !data.contains(bogeyStyleKey)) _bogeyData = _createBogeyData();
    return _bogeyData!;
  }

  /// `setBogeyData(newData)`: the default style is added when [newData] has none.
  void setBogeyData(CTag newData) {
    if (!newData.contains(bogeyStyleKey)) newData.putString(bogeyStyleKey, getDefaultStyle().id);
    _bogeyData = newData;
  }

  /// `setBogeyStyle(style)`.
  void setBogeyStyle(BogeyStyle style) {
    final data = getBogeyData();
    data.putString(bogeyStyleKey, style.id);
    _markUpdated();
  }

  /// `getStyle()`: the style of the data; a style that is no longer registered resets to the default.
  BogeyStyle getStyle() {
    final data = getBogeyData();
    final currentStyle = data.getString(bogeyStyleKey);
    final style = AllBogeyStyles.get(currentStyle);
    if (style == null) {
      setBogeyStyle(getDefaultStyle());
      return getStyle();
    }
    return style;
  }

  /// `AbstractBogeyBlock.getNextSize(sbbe)`: the state of the next larger size of this bogey's style.
  BState getNextSize() {
    final state = getBlockState();
    final block = AbstractBogeyBlock.byKey(state.key);
    if (block == null) return state;
    return block.getNextSize(getStyle(), state);
  }

  /// `AbstractBogeyBlock.getStateOfSize(sbbe, size)`.
  BState getStateOfSize(AbstractBogeyBlock block, BogeySize size) =>
      block.getStateOfSize(getStyle(), getBlockState(), size);

  CTag _createBogeyData() {
    final nbt = CTag();
    nbt.putString(bogeyStyleKey, getDefaultStyle().id);
    var upsideDown = false;
    final state = getBlockState();
    final block = AbstractBogeyBlock.byKey(state.key);
    if (block != null) upsideDown = block.isUpsideDown(state);
    nbt.putBoolean(upsideDownKey, upsideDown);
    return nbt;
  }

  void _markUpdated() => sendData();

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final data = getBogeyData(); // now contains the style
    tag.putCompound(bogeyDataKey, data.toHost());
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final data = tag.getCompound(bogeyDataKey);
    _bogeyData = data?.toCTag() ?? _createBogeyData();
    super.read(tag, clientPacket: clientPacket);
  }
}

/// `StandardBogeyBlockEntity`.
class StandardBogeyBlockEntity extends AbstractBogeyBlockEntity {
  static const String type = 'create:bogey';

  StandardBogeyBlockEntity(super.worldId, super.pos);

  @override
  BogeyStyle getDefaultStyle() => AllBogeyStyles.STANDARD;
}
