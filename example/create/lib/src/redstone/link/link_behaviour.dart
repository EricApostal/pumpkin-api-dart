// `LinkBehaviour`: the block entity behaviour that joins a block entity to a redstone
// link network (redstone links, stock links, the redstone requester, ...). Published to
// the other modules through `api/redstone.dart`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/pos.dart';
import 'frequency.dart';
import 'frequency_stacks.dart';
import 'link_network.dart';

/// The hit test of the two frequency slots: [first] says which slot, [localHit] is the
/// hit relative to the block's corner.
typedef SlotTest = bool Function(bool first, Vec3 localHit);

/// `LinkBehaviour`.
class LinkBehaviour extends BlockEntityBehaviour implements RedstoneLinkable {
  static const String behaviourId = 'Link';

  @override
  String get id => behaviourId;

  /// The network handler (a function, so the behaviour can be built before the module loads).
  final RedstoneLinkNetworkHandler Function() _handler;

  final SlotTest slotTest;

  Frequency frequencyFirst = Frequency.empty;
  Frequency frequencyLast = Frequency.empty;

  /// `newPosition`: false after loading a block entity that was saved at its current
  /// position, until `initialize` ran; receivers ignore the network until then.
  bool newPosition = true;

  bool _transmitter;
  final int Function() _transmission;
  final void Function(int power) _signalCallback;

  LinkBehaviour._(this._handler, this.slotTest, this._transmitter, this._transmission, this._signalCallback);

  /// `LinkBehaviour.receiver`.
  factory LinkBehaviour.receiver({
    required RedstoneLinkNetworkHandler Function() handler,
    required SlotTest slotTest,
    required void Function(int power) signalCallback,
  }) => LinkBehaviour._(handler, slotTest, false, () => 0, signalCallback);

  /// `LinkBehaviour.transmitter`.
  factory LinkBehaviour.transmitter({
    required RedstoneLinkNetworkHandler Function() handler,
    required SlotTest slotTest,
    required int Function() transmission,
  }) => LinkBehaviour._(handler, slotTest, true, transmission, (_) {});

  /// A behaviour that can be either; used by the redstone link whose mode follows its block state.
  factory LinkBehaviour.switchable({
    required RedstoneLinkNetworkHandler Function() handler,
    required SlotTest slotTest,
    required bool transmitter,
    required int Function() transmission,
    required void Function(int power) signalCallback,
  }) => LinkBehaviour._(handler, slotTest, transmitter, transmission, signalCallback);

  RedstoneLinkNetworkHandler get handler => _handler();

  bool get isTransmitter => _transmitter;

  /// Changes between transmitting and receiving: the entity left the network and
  /// joins it again so the receivers see the change (`removeBehaviour` + `createLink`).
  void switchMode({required bool transmitter, bool rejoin = true}) {
    if (_transmitter == transmitter) return;
    if (!rejoin) {
      _transmitter = transmitter;
      return;
    }
    handler.removeFromNetwork(owner.worldId, this);
    _transmitter = transmitter;
    handler.addToNetwork(owner.worldId, this);
  }

  /// `copyItemsFrom`.
  void copyItemsFrom(LinkBehaviour? other) {
    if (other == null) return;
    frequencyFirst = other.frequencyFirst;
    frequencyLast = other.frequencyLast;
  }

  // -- IRedstoneLinkable ---------------------------------------------------------------------

  @override
  bool get isListening => !_transmitter;

  @override
  int get transmittedStrength => _transmitter ? _transmission() : 0;

  @override
  void setReceivedStrength(int power) {
    if (!newPosition) return;
    _signalCallback(power);
  }

  @override
  void onActorNetworkUpdate(int power) {
    // Fix for the one to one loading order problem.
    if (isListening) {
      newPosition = true;
      setReceivedStrength(power);
    }
  }

  @override
  NetworkKey get networkKey => Couple<Frequency>(frequencyFirst, frequencyLast);

  @override
  Pos get location => owner.pos.toPos();

  @override
  bool get isAlive {
    if (owner.removed) return false;
    final world = owner.world;
    if (world == null || !world.isLoaded(pos: owner.pos)) return false;
    return identical(owner.store.at(owner.worldId, owner.pos), owner);
  }

  /// `notifySignalChange`.
  void notifySignalChange() => handler.updateNetworkOf(owner.worldId, this);

  // -- Lifecycle -------------------------------------------------------------------------------

  @override
  void initialize() {
    handler.addToNetwork(owner.worldId, this);
    newPosition = true;
  }

  @override
  void onUnload() => handler.removeFromNetwork(owner.worldId, this);

  @override
  void onRemoved() => handler.removeFromNetwork(owner.worldId, this);

  /// `setFrequency`: [frequency] goes into slot [first] (the first or the last one).
  void setFrequency(bool first, Frequency frequency) {
    final current = first ? frequencyFirst : frequencyLast;
    final changed = frequency != current;

    if (changed) handler.removeFromNetwork(owner.worldId, this);

    if (first) {
      frequencyFirst = frequency;
    } else {
      frequencyLast = frequency;
    }

    if (!changed) return;

    owner.sendData();
    handler.addToNetwork(owner.worldId, this);
  }

  /// `testHit(first, hit)`: [hit] in world coordinates.
  bool testHit(bool first, Vec3 hit) {
    final p = owner.pos;
    return slotTest(first, (hit.$1 - p.x, hit.$2 - p.y, hit.$3 - p.z));
  }

  // -- NBT -------------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('FrequencyFirst', frequencyToNbt(frequencyFirst));
    tag.putCompound('FrequencyLast', frequencyToNbt(frequencyLast));
    tag.putLong('LastKnownPosition', packPos(owner.pos.x, owner.pos.y, owner.pos.z));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final positionInTag = packPos(owner.pos.x, owner.pos.y, owner.pos.z);
    final positionKey = tag.getInt('LastKnownPosition') ?? 0;
    newPosition = positionInTag != positionKey;

    frequencyFirst = frequencyFromNbt(tag.getCompound('FrequencyFirst'));
    frequencyLast = frequencyFromNbt(tag.getCompound('FrequencyLast'));
  }
}
