// `SignalEdgeGroup` (pure): a stretch of track between signals that at most one train may occupy.
import '../entity/train.dart';
import '../../conveyance/nbt_names.dart' show enumFromNbtName;
import '../manager/create.dart';
import '../util/ctag.dart';
import 'edge_group_color.dart';
import 'signal_boundary.dart';

class SignalEdgeGroup {
  String id;
  EdgeGroupColor color = EdgeGroupColor.getDefault();

  Set<Train> trains = Set.identity();
  SignalBoundary? reserved;

  Map<String, String> intersecting = {};
  Set<SignalEdgeGroup> intersectingResolved = Set.identity();
  Set<String> adjacent = {};

  bool fallbackGroup = false;

  SignalEdgeGroup(this.id);

  SignalEdgeGroup asFallback() {
    fallbackGroup = true;
    return this;
  }

  /// `isOccupiedUnless(Train)` and `isOccupiedUnless(SignalBoundary)`: [trainOrBoundary] is either.
  bool isOccupiedUnless(Object trainOrBoundary) {
    if (intersectingResolved.isEmpty) _walkIntersecting(intersectingResolved.add);
    for (final group in intersectingResolved) {
      if (group._isThisOccupiedUnless(trainOrBoundary)) return true;
    }
    return false;
  }

  bool _isThisOccupiedUnless(Object trainOrBoundary) {
    if (trainOrBoundary is SignalBoundary) {
      return trains.isNotEmpty || reserved != null && !identical(reserved, trainOrBoundary);
    }
    return reserved != null || trains.length > 1 || !trains.contains(trainOrBoundary) && trains.isNotEmpty;
  }

  void putIntersection(String intersectionId, String targetGroup) {
    intersecting[intersectionId] = targetGroup;
    _walkIntersecting((g) => g.intersectingResolved.clear());
    resolveColor();
  }

  void removeIntersection(String intersectionId) {
    _walkIntersecting((g) => g.intersectingResolved.clear());

    final removed = intersecting.remove(intersectionId);
    final other = Create.RAILWAYS.signalEdgeGroups[removed];
    other?.intersecting.remove(intersectionId);

    resolveColor();
  }

  void putAdjacent(String adjacent) {
    this.adjacent.add(adjacent);
  }

  void removeAdjacent(String adjacent) {
    this.adjacent.remove(adjacent);
  }

  void resolveColor() {
    if (intersectingResolved.isEmpty) _walkIntersecting(intersectingResolved.add);

    var mask = 0;
    for (final group in intersectingResolved) {
      for (final id in group.adjacent) {
        final adjacent = Create.RAILWAYS.signalEdgeGroups[id];
        if (adjacent == null) continue;
        if (intersectingResolved.contains(adjacent)) continue;
        mask = adjacent.color.strikeFrom(mask);
      }
    }

    final newColour = EdgeGroupColor.findNextAvailable(mask);
    if (newColour == color) return;

    _walkIntersecting((group) {
      group.color = newColour;
      Create.RAILWAYS.sync.edgeGroupCreated(group.id, group.color);
    });
    Create.RAILWAYS.markTracksDirty();
  }

  void _walkIntersecting(void Function(SignalEdgeGroup group) callback) {
    _walkIntersectingRec(Set<SignalEdgeGroup>.identity(), callback);
  }

  void _walkIntersectingRec(Set<SignalEdgeGroup> visited, void Function(SignalEdgeGroup group) callback) {
    if (!visited.add(this)) return;
    callback(this);
    for (final uuid in intersecting.values.toList()) {
      final group = Create.RAILWAYS.signalEdgeGroups[uuid];
      group?._walkIntersectingRec(visited, callback);
    }
  }

  static SignalEdgeGroup read(CTag tag) {
    final group = SignalEdgeGroup(tag.getUuid('Id') ?? (throw const FormatException('SignalEdgeGroup without Id')));
    group.color = enumFromNbtName(tag.getString('Color'), EdgeGroupColor.values);
    for (final nbt in tag.getCompoundList('Connected')) {
      final key = nbt.getUuid('Key');
      final value = nbt.getUuid('Value');
      if (key != null && value != null) group.intersecting[key] = value;
    }
    group.fallbackGroup = tag.getBoolean('Fallback');
    return group;
  }

  CTag write() {
    final tag = CTag();
    tag.putUuid('Id', id);
    tag.putString('Color', color.name);
    tag.putCompoundList('Connected', [
      for (final e in intersecting.entries)
        CTag()
          ..putUuid('Key', e.key)
          ..putUuid('Value', e.value),
    ]);
    tag.putBoolean('Fallback', fallbackGroup);
    return tag;
  }
}
