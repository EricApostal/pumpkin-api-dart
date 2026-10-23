// The media a disk drive holds (`IMedia` in CC: Tweaked, `IMedia.java`).
//
// Java decides what a stack is by asking its registered `IMedia` providers:
// `MountMedia.DISK` for a data disk (a writable mount, keyed by the `disk_id`
// component), `TreasureDiskMedia` for a treasure disk (a read-only mount into
// the mod jar's `data/computercraft/lua/treasure/<path>`) and `RecordMedia` for
// anything with a `minecraft:jukebox_playable` component.
//
// This file is the model only: it knows nothing of the host. The plugin builds
// the instances (the mounts come from its data folder and from the ROM jar) and
// hands them to a drive.
import 'filesystem.dart';

/// A disk in a drive, or in a computer's media slot (`IMedia`). The defaults
/// are Java's: a label that cannot be set, no data and no audio.
abstract class Media {
  /// The item key the media came from (`computercraft:disk`), for logs.
  String get itemKey;

  /// `getLabel`: the label of the disk, or null when it has none.
  String? get label => null;

  /// `setLabel`: whether the label could be changed. Java's `IMedia.setLabel`
  /// is false by default, so a treasure disk and a record refuse a new label
  /// and `setDiskLabel` raises "Disk label cannot be changed".
  bool setLabel(String? label) => false;

  /// `createDataMount`: the contents of the disk, or null when it has none
  /// (a record).
  Mount? createDataMount() => null;

  /// The `disk_id` component of the stack (`Drive.getDiskID`), or null when
  /// the disk has no id.
  int? get diskId => null;

  /// `getAudio`: the title of the record on the disk, or null when the disk has
  /// no audio. `getAudioTitle` gives nil for null.
  String? get audioTitle => null;

  /// Whether this media ever plays audio (`getMedia().getAudio(...) != null`).
  bool get hasAudio => audioTitle != null;
}

/// A data disk: a writable mount (the plugin's storage, keyed by the disk's
/// `disk_id`) whose label is the item's custom name (`MountMedia.getLabel` /
/// `setLabel`, which sets the custom name).
final class DataDisk extends Media {
  final Mount mount;
  final int id;

  /// The label of the disk (the item's custom name, `MountMedia.getLabel`);
  /// null when it has none.
  String? _label;

  DataDisk(this.mount, this.id, [this._label]);

  @override
  String get itemKey => 'computercraft:disk';

  @override
  int? get diskId => id;

  @override
  String? get label => _label;

  @override
  bool setLabel(String? label) {
    _label = label;
    return true;
  }

  @override
  Mount createDataMount() => mount;
}

/// A treasure disk: the read-only content of the mod jar's data pack under
/// `lua/treasure/<path>`, labelled with the title of its `treasure_disk`
/// component. `TreasureDiskMedia` overrides `getLabel` only, so its label
/// cannot be set.
final class TreasureDisk extends Media {
  final Mount mount;
  final String title;

  TreasureDisk(this.mount, this.title);

  @override
  String get itemKey => 'computercraft:treasure_disk';

  @override
  String? get label => title;

  @override
  Mount createDataMount() => mount;
}

/// A music disc (`RecordMedia`): audio only, and a label that cannot be
/// changed. Java's label is the song's description and this server cannot read
/// it (the song lives in the datapack registry `minecraft:jukebox_song`, which
/// the host does not expose), so [title] is null when the plugin could not
/// find one and `getAudioTitle` gives nil where Java gives the description.
/// Whether the disk has audio is known from the component, so `hasAudio` is
/// true either way.
final class RecordDisk extends Media {
  final String? title;

  RecordDisk([this.title]);

  @override
  String get itemKey => 'minecraft:music_disc';

  @override
  String? get label => title;

  @override
  String? get audioTitle => title;

  @override
  bool get hasAudio => true;
}