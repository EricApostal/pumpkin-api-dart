// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'players.dart';

class PlayerRecordMapper extends ClassMapperBase<PlayerRecord> {
  PlayerRecordMapper._();

  static PlayerRecordMapper? _instance;
  static PlayerRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayerRecordMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PlayerRecord';

  static String _$uuid(PlayerRecord v) => v.uuid;
  static const Field<PlayerRecord, String> _f$uuid = Field('uuid', _$uuid);
  static String _$name(PlayerRecord v) => v.name;
  static const Field<PlayerRecord, String> _f$name = Field('name', _$name);
  static DateTime _$firstSeen(PlayerRecord v) => v.firstSeen;
  static const Field<PlayerRecord, DateTime> _f$firstSeen = Field(
    'firstSeen',
    _$firstSeen,
  );
  static DateTime _$lastSeen(PlayerRecord v) => v.lastSeen;
  static const Field<PlayerRecord, DateTime> _f$lastSeen = Field(
    'lastSeen',
    _$lastSeen,
  );

  @override
  final MappableFields<PlayerRecord> fields = const {
    #uuid: _f$uuid,
    #name: _f$name,
    #firstSeen: _f$firstSeen,
    #lastSeen: _f$lastSeen,
  };

  static PlayerRecord _instantiate(DecodingData data) {
    return PlayerRecord(
      uuid: data.dec(_f$uuid),
      name: data.dec(_f$name),
      firstSeen: data.dec(_f$firstSeen),
      lastSeen: data.dec(_f$lastSeen),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlayerRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlayerRecord>(map);
  }

  static PlayerRecord fromJson(String json) {
    return ensureInitialized().decodeJson<PlayerRecord>(json);
  }
}

mixin PlayerRecordMappable {
  String toJson() {
    return PlayerRecordMapper.ensureInitialized().encodeJson<PlayerRecord>(
      this as PlayerRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return PlayerRecordMapper.ensureInitialized().encodeMap<PlayerRecord>(
      this as PlayerRecord,
    );
  }

  PlayerRecordCopyWith<PlayerRecord, PlayerRecord, PlayerRecord> get copyWith =>
      _PlayerRecordCopyWithImpl<PlayerRecord, PlayerRecord>(
        this as PlayerRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PlayerRecordMapper.ensureInitialized().stringifyValue(
      this as PlayerRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlayerRecordMapper.ensureInitialized().equalsValue(
      this as PlayerRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return PlayerRecordMapper.ensureInitialized().hashValue(
      this as PlayerRecord,
    );
  }
}

extension PlayerRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlayerRecord, $Out> {
  PlayerRecordCopyWith<$R, PlayerRecord, $Out> get $asPlayerRecord =>
      $base.as((v, t, t2) => _PlayerRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlayerRecordCopyWith<$R, $In extends PlayerRecord, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? uuid,
    String? name,
    DateTime? firstSeen,
    DateTime? lastSeen,
  });
  PlayerRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PlayerRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlayerRecord, $Out>
    implements PlayerRecordCopyWith<$R, PlayerRecord, $Out> {
  _PlayerRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlayerRecord> $mapper =
      PlayerRecordMapper.ensureInitialized();
  @override
  $R call({
    String? uuid,
    String? name,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) => $apply(
    FieldCopyWithData({
      if (uuid != null) #uuid: uuid,
      if (name != null) #name: name,
      if (firstSeen != null) #firstSeen: firstSeen,
      if (lastSeen != null) #lastSeen: lastSeen,
    }),
  );
  @override
  PlayerRecord $make(CopyWithData data) => PlayerRecord(
    uuid: data.get(#uuid, or: $value.uuid),
    name: data.get(#name, or: $value.name),
    firstSeen: data.get(#firstSeen, or: $value.firstSeen),
    lastSeen: data.get(#lastSeen, or: $value.lastSeen),
  );

  @override
  PlayerRecordCopyWith<$R2, PlayerRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlayerRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PlayerRecordsMapper extends ClassMapperBase<PlayerRecords> {
  PlayerRecordsMapper._();

  static PlayerRecordsMapper? _instance;
  static PlayerRecordsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayerRecordsMapper._());
      PlayerRecordMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PlayerRecords';

  static Map<String, PlayerRecord> _$players(PlayerRecords v) => v.players;
  static const Field<PlayerRecords, Map<String, PlayerRecord>> _f$players =
      Field('players', _$players, opt: true, def: const {});

  @override
  final MappableFields<PlayerRecords> fields = const {#players: _f$players};

  static PlayerRecords _instantiate(DecodingData data) {
    return PlayerRecords(players: data.dec(_f$players));
  }

  @override
  final Function instantiate = _instantiate;

  static PlayerRecords fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlayerRecords>(map);
  }

  static PlayerRecords fromJson(String json) {
    return ensureInitialized().decodeJson<PlayerRecords>(json);
  }
}

mixin PlayerRecordsMappable {
  String toJson() {
    return PlayerRecordsMapper.ensureInitialized().encodeJson<PlayerRecords>(
      this as PlayerRecords,
    );
  }

  Map<String, dynamic> toMap() {
    return PlayerRecordsMapper.ensureInitialized().encodeMap<PlayerRecords>(
      this as PlayerRecords,
    );
  }

  PlayerRecordsCopyWith<PlayerRecords, PlayerRecords, PlayerRecords>
  get copyWith => _PlayerRecordsCopyWithImpl<PlayerRecords, PlayerRecords>(
    this as PlayerRecords,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return PlayerRecordsMapper.ensureInitialized().stringifyValue(
      this as PlayerRecords,
    );
  }

  @override
  bool operator ==(Object other) {
    return PlayerRecordsMapper.ensureInitialized().equalsValue(
      this as PlayerRecords,
      other,
    );
  }

  @override
  int get hashCode {
    return PlayerRecordsMapper.ensureInitialized().hashValue(
      this as PlayerRecords,
    );
  }
}

extension PlayerRecordsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PlayerRecords, $Out> {
  PlayerRecordsCopyWith<$R, PlayerRecords, $Out> get $asPlayerRecords =>
      $base.as((v, t, t2) => _PlayerRecordsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PlayerRecordsCopyWith<$R, $In extends PlayerRecords, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    PlayerRecord,
    PlayerRecordCopyWith<$R, PlayerRecord, PlayerRecord>
  >
  get players;
  $R call({Map<String, PlayerRecord>? players});
  PlayerRecordsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PlayerRecordsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PlayerRecords, $Out>
    implements PlayerRecordsCopyWith<$R, PlayerRecords, $Out> {
  _PlayerRecordsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PlayerRecords> $mapper =
      PlayerRecordsMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    PlayerRecord,
    PlayerRecordCopyWith<$R, PlayerRecord, PlayerRecord>
  >
  get players => MapCopyWith(
    $value.players,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(players: v),
  );
  @override
  $R call({Map<String, PlayerRecord>? players}) =>
      $apply(FieldCopyWithData({if (players != null) #players: players}));
  @override
  PlayerRecords $make(CopyWithData data) =>
      PlayerRecords(players: data.get(#players, or: $value.players));

  @override
  PlayerRecordsCopyWith<$R2, PlayerRecords, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PlayerRecordsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

