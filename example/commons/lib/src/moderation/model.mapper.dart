// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class PunishmentTypeMapper extends EnumMapper<PunishmentType> {
  PunishmentTypeMapper._();

  static PunishmentTypeMapper? _instance;
  static PunishmentTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PunishmentTypeMapper._());
    }
    return _instance!;
  }

  static PunishmentType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  PunishmentType decode(dynamic value) {
    switch (value) {
      case r'warn':
        return PunishmentType.warn;
      case r'mute':
        return PunishmentType.mute;
      case r'ban':
        return PunishmentType.ban;
      case r'kick':
        return PunishmentType.kick;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(PunishmentType self) {
    switch (self) {
      case PunishmentType.warn:
        return r'warn';
      case PunishmentType.mute:
        return r'mute';
      case PunishmentType.ban:
        return r'ban';
      case PunishmentType.kick:
        return r'kick';
    }
  }
}

extension PunishmentTypeMapperExtension on PunishmentType {
  String toValue() {
    PunishmentTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<PunishmentType>(this) as String;
  }
}

class PunishmentMapper extends ClassMapperBase<Punishment> {
  PunishmentMapper._();

  static PunishmentMapper? _instance;
  static PunishmentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PunishmentMapper._());
      PunishmentTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Punishment';

  static int _$id(Punishment v) => v.id;
  static const Field<Punishment, int> _f$id = Field('id', _$id);
  static PunishmentType _$type(Punishment v) => v.type;
  static const Field<Punishment, PunishmentType> _f$type = Field(
    'type',
    _$type,
  );
  static String _$targetUuid(Punishment v) => v.targetUuid;
  static const Field<Punishment, String> _f$targetUuid = Field(
    'targetUuid',
    _$targetUuid,
  );
  static String _$targetName(Punishment v) => v.targetName;
  static const Field<Punishment, String> _f$targetName = Field(
    'targetName',
    _$targetName,
  );
  static String _$issuerUuid(Punishment v) => v.issuerUuid;
  static const Field<Punishment, String> _f$issuerUuid = Field(
    'issuerUuid',
    _$issuerUuid,
  );
  static String _$issuerName(Punishment v) => v.issuerName;
  static const Field<Punishment, String> _f$issuerName = Field(
    'issuerName',
    _$issuerName,
  );
  static String _$reason(Punishment v) => v.reason;
  static const Field<Punishment, String> _f$reason = Field('reason', _$reason);
  static DateTime _$issuedAt(Punishment v) => v.issuedAt;
  static const Field<Punishment, DateTime> _f$issuedAt = Field(
    'issuedAt',
    _$issuedAt,
  );
  static DateTime? _$expiresAt(Punishment v) => v.expiresAt;
  static const Field<Punishment, DateTime> _f$expiresAt = Field(
    'expiresAt',
    _$expiresAt,
    opt: true,
  );
  static DateTime? _$revokedAt(Punishment v) => v.revokedAt;
  static const Field<Punishment, DateTime> _f$revokedAt = Field(
    'revokedAt',
    _$revokedAt,
    opt: true,
  );
  static String? _$revokedBy(Punishment v) => v.revokedBy;
  static const Field<Punishment, String> _f$revokedBy = Field(
    'revokedBy',
    _$revokedBy,
    opt: true,
  );

  @override
  final MappableFields<Punishment> fields = const {
    #id: _f$id,
    #type: _f$type,
    #targetUuid: _f$targetUuid,
    #targetName: _f$targetName,
    #issuerUuid: _f$issuerUuid,
    #issuerName: _f$issuerName,
    #reason: _f$reason,
    #issuedAt: _f$issuedAt,
    #expiresAt: _f$expiresAt,
    #revokedAt: _f$revokedAt,
    #revokedBy: _f$revokedBy,
  };

  static Punishment _instantiate(DecodingData data) {
    return Punishment(
      id: data.dec(_f$id),
      type: data.dec(_f$type),
      targetUuid: data.dec(_f$targetUuid),
      targetName: data.dec(_f$targetName),
      issuerUuid: data.dec(_f$issuerUuid),
      issuerName: data.dec(_f$issuerName),
      reason: data.dec(_f$reason),
      issuedAt: data.dec(_f$issuedAt),
      expiresAt: data.dec(_f$expiresAt),
      revokedAt: data.dec(_f$revokedAt),
      revokedBy: data.dec(_f$revokedBy),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Punishment fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Punishment>(map);
  }

  static Punishment fromJson(String json) {
    return ensureInitialized().decodeJson<Punishment>(json);
  }
}

mixin PunishmentMappable {
  String toJson() {
    return PunishmentMapper.ensureInitialized().encodeJson<Punishment>(
      this as Punishment,
    );
  }

  Map<String, dynamic> toMap() {
    return PunishmentMapper.ensureInitialized().encodeMap<Punishment>(
      this as Punishment,
    );
  }

  PunishmentCopyWith<Punishment, Punishment, Punishment> get copyWith =>
      _PunishmentCopyWithImpl<Punishment, Punishment>(
        this as Punishment,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PunishmentMapper.ensureInitialized().stringifyValue(
      this as Punishment,
    );
  }

  @override
  bool operator ==(Object other) {
    return PunishmentMapper.ensureInitialized().equalsValue(
      this as Punishment,
      other,
    );
  }

  @override
  int get hashCode {
    return PunishmentMapper.ensureInitialized().hashValue(this as Punishment);
  }
}

extension PunishmentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, Punishment, $Out> {
  PunishmentCopyWith<$R, Punishment, $Out> get $asPunishment =>
      $base.as((v, t, t2) => _PunishmentCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PunishmentCopyWith<$R, $In extends Punishment, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? id,
    PunishmentType? type,
    String? targetUuid,
    String? targetName,
    String? issuerUuid,
    String? issuerName,
    String? reason,
    DateTime? issuedAt,
    DateTime? expiresAt,
    DateTime? revokedAt,
    String? revokedBy,
  });
  PunishmentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PunishmentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Punishment, $Out>
    implements PunishmentCopyWith<$R, Punishment, $Out> {
  _PunishmentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Punishment> $mapper =
      PunishmentMapper.ensureInitialized();
  @override
  $R call({
    int? id,
    PunishmentType? type,
    String? targetUuid,
    String? targetName,
    String? issuerUuid,
    String? issuerName,
    String? reason,
    DateTime? issuedAt,
    Object? expiresAt = $none,
    Object? revokedAt = $none,
    Object? revokedBy = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (type != null) #type: type,
      if (targetUuid != null) #targetUuid: targetUuid,
      if (targetName != null) #targetName: targetName,
      if (issuerUuid != null) #issuerUuid: issuerUuid,
      if (issuerName != null) #issuerName: issuerName,
      if (reason != null) #reason: reason,
      if (issuedAt != null) #issuedAt: issuedAt,
      if (expiresAt != $none) #expiresAt: expiresAt,
      if (revokedAt != $none) #revokedAt: revokedAt,
      if (revokedBy != $none) #revokedBy: revokedBy,
    }),
  );
  @override
  Punishment $make(CopyWithData data) => Punishment(
    id: data.get(#id, or: $value.id),
    type: data.get(#type, or: $value.type),
    targetUuid: data.get(#targetUuid, or: $value.targetUuid),
    targetName: data.get(#targetName, or: $value.targetName),
    issuerUuid: data.get(#issuerUuid, or: $value.issuerUuid),
    issuerName: data.get(#issuerName, or: $value.issuerName),
    reason: data.get(#reason, or: $value.reason),
    issuedAt: data.get(#issuedAt, or: $value.issuedAt),
    expiresAt: data.get(#expiresAt, or: $value.expiresAt),
    revokedAt: data.get(#revokedAt, or: $value.revokedAt),
    revokedBy: data.get(#revokedBy, or: $value.revokedBy),
  );

  @override
  PunishmentCopyWith<$R2, Punishment, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PunishmentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PunishmentLogMapper extends ClassMapperBase<PunishmentLog> {
  PunishmentLogMapper._();

  static PunishmentLogMapper? _instance;
  static PunishmentLogMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PunishmentLogMapper._());
      PunishmentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PunishmentLog';

  static int _$nextId(PunishmentLog v) => v.nextId;
  static const Field<PunishmentLog, int> _f$nextId = Field(
    'nextId',
    _$nextId,
    opt: true,
    def: 1,
  );
  static List<Punishment> _$records(PunishmentLog v) => v.records;
  static const Field<PunishmentLog, List<Punishment>> _f$records = Field(
    'records',
    _$records,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<PunishmentLog> fields = const {
    #nextId: _f$nextId,
    #records: _f$records,
  };

  static PunishmentLog _instantiate(DecodingData data) {
    return PunishmentLog(
      nextId: data.dec(_f$nextId),
      records: data.dec(_f$records),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PunishmentLog fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PunishmentLog>(map);
  }

  static PunishmentLog fromJson(String json) {
    return ensureInitialized().decodeJson<PunishmentLog>(json);
  }
}

mixin PunishmentLogMappable {
  String toJson() {
    return PunishmentLogMapper.ensureInitialized().encodeJson<PunishmentLog>(
      this as PunishmentLog,
    );
  }

  Map<String, dynamic> toMap() {
    return PunishmentLogMapper.ensureInitialized().encodeMap<PunishmentLog>(
      this as PunishmentLog,
    );
  }

  PunishmentLogCopyWith<PunishmentLog, PunishmentLog, PunishmentLog>
  get copyWith => _PunishmentLogCopyWithImpl<PunishmentLog, PunishmentLog>(
    this as PunishmentLog,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return PunishmentLogMapper.ensureInitialized().stringifyValue(
      this as PunishmentLog,
    );
  }

  @override
  bool operator ==(Object other) {
    return PunishmentLogMapper.ensureInitialized().equalsValue(
      this as PunishmentLog,
      other,
    );
  }

  @override
  int get hashCode {
    return PunishmentLogMapper.ensureInitialized().hashValue(
      this as PunishmentLog,
    );
  }
}

extension PunishmentLogValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PunishmentLog, $Out> {
  PunishmentLogCopyWith<$R, PunishmentLog, $Out> get $asPunishmentLog =>
      $base.as((v, t, t2) => _PunishmentLogCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PunishmentLogCopyWith<$R, $In extends PunishmentLog, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Punishment, PunishmentCopyWith<$R, Punishment, Punishment>>
  get records;
  $R call({int? nextId, List<Punishment>? records});
  PunishmentLogCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PunishmentLogCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PunishmentLog, $Out>
    implements PunishmentLogCopyWith<$R, PunishmentLog, $Out> {
  _PunishmentLogCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PunishmentLog> $mapper =
      PunishmentLogMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Punishment, PunishmentCopyWith<$R, Punishment, Punishment>>
  get records => ListCopyWith(
    $value.records,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(records: v),
  );
  @override
  $R call({int? nextId, List<Punishment>? records}) => $apply(
    FieldCopyWithData({
      if (nextId != null) #nextId: nextId,
      if (records != null) #records: records,
    }),
  );
  @override
  PunishmentLog $make(CopyWithData data) => PunishmentLog(
    nextId: data.get(#nextId, or: $value.nextId),
    records: data.get(#records, or: $value.records),
  );

  @override
  PunishmentLogCopyWith<$R2, PunishmentLog, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PunishmentLogCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ProtectedPlayersMapper extends ClassMapperBase<ProtectedPlayers> {
  ProtectedPlayersMapper._();

  static ProtectedPlayersMapper? _instance;
  static ProtectedPlayersMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProtectedPlayersMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProtectedPlayers';

  static List<String> _$players(ProtectedPlayers v) => v.players;
  static const Field<ProtectedPlayers, List<String>> _f$players = Field(
    'players',
    _$players,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<ProtectedPlayers> fields = const {#players: _f$players};

  static ProtectedPlayers _instantiate(DecodingData data) {
    return ProtectedPlayers(players: data.dec(_f$players));
  }

  @override
  final Function instantiate = _instantiate;

  static ProtectedPlayers fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProtectedPlayers>(map);
  }

  static ProtectedPlayers fromJson(String json) {
    return ensureInitialized().decodeJson<ProtectedPlayers>(json);
  }
}

mixin ProtectedPlayersMappable {
  String toJson() {
    return ProtectedPlayersMapper.ensureInitialized()
        .encodeJson<ProtectedPlayers>(this as ProtectedPlayers);
  }

  Map<String, dynamic> toMap() {
    return ProtectedPlayersMapper.ensureInitialized()
        .encodeMap<ProtectedPlayers>(this as ProtectedPlayers);
  }

  ProtectedPlayersCopyWith<ProtectedPlayers, ProtectedPlayers, ProtectedPlayers>
  get copyWith =>
      _ProtectedPlayersCopyWithImpl<ProtectedPlayers, ProtectedPlayers>(
        this as ProtectedPlayers,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProtectedPlayersMapper.ensureInitialized().stringifyValue(
      this as ProtectedPlayers,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProtectedPlayersMapper.ensureInitialized().equalsValue(
      this as ProtectedPlayers,
      other,
    );
  }

  @override
  int get hashCode {
    return ProtectedPlayersMapper.ensureInitialized().hashValue(
      this as ProtectedPlayers,
    );
  }
}

extension ProtectedPlayersValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProtectedPlayers, $Out> {
  ProtectedPlayersCopyWith<$R, ProtectedPlayers, $Out>
  get $asProtectedPlayers =>
      $base.as((v, t, t2) => _ProtectedPlayersCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProtectedPlayersCopyWith<$R, $In extends ProtectedPlayers, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get players;
  $R call({List<String>? players});
  ProtectedPlayersCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ProtectedPlayersCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProtectedPlayers, $Out>
    implements ProtectedPlayersCopyWith<$R, ProtectedPlayers, $Out> {
  _ProtectedPlayersCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProtectedPlayers> $mapper =
      ProtectedPlayersMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get players =>
      ListCopyWith(
        $value.players,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(players: v),
      );
  @override
  $R call({List<String>? players}) =>
      $apply(FieldCopyWithData({if (players != null) #players: players}));
  @override
  ProtectedPlayers $make(CopyWithData data) =>
      ProtectedPlayers(players: data.get(#players, or: $value.players));

  @override
  ProtectedPlayersCopyWith<$R2, ProtectedPlayers, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProtectedPlayersCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModerationConfigMapper extends ClassMapperBase<ModerationConfig> {
  ModerationConfigMapper._();

  static ModerationConfigMapper? _instance;
  static ModerationConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModerationConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ModerationConfig';

  static String _$defaultReason(ModerationConfig v) => v.defaultReason;
  static const Field<ModerationConfig, String> _f$defaultReason = Field(
    'defaultReason',
    _$defaultReason,
    opt: true,
    def: 'No reason given',
  );
  static String _$appeal(ModerationConfig v) => v.appeal;
  static const Field<ModerationConfig, String> _f$appeal = Field(
    'appeal',
    _$appeal,
    opt: true,
    def: 'If you think this is a mistake, contact the staff.',
  );
  static String _$defaultMuteDuration(ModerationConfig v) =>
      v.defaultMuteDuration;
  static const Field<ModerationConfig, String> _f$defaultMuteDuration = Field(
    'defaultMuteDuration',
    _$defaultMuteDuration,
    opt: true,
    def: 'perm',
  );
  static String _$warnExpiry(ModerationConfig v) => v.warnExpiry;
  static const Field<ModerationConfig, String> _f$warnExpiry = Field(
    'warnExpiry',
    _$warnExpiry,
    opt: true,
    def: '30d',
  );
  static int _$escalationWarns(ModerationConfig v) => v.escalationWarns;
  static const Field<ModerationConfig, int> _f$escalationWarns = Field(
    'escalationWarns',
    _$escalationWarns,
    opt: true,
    def: 3,
  );
  static String _$escalationWindow(ModerationConfig v) => v.escalationWindow;
  static const Field<ModerationConfig, String> _f$escalationWindow = Field(
    'escalationWindow',
    _$escalationWindow,
    opt: true,
    def: '7d',
  );
  static String _$escalationAction(ModerationConfig v) => v.escalationAction;
  static const Field<ModerationConfig, String> _f$escalationAction = Field(
    'escalationAction',
    _$escalationAction,
    opt: true,
    def: 'mute',
  );
  static String _$escalationDuration(ModerationConfig v) =>
      v.escalationDuration;
  static const Field<ModerationConfig, String> _f$escalationDuration = Field(
    'escalationDuration',
    _$escalationDuration,
    opt: true,
    def: '1h',
  );
  static String _$escalationReason(ModerationConfig v) => v.escalationReason;
  static const Field<ModerationConfig, String> _f$escalationReason = Field(
    'escalationReason',
    _$escalationReason,
    opt: true,
    def: 'Automatic: {count} warnings within {window}',
  );
  static List<String> _$mutedCommands(ModerationConfig v) => v.mutedCommands;
  static const Field<ModerationConfig, List<String>> _f$mutedCommands = Field(
    'mutedCommands',
    _$mutedCommands,
    opt: true,
    def: const [
      'msg',
      'tell',
      'w',
      'whisper',
      'r',
      'reply',
      'me',
      'say',
      'mail',
    ],
  );
  static int _$sweepSeconds(ModerationConfig v) => v.sweepSeconds;
  static const Field<ModerationConfig, int> _f$sweepSeconds = Field(
    'sweepSeconds',
    _$sweepSeconds,
    opt: true,
    def: 30,
  );
  static int _$pageSize(ModerationConfig v) => v.pageSize;
  static const Field<ModerationConfig, int> _f$pageSize = Field(
    'pageSize',
    _$pageSize,
    opt: true,
    def: 8,
  );
  static int _$maxReasonLength(ModerationConfig v) => v.maxReasonLength;
  static const Field<ModerationConfig, int> _f$maxReasonLength = Field(
    'maxReasonLength',
    _$maxReasonLength,
    opt: true,
    def: 200,
  );

  @override
  final MappableFields<ModerationConfig> fields = const {
    #defaultReason: _f$defaultReason,
    #appeal: _f$appeal,
    #defaultMuteDuration: _f$defaultMuteDuration,
    #warnExpiry: _f$warnExpiry,
    #escalationWarns: _f$escalationWarns,
    #escalationWindow: _f$escalationWindow,
    #escalationAction: _f$escalationAction,
    #escalationDuration: _f$escalationDuration,
    #escalationReason: _f$escalationReason,
    #mutedCommands: _f$mutedCommands,
    #sweepSeconds: _f$sweepSeconds,
    #pageSize: _f$pageSize,
    #maxReasonLength: _f$maxReasonLength,
  };

  static ModerationConfig _instantiate(DecodingData data) {
    return ModerationConfig(
      defaultReason: data.dec(_f$defaultReason),
      appeal: data.dec(_f$appeal),
      defaultMuteDuration: data.dec(_f$defaultMuteDuration),
      warnExpiry: data.dec(_f$warnExpiry),
      escalationWarns: data.dec(_f$escalationWarns),
      escalationWindow: data.dec(_f$escalationWindow),
      escalationAction: data.dec(_f$escalationAction),
      escalationDuration: data.dec(_f$escalationDuration),
      escalationReason: data.dec(_f$escalationReason),
      mutedCommands: data.dec(_f$mutedCommands),
      sweepSeconds: data.dec(_f$sweepSeconds),
      pageSize: data.dec(_f$pageSize),
      maxReasonLength: data.dec(_f$maxReasonLength),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModerationConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModerationConfig>(map);
  }

  static ModerationConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ModerationConfig>(json);
  }
}

mixin ModerationConfigMappable {
  String toJson() {
    return ModerationConfigMapper.ensureInitialized()
        .encodeJson<ModerationConfig>(this as ModerationConfig);
  }

  Map<String, dynamic> toMap() {
    return ModerationConfigMapper.ensureInitialized()
        .encodeMap<ModerationConfig>(this as ModerationConfig);
  }

  ModerationConfigCopyWith<ModerationConfig, ModerationConfig, ModerationConfig>
  get copyWith =>
      _ModerationConfigCopyWithImpl<ModerationConfig, ModerationConfig>(
        this as ModerationConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModerationConfigMapper.ensureInitialized().stringifyValue(
      this as ModerationConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModerationConfigMapper.ensureInitialized().equalsValue(
      this as ModerationConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ModerationConfigMapper.ensureInitialized().hashValue(
      this as ModerationConfig,
    );
  }
}

extension ModerationConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModerationConfig, $Out> {
  ModerationConfigCopyWith<$R, ModerationConfig, $Out>
  get $asModerationConfig =>
      $base.as((v, t, t2) => _ModerationConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModerationConfigCopyWith<$R, $In extends ModerationConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get mutedCommands;
  $R call({
    String? defaultReason,
    String? appeal,
    String? defaultMuteDuration,
    String? warnExpiry,
    int? escalationWarns,
    String? escalationWindow,
    String? escalationAction,
    String? escalationDuration,
    String? escalationReason,
    List<String>? mutedCommands,
    int? sweepSeconds,
    int? pageSize,
    int? maxReasonLength,
  });
  ModerationConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ModerationConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModerationConfig, $Out>
    implements ModerationConfigCopyWith<$R, ModerationConfig, $Out> {
  _ModerationConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModerationConfig> $mapper =
      ModerationConfigMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get mutedCommands => ListCopyWith(
    $value.mutedCommands,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(mutedCommands: v),
  );
  @override
  $R call({
    String? defaultReason,
    String? appeal,
    String? defaultMuteDuration,
    String? warnExpiry,
    int? escalationWarns,
    String? escalationWindow,
    String? escalationAction,
    String? escalationDuration,
    String? escalationReason,
    List<String>? mutedCommands,
    int? sweepSeconds,
    int? pageSize,
    int? maxReasonLength,
  }) => $apply(
    FieldCopyWithData({
      if (defaultReason != null) #defaultReason: defaultReason,
      if (appeal != null) #appeal: appeal,
      if (defaultMuteDuration != null)
        #defaultMuteDuration: defaultMuteDuration,
      if (warnExpiry != null) #warnExpiry: warnExpiry,
      if (escalationWarns != null) #escalationWarns: escalationWarns,
      if (escalationWindow != null) #escalationWindow: escalationWindow,
      if (escalationAction != null) #escalationAction: escalationAction,
      if (escalationDuration != null) #escalationDuration: escalationDuration,
      if (escalationReason != null) #escalationReason: escalationReason,
      if (mutedCommands != null) #mutedCommands: mutedCommands,
      if (sweepSeconds != null) #sweepSeconds: sweepSeconds,
      if (pageSize != null) #pageSize: pageSize,
      if (maxReasonLength != null) #maxReasonLength: maxReasonLength,
    }),
  );
  @override
  ModerationConfig $make(CopyWithData data) => ModerationConfig(
    defaultReason: data.get(#defaultReason, or: $value.defaultReason),
    appeal: data.get(#appeal, or: $value.appeal),
    defaultMuteDuration: data.get(
      #defaultMuteDuration,
      or: $value.defaultMuteDuration,
    ),
    warnExpiry: data.get(#warnExpiry, or: $value.warnExpiry),
    escalationWarns: data.get(#escalationWarns, or: $value.escalationWarns),
    escalationWindow: data.get(#escalationWindow, or: $value.escalationWindow),
    escalationAction: data.get(#escalationAction, or: $value.escalationAction),
    escalationDuration: data.get(
      #escalationDuration,
      or: $value.escalationDuration,
    ),
    escalationReason: data.get(#escalationReason, or: $value.escalationReason),
    mutedCommands: data.get(#mutedCommands, or: $value.mutedCommands),
    sweepSeconds: data.get(#sweepSeconds, or: $value.sweepSeconds),
    pageSize: data.get(#pageSize, or: $value.pageSize),
    maxReasonLength: data.get(#maxReasonLength, or: $value.maxReasonLength),
  );

  @override
  ModerationConfigCopyWith<$R2, ModerationConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModerationConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

