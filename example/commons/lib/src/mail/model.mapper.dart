// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class MailConfigMapper extends ClassMapperBase<MailConfig> {
  MailConfigMapper._();

  static MailConfigMapper? _instance;
  static MailConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MailConfigMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'MailConfig';

  static int _$maxInboxSize(MailConfig v) => v.maxInboxSize;
  static const Field<MailConfig, int> _f$maxInboxSize = Field(
    'maxInboxSize',
    _$maxInboxSize,
    opt: true,
    def: 50,
  );
  static int _$maxMessageLength(MailConfig v) => v.maxMessageLength;
  static const Field<MailConfig, int> _f$maxMessageLength = Field(
    'maxMessageLength',
    _$maxMessageLength,
    opt: true,
    def: 256,
  );
  static int _$sendCooldownSeconds(MailConfig v) => v.sendCooldownSeconds;
  static const Field<MailConfig, int> _f$sendCooldownSeconds = Field(
    'sendCooldownSeconds',
    _$sendCooldownSeconds,
    opt: true,
    def: 30,
  );
  static int _$sentHistorySize(MailConfig v) => v.sentHistorySize;
  static const Field<MailConfig, int> _f$sentHistorySize = Field(
    'sentHistorySize',
    _$sentHistorySize,
    opt: true,
    def: 20,
  );
  static bool _$allowBlocking(MailConfig v) => v.allowBlocking;
  static const Field<MailConfig, bool> _f$allowBlocking = Field(
    'allowBlocking',
    _$allowBlocking,
    opt: true,
    def: true,
  );
  static bool _$notifyOnJoin(MailConfig v) => v.notifyOnJoin;
  static const Field<MailConfig, bool> _f$notifyOnJoin = Field(
    'notifyOnJoin',
    _$notifyOnJoin,
    opt: true,
    def: false,
  );
  static int _$pageSize(MailConfig v) => v.pageSize;
  static const Field<MailConfig, int> _f$pageSize = Field(
    'pageSize',
    _$pageSize,
    opt: true,
    def: 6,
  );

  @override
  final MappableFields<MailConfig> fields = const {
    #maxInboxSize: _f$maxInboxSize,
    #maxMessageLength: _f$maxMessageLength,
    #sendCooldownSeconds: _f$sendCooldownSeconds,
    #sentHistorySize: _f$sentHistorySize,
    #allowBlocking: _f$allowBlocking,
    #notifyOnJoin: _f$notifyOnJoin,
    #pageSize: _f$pageSize,
  };

  static MailConfig _instantiate(DecodingData data) {
    return MailConfig(
      maxInboxSize: data.dec(_f$maxInboxSize),
      maxMessageLength: data.dec(_f$maxMessageLength),
      sendCooldownSeconds: data.dec(_f$sendCooldownSeconds),
      sentHistorySize: data.dec(_f$sentHistorySize),
      allowBlocking: data.dec(_f$allowBlocking),
      notifyOnJoin: data.dec(_f$notifyOnJoin),
      pageSize: data.dec(_f$pageSize),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MailConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MailConfig>(map);
  }

  static MailConfig fromJson(String json) {
    return ensureInitialized().decodeJson<MailConfig>(json);
  }
}

mixin MailConfigMappable {
  String toJson() {
    return MailConfigMapper.ensureInitialized().encodeJson<MailConfig>(
      this as MailConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return MailConfigMapper.ensureInitialized().encodeMap<MailConfig>(
      this as MailConfig,
    );
  }

  MailConfigCopyWith<MailConfig, MailConfig, MailConfig> get copyWith =>
      _MailConfigCopyWithImpl<MailConfig, MailConfig>(
        this as MailConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MailConfigMapper.ensureInitialized().stringifyValue(
      this as MailConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return MailConfigMapper.ensureInitialized().equalsValue(
      this as MailConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return MailConfigMapper.ensureInitialized().hashValue(this as MailConfig);
  }
}

extension MailConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MailConfig, $Out> {
  MailConfigCopyWith<$R, MailConfig, $Out> get $asMailConfig =>
      $base.as((v, t, t2) => _MailConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MailConfigCopyWith<$R, $In extends MailConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? maxInboxSize,
    int? maxMessageLength,
    int? sendCooldownSeconds,
    int? sentHistorySize,
    bool? allowBlocking,
    bool? notifyOnJoin,
    int? pageSize,
  });
  MailConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MailConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MailConfig, $Out>
    implements MailConfigCopyWith<$R, MailConfig, $Out> {
  _MailConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MailConfig> $mapper =
      MailConfigMapper.ensureInitialized();
  @override
  $R call({
    int? maxInboxSize,
    int? maxMessageLength,
    int? sendCooldownSeconds,
    int? sentHistorySize,
    bool? allowBlocking,
    bool? notifyOnJoin,
    int? pageSize,
  }) => $apply(
    FieldCopyWithData({
      if (maxInboxSize != null) #maxInboxSize: maxInboxSize,
      if (maxMessageLength != null) #maxMessageLength: maxMessageLength,
      if (sendCooldownSeconds != null)
        #sendCooldownSeconds: sendCooldownSeconds,
      if (sentHistorySize != null) #sentHistorySize: sentHistorySize,
      if (allowBlocking != null) #allowBlocking: allowBlocking,
      if (notifyOnJoin != null) #notifyOnJoin: notifyOnJoin,
      if (pageSize != null) #pageSize: pageSize,
    }),
  );
  @override
  MailConfig $make(CopyWithData data) => MailConfig(
    maxInboxSize: data.get(#maxInboxSize, or: $value.maxInboxSize),
    maxMessageLength: data.get(#maxMessageLength, or: $value.maxMessageLength),
    sendCooldownSeconds: data.get(
      #sendCooldownSeconds,
      or: $value.sendCooldownSeconds,
    ),
    sentHistorySize: data.get(#sentHistorySize, or: $value.sentHistorySize),
    allowBlocking: data.get(#allowBlocking, or: $value.allowBlocking),
    notifyOnJoin: data.get(#notifyOnJoin, or: $value.notifyOnJoin),
    pageSize: data.get(#pageSize, or: $value.pageSize),
  );

  @override
  MailConfigCopyWith<$R2, MailConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MailConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class MailMessageMapper extends ClassMapperBase<MailMessage> {
  MailMessageMapper._();

  static MailMessageMapper? _instance;
  static MailMessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MailMessageMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'MailMessage';

  static int _$id(MailMessage v) => v.id;
  static const Field<MailMessage, int> _f$id = Field('id', _$id);
  static String _$fromUuid(MailMessage v) => v.fromUuid;
  static const Field<MailMessage, String> _f$fromUuid = Field(
    'fromUuid',
    _$fromUuid,
  );
  static String _$fromName(MailMessage v) => v.fromName;
  static const Field<MailMessage, String> _f$fromName = Field(
    'fromName',
    _$fromName,
  );
  static String _$text(MailMessage v) => v.text;
  static const Field<MailMessage, String> _f$text = Field('text', _$text);
  static DateTime _$sentAt(MailMessage v) => v.sentAt;
  static const Field<MailMessage, DateTime> _f$sentAt = Field(
    'sentAt',
    _$sentAt,
  );
  static bool _$read(MailMessage v) => v.read;
  static const Field<MailMessage, bool> _f$read = Field(
    'read',
    _$read,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<MailMessage> fields = const {
    #id: _f$id,
    #fromUuid: _f$fromUuid,
    #fromName: _f$fromName,
    #text: _f$text,
    #sentAt: _f$sentAt,
    #read: _f$read,
  };

  static MailMessage _instantiate(DecodingData data) {
    return MailMessage(
      id: data.dec(_f$id),
      fromUuid: data.dec(_f$fromUuid),
      fromName: data.dec(_f$fromName),
      text: data.dec(_f$text),
      sentAt: data.dec(_f$sentAt),
      read: data.dec(_f$read),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MailMessage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MailMessage>(map);
  }

  static MailMessage fromJson(String json) {
    return ensureInitialized().decodeJson<MailMessage>(json);
  }
}

mixin MailMessageMappable {
  String toJson() {
    return MailMessageMapper.ensureInitialized().encodeJson<MailMessage>(
      this as MailMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return MailMessageMapper.ensureInitialized().encodeMap<MailMessage>(
      this as MailMessage,
    );
  }

  MailMessageCopyWith<MailMessage, MailMessage, MailMessage> get copyWith =>
      _MailMessageCopyWithImpl<MailMessage, MailMessage>(
        this as MailMessage,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MailMessageMapper.ensureInitialized().stringifyValue(
      this as MailMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return MailMessageMapper.ensureInitialized().equalsValue(
      this as MailMessage,
      other,
    );
  }

  @override
  int get hashCode {
    return MailMessageMapper.ensureInitialized().hashValue(this as MailMessage);
  }
}

extension MailMessageValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MailMessage, $Out> {
  MailMessageCopyWith<$R, MailMessage, $Out> get $asMailMessage =>
      $base.as((v, t, t2) => _MailMessageCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MailMessageCopyWith<$R, $In extends MailMessage, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? id,
    String? fromUuid,
    String? fromName,
    String? text,
    DateTime? sentAt,
    bool? read,
  });
  MailMessageCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MailMessageCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MailMessage, $Out>
    implements MailMessageCopyWith<$R, MailMessage, $Out> {
  _MailMessageCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MailMessage> $mapper =
      MailMessageMapper.ensureInitialized();
  @override
  $R call({
    int? id,
    String? fromUuid,
    String? fromName,
    String? text,
    DateTime? sentAt,
    bool? read,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (fromUuid != null) #fromUuid: fromUuid,
      if (fromName != null) #fromName: fromName,
      if (text != null) #text: text,
      if (sentAt != null) #sentAt: sentAt,
      if (read != null) #read: read,
    }),
  );
  @override
  MailMessage $make(CopyWithData data) => MailMessage(
    id: data.get(#id, or: $value.id),
    fromUuid: data.get(#fromUuid, or: $value.fromUuid),
    fromName: data.get(#fromName, or: $value.fromName),
    text: data.get(#text, or: $value.text),
    sentAt: data.get(#sentAt, or: $value.sentAt),
    read: data.get(#read, or: $value.read),
  );

  @override
  MailMessageCopyWith<$R2, MailMessage, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MailMessageCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SentMailMapper extends ClassMapperBase<SentMail> {
  SentMailMapper._();

  static SentMailMapper? _instance;
  static SentMailMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SentMailMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SentMail';

  static int _$id(SentMail v) => v.id;
  static const Field<SentMail, int> _f$id = Field('id', _$id);
  static String _$toUuid(SentMail v) => v.toUuid;
  static const Field<SentMail, String> _f$toUuid = Field('toUuid', _$toUuid);
  static String _$toName(SentMail v) => v.toName;
  static const Field<SentMail, String> _f$toName = Field('toName', _$toName);
  static String _$text(SentMail v) => v.text;
  static const Field<SentMail, String> _f$text = Field('text', _$text);
  static DateTime _$sentAt(SentMail v) => v.sentAt;
  static const Field<SentMail, DateTime> _f$sentAt = Field('sentAt', _$sentAt);

  @override
  final MappableFields<SentMail> fields = const {
    #id: _f$id,
    #toUuid: _f$toUuid,
    #toName: _f$toName,
    #text: _f$text,
    #sentAt: _f$sentAt,
  };

  static SentMail _instantiate(DecodingData data) {
    return SentMail(
      id: data.dec(_f$id),
      toUuid: data.dec(_f$toUuid),
      toName: data.dec(_f$toName),
      text: data.dec(_f$text),
      sentAt: data.dec(_f$sentAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SentMail fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SentMail>(map);
  }

  static SentMail fromJson(String json) {
    return ensureInitialized().decodeJson<SentMail>(json);
  }
}

mixin SentMailMappable {
  String toJson() {
    return SentMailMapper.ensureInitialized().encodeJson<SentMail>(
      this as SentMail,
    );
  }

  Map<String, dynamic> toMap() {
    return SentMailMapper.ensureInitialized().encodeMap<SentMail>(
      this as SentMail,
    );
  }

  SentMailCopyWith<SentMail, SentMail, SentMail> get copyWith =>
      _SentMailCopyWithImpl<SentMail, SentMail>(
        this as SentMail,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SentMailMapper.ensureInitialized().stringifyValue(this as SentMail);
  }

  @override
  bool operator ==(Object other) {
    return SentMailMapper.ensureInitialized().equalsValue(
      this as SentMail,
      other,
    );
  }

  @override
  int get hashCode {
    return SentMailMapper.ensureInitialized().hashValue(this as SentMail);
  }
}

extension SentMailValueCopy<$R, $Out> on ObjectCopyWith<$R, SentMail, $Out> {
  SentMailCopyWith<$R, SentMail, $Out> get $asSentMail =>
      $base.as((v, t, t2) => _SentMailCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SentMailCopyWith<$R, $In extends SentMail, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? id,
    String? toUuid,
    String? toName,
    String? text,
    DateTime? sentAt,
  });
  SentMailCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SentMailCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SentMail, $Out>
    implements SentMailCopyWith<$R, SentMail, $Out> {
  _SentMailCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SentMail> $mapper =
      SentMailMapper.ensureInitialized();
  @override
  $R call({
    int? id,
    String? toUuid,
    String? toName,
    String? text,
    DateTime? sentAt,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (toUuid != null) #toUuid: toUuid,
      if (toName != null) #toName: toName,
      if (text != null) #text: text,
      if (sentAt != null) #sentAt: sentAt,
    }),
  );
  @override
  SentMail $make(CopyWithData data) => SentMail(
    id: data.get(#id, or: $value.id),
    toUuid: data.get(#toUuid, or: $value.toUuid),
    toName: data.get(#toName, or: $value.toName),
    text: data.get(#text, or: $value.text),
    sentAt: data.get(#sentAt, or: $value.sentAt),
  );

  @override
  SentMailCopyWith<$R2, SentMail, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SentMailCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class MailDataMapper extends ClassMapperBase<MailData> {
  MailDataMapper._();

  static MailDataMapper? _instance;
  static MailDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MailDataMapper._());
      MailMessageMapper.ensureInitialized();
      SentMailMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'MailData';

  static int _$nextId(MailData v) => v.nextId;
  static const Field<MailData, int> _f$nextId = Field(
    'nextId',
    _$nextId,
    opt: true,
    def: 1,
  );
  static Map<String, List<MailMessage>> _$inboxes(MailData v) => v.inboxes;
  static const Field<MailData, Map<String, List<MailMessage>>> _f$inboxes =
      Field('inboxes', _$inboxes, opt: true, def: const {});
  static Map<String, List<SentMail>> _$sent(MailData v) => v.sent;
  static const Field<MailData, Map<String, List<SentMail>>> _f$sent = Field(
    'sent',
    _$sent,
    opt: true,
    def: const {},
  );
  static Map<String, List<String>> _$blocked(MailData v) => v.blocked;
  static const Field<MailData, Map<String, List<String>>> _f$blocked = Field(
    'blocked',
    _$blocked,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<MailData> fields = const {
    #nextId: _f$nextId,
    #inboxes: _f$inboxes,
    #sent: _f$sent,
    #blocked: _f$blocked,
  };

  static MailData _instantiate(DecodingData data) {
    return MailData(
      nextId: data.dec(_f$nextId),
      inboxes: data.dec(_f$inboxes),
      sent: data.dec(_f$sent),
      blocked: data.dec(_f$blocked),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MailData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MailData>(map);
  }

  static MailData fromJson(String json) {
    return ensureInitialized().decodeJson<MailData>(json);
  }
}

mixin MailDataMappable {
  String toJson() {
    return MailDataMapper.ensureInitialized().encodeJson<MailData>(
      this as MailData,
    );
  }

  Map<String, dynamic> toMap() {
    return MailDataMapper.ensureInitialized().encodeMap<MailData>(
      this as MailData,
    );
  }

  MailDataCopyWith<MailData, MailData, MailData> get copyWith =>
      _MailDataCopyWithImpl<MailData, MailData>(
        this as MailData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MailDataMapper.ensureInitialized().stringifyValue(this as MailData);
  }

  @override
  bool operator ==(Object other) {
    return MailDataMapper.ensureInitialized().equalsValue(
      this as MailData,
      other,
    );
  }

  @override
  int get hashCode {
    return MailDataMapper.ensureInitialized().hashValue(this as MailData);
  }
}

extension MailDataValueCopy<$R, $Out> on ObjectCopyWith<$R, MailData, $Out> {
  MailDataCopyWith<$R, MailData, $Out> get $asMailData =>
      $base.as((v, t, t2) => _MailDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MailDataCopyWith<$R, $In extends MailData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    List<MailMessage>,
    ObjectCopyWith<$R, List<MailMessage>, List<MailMessage>>
  >
  get inboxes;
  MapCopyWith<
    $R,
    String,
    List<SentMail>,
    ObjectCopyWith<$R, List<SentMail>, List<SentMail>>
  >
  get sent;
  MapCopyWith<
    $R,
    String,
    List<String>,
    ObjectCopyWith<$R, List<String>, List<String>>
  >
  get blocked;
  $R call({
    int? nextId,
    Map<String, List<MailMessage>>? inboxes,
    Map<String, List<SentMail>>? sent,
    Map<String, List<String>>? blocked,
  });
  MailDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MailDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MailData, $Out>
    implements MailDataCopyWith<$R, MailData, $Out> {
  _MailDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MailData> $mapper =
      MailDataMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    List<MailMessage>,
    ObjectCopyWith<$R, List<MailMessage>, List<MailMessage>>
  >
  get inboxes => MapCopyWith(
    $value.inboxes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(inboxes: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    List<SentMail>,
    ObjectCopyWith<$R, List<SentMail>, List<SentMail>>
  >
  get sent => MapCopyWith(
    $value.sent,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(sent: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    List<String>,
    ObjectCopyWith<$R, List<String>, List<String>>
  >
  get blocked => MapCopyWith(
    $value.blocked,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(blocked: v),
  );
  @override
  $R call({
    int? nextId,
    Map<String, List<MailMessage>>? inboxes,
    Map<String, List<SentMail>>? sent,
    Map<String, List<String>>? blocked,
  }) => $apply(
    FieldCopyWithData({
      if (nextId != null) #nextId: nextId,
      if (inboxes != null) #inboxes: inboxes,
      if (sent != null) #sent: sent,
      if (blocked != null) #blocked: blocked,
    }),
  );
  @override
  MailData $make(CopyWithData data) => MailData(
    nextId: data.get(#nextId, or: $value.nextId),
    inboxes: data.get(#inboxes, or: $value.inboxes),
    sent: data.get(#sent, or: $value.sent),
    blocked: data.get(#blocked, or: $value.blocked),
  );

  @override
  MailDataCopyWith<$R2, MailData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MailDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

