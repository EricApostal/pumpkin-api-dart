// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'model.dart';

class AnnouncementModeMapper extends EnumMapper<AnnouncementMode> {
  AnnouncementModeMapper._();

  static AnnouncementModeMapper? _instance;
  static AnnouncementModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AnnouncementModeMapper._());
    }
    return _instance!;
  }

  static AnnouncementMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AnnouncementMode decode(dynamic value) {
    switch (value) {
      case r'chat':
        return AnnouncementMode.chat;
      case r'actionbar':
        return AnnouncementMode.actionbar;
      case r'bossbar':
        return AnnouncementMode.bossbar;
      case r'title':
        return AnnouncementMode.title;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AnnouncementMode self) {
    switch (self) {
      case AnnouncementMode.chat:
        return r'chat';
      case AnnouncementMode.actionbar:
        return r'actionbar';
      case AnnouncementMode.bossbar:
        return r'bossbar';
      case AnnouncementMode.title:
        return r'title';
    }
  }
}

extension AnnouncementModeMapperExtension on AnnouncementMode {
  String toValue() {
    AnnouncementModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AnnouncementMode>(this) as String;
  }
}

class AnnouncementMapper extends ClassMapperBase<Announcement> {
  AnnouncementMapper._();

  static AnnouncementMapper? _instance;
  static AnnouncementMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AnnouncementMapper._());
      AnnouncementModeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Announcement';

  static String _$text(Announcement v) => v.text;
  static const Field<Announcement, String> _f$text = Field('text', _$text);
  static String? _$subtitle(Announcement v) => v.subtitle;
  static const Field<Announcement, String> _f$subtitle = Field(
    'subtitle',
    _$subtitle,
    opt: true,
  );
  static AnnouncementMode _$mode(Announcement v) => v.mode;
  static const Field<Announcement, AnnouncementMode> _f$mode = Field(
    'mode',
    _$mode,
    opt: true,
    def: AnnouncementMode.chat,
  );
  static String? _$command(Announcement v) => v.command;
  static const Field<Announcement, String> _f$command = Field(
    'command',
    _$command,
    opt: true,
  );
  static String? _$url(Announcement v) => v.url;
  static const Field<Announcement, String> _f$url = Field(
    'url',
    _$url,
    opt: true,
  );
  static String? _$hover(Announcement v) => v.hover;
  static const Field<Announcement, String> _f$hover = Field(
    'hover',
    _$hover,
    opt: true,
  );
  static String? _$permission(Announcement v) => v.permission;
  static const Field<Announcement, String> _f$permission = Field(
    'permission',
    _$permission,
    opt: true,
  );
  static String? _$world(Announcement v) => v.world;
  static const Field<Announcement, String> _f$world = Field(
    'world',
    _$world,
    opt: true,
  );

  @override
  final MappableFields<Announcement> fields = const {
    #text: _f$text,
    #subtitle: _f$subtitle,
    #mode: _f$mode,
    #command: _f$command,
    #url: _f$url,
    #hover: _f$hover,
    #permission: _f$permission,
    #world: _f$world,
  };

  static Announcement _instantiate(DecodingData data) {
    return Announcement(
      text: data.dec(_f$text),
      subtitle: data.dec(_f$subtitle),
      mode: data.dec(_f$mode),
      command: data.dec(_f$command),
      url: data.dec(_f$url),
      hover: data.dec(_f$hover),
      permission: data.dec(_f$permission),
      world: data.dec(_f$world),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Announcement fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Announcement>(map);
  }

  static Announcement fromJson(String json) {
    return ensureInitialized().decodeJson<Announcement>(json);
  }
}

mixin AnnouncementMappable {
  String toJson() {
    return AnnouncementMapper.ensureInitialized().encodeJson<Announcement>(
      this as Announcement,
    );
  }

  Map<String, dynamic> toMap() {
    return AnnouncementMapper.ensureInitialized().encodeMap<Announcement>(
      this as Announcement,
    );
  }

  AnnouncementCopyWith<Announcement, Announcement, Announcement> get copyWith =>
      _AnnouncementCopyWithImpl<Announcement, Announcement>(
        this as Announcement,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AnnouncementMapper.ensureInitialized().stringifyValue(
      this as Announcement,
    );
  }

  @override
  bool operator ==(Object other) {
    return AnnouncementMapper.ensureInitialized().equalsValue(
      this as Announcement,
      other,
    );
  }

  @override
  int get hashCode {
    return AnnouncementMapper.ensureInitialized().hashValue(
      this as Announcement,
    );
  }
}

extension AnnouncementValueCopy<$R, $Out>
    on ObjectCopyWith<$R, Announcement, $Out> {
  AnnouncementCopyWith<$R, Announcement, $Out> get $asAnnouncement =>
      $base.as((v, t, t2) => _AnnouncementCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AnnouncementCopyWith<$R, $In extends Announcement, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? text,
    String? subtitle,
    AnnouncementMode? mode,
    String? command,
    String? url,
    String? hover,
    String? permission,
    String? world,
  });
  AnnouncementCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AnnouncementCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Announcement, $Out>
    implements AnnouncementCopyWith<$R, Announcement, $Out> {
  _AnnouncementCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Announcement> $mapper =
      AnnouncementMapper.ensureInitialized();
  @override
  $R call({
    String? text,
    Object? subtitle = $none,
    AnnouncementMode? mode,
    Object? command = $none,
    Object? url = $none,
    Object? hover = $none,
    Object? permission = $none,
    Object? world = $none,
  }) => $apply(
    FieldCopyWithData({
      if (text != null) #text: text,
      if (subtitle != $none) #subtitle: subtitle,
      if (mode != null) #mode: mode,
      if (command != $none) #command: command,
      if (url != $none) #url: url,
      if (hover != $none) #hover: hover,
      if (permission != $none) #permission: permission,
      if (world != $none) #world: world,
    }),
  );
  @override
  Announcement $make(CopyWithData data) => Announcement(
    text: data.get(#text, or: $value.text),
    subtitle: data.get(#subtitle, or: $value.subtitle),
    mode: data.get(#mode, or: $value.mode),
    command: data.get(#command, or: $value.command),
    url: data.get(#url, or: $value.url),
    hover: data.get(#hover, or: $value.hover),
    permission: data.get(#permission, or: $value.permission),
    world: data.get(#world, or: $value.world),
  );

  @override
  AnnouncementCopyWith<$R2, Announcement, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AnnouncementCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AnnouncementsConfigMapper extends ClassMapperBase<AnnouncementsConfig> {
  AnnouncementsConfigMapper._();

  static AnnouncementsConfigMapper? _instance;
  static AnnouncementsConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AnnouncementsConfigMapper._());
      AnnouncementMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AnnouncementsConfig';

  static bool _$enabled(AnnouncementsConfig v) => v.enabled;
  static const Field<AnnouncementsConfig, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static int _$intervalSeconds(AnnouncementsConfig v) => v.intervalSeconds;
  static const Field<AnnouncementsConfig, int> _f$intervalSeconds = Field(
    'intervalSeconds',
    _$intervalSeconds,
    opt: true,
    def: 300,
  );
  static bool _$random(AnnouncementsConfig v) => v.random;
  static const Field<AnnouncementsConfig, bool> _f$random = Field(
    'random',
    _$random,
    opt: true,
    def: false,
  );
  static int _$displaySeconds(AnnouncementsConfig v) => v.displaySeconds;
  static const Field<AnnouncementsConfig, int> _f$displaySeconds = Field(
    'displaySeconds',
    _$displaySeconds,
    opt: true,
    def: 10,
  );
  static String _$bossBarColor(AnnouncementsConfig v) => v.bossBarColor;
  static const Field<AnnouncementsConfig, String> _f$bossBarColor = Field(
    'bossBarColor',
    _$bossBarColor,
    opt: true,
    def: 'yellow',
  );
  static String _$chatPrefix(AnnouncementsConfig v) => v.chatPrefix;
  static const Field<AnnouncementsConfig, String> _f$chatPrefix = Field(
    'chatPrefix',
    _$chatPrefix,
    opt: true,
    def: '&8[&6!&8] &r',
  );
  static int _$utcOffsetMinutes(AnnouncementsConfig v) => v.utcOffsetMinutes;
  static const Field<AnnouncementsConfig, int> _f$utcOffsetMinutes = Field(
    'utcOffsetMinutes',
    _$utcOffsetMinutes,
    opt: true,
    def: 0,
  );
  static List<Announcement> _$messages(AnnouncementsConfig v) => v.messages;
  static const Field<AnnouncementsConfig, List<Announcement>> _f$messages =
      Field(
        'messages',
        _$messages,
        opt: true,
        def: const [
          Announcement(
            text: '&eThere are &6{online} &eplayers online. Say hello in chat!',
          ),
          Announcement(
            text: "&eDon't forget your daily reward! &a[Claim]",
            command: '/daily',
            hover: '&7Click to claim it',
          ),
          Announcement(
            text: '&6{online}/{max} &fplayers online - it is &e{time}',
            mode: AnnouncementMode.bossbar,
          ),
          Announcement(
            text: '&7Tip: write &f@name&7 in chat to get someone\'s attention',
            mode: AnnouncementMode.actionbar,
          ),
        ],
      );

  @override
  final MappableFields<AnnouncementsConfig> fields = const {
    #enabled: _f$enabled,
    #intervalSeconds: _f$intervalSeconds,
    #random: _f$random,
    #displaySeconds: _f$displaySeconds,
    #bossBarColor: _f$bossBarColor,
    #chatPrefix: _f$chatPrefix,
    #utcOffsetMinutes: _f$utcOffsetMinutes,
    #messages: _f$messages,
  };

  static AnnouncementsConfig _instantiate(DecodingData data) {
    return AnnouncementsConfig(
      enabled: data.dec(_f$enabled),
      intervalSeconds: data.dec(_f$intervalSeconds),
      random: data.dec(_f$random),
      displaySeconds: data.dec(_f$displaySeconds),
      bossBarColor: data.dec(_f$bossBarColor),
      chatPrefix: data.dec(_f$chatPrefix),
      utcOffsetMinutes: data.dec(_f$utcOffsetMinutes),
      messages: data.dec(_f$messages),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AnnouncementsConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AnnouncementsConfig>(map);
  }

  static AnnouncementsConfig fromJson(String json) {
    return ensureInitialized().decodeJson<AnnouncementsConfig>(json);
  }
}

mixin AnnouncementsConfigMappable {
  String toJson() {
    return AnnouncementsConfigMapper.ensureInitialized()
        .encodeJson<AnnouncementsConfig>(this as AnnouncementsConfig);
  }

  Map<String, dynamic> toMap() {
    return AnnouncementsConfigMapper.ensureInitialized()
        .encodeMap<AnnouncementsConfig>(this as AnnouncementsConfig);
  }

  AnnouncementsConfigCopyWith<
    AnnouncementsConfig,
    AnnouncementsConfig,
    AnnouncementsConfig
  >
  get copyWith =>
      _AnnouncementsConfigCopyWithImpl<
        AnnouncementsConfig,
        AnnouncementsConfig
      >(this as AnnouncementsConfig, $identity, $identity);
  @override
  String toString() {
    return AnnouncementsConfigMapper.ensureInitialized().stringifyValue(
      this as AnnouncementsConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return AnnouncementsConfigMapper.ensureInitialized().equalsValue(
      this as AnnouncementsConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return AnnouncementsConfigMapper.ensureInitialized().hashValue(
      this as AnnouncementsConfig,
    );
  }
}

extension AnnouncementsConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AnnouncementsConfig, $Out> {
  AnnouncementsConfigCopyWith<$R, AnnouncementsConfig, $Out>
  get $asAnnouncementsConfig => $base.as(
    (v, t, t2) => _AnnouncementsConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AnnouncementsConfigCopyWith<
  $R,
  $In extends AnnouncementsConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    Announcement,
    AnnouncementCopyWith<$R, Announcement, Announcement>
  >
  get messages;
  $R call({
    bool? enabled,
    int? intervalSeconds,
    bool? random,
    int? displaySeconds,
    String? bossBarColor,
    String? chatPrefix,
    int? utcOffsetMinutes,
    List<Announcement>? messages,
  });
  AnnouncementsConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AnnouncementsConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AnnouncementsConfig, $Out>
    implements AnnouncementsConfigCopyWith<$R, AnnouncementsConfig, $Out> {
  _AnnouncementsConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AnnouncementsConfig> $mapper =
      AnnouncementsConfigMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    Announcement,
    AnnouncementCopyWith<$R, Announcement, Announcement>
  >
  get messages => ListCopyWith(
    $value.messages,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(messages: v),
  );
  @override
  $R call({
    bool? enabled,
    int? intervalSeconds,
    bool? random,
    int? displaySeconds,
    String? bossBarColor,
    String? chatPrefix,
    int? utcOffsetMinutes,
    List<Announcement>? messages,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (intervalSeconds != null) #intervalSeconds: intervalSeconds,
      if (random != null) #random: random,
      if (displaySeconds != null) #displaySeconds: displaySeconds,
      if (bossBarColor != null) #bossBarColor: bossBarColor,
      if (chatPrefix != null) #chatPrefix: chatPrefix,
      if (utcOffsetMinutes != null) #utcOffsetMinutes: utcOffsetMinutes,
      if (messages != null) #messages: messages,
    }),
  );
  @override
  AnnouncementsConfig $make(CopyWithData data) => AnnouncementsConfig(
    enabled: data.get(#enabled, or: $value.enabled),
    intervalSeconds: data.get(#intervalSeconds, or: $value.intervalSeconds),
    random: data.get(#random, or: $value.random),
    displaySeconds: data.get(#displaySeconds, or: $value.displaySeconds),
    bossBarColor: data.get(#bossBarColor, or: $value.bossBarColor),
    chatPrefix: data.get(#chatPrefix, or: $value.chatPrefix),
    utcOffsetMinutes: data.get(#utcOffsetMinutes, or: $value.utcOffsetMinutes),
    messages: data.get(#messages, or: $value.messages),
  );

  @override
  AnnouncementsConfigCopyWith<$R2, AnnouncementsConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AnnouncementsConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

