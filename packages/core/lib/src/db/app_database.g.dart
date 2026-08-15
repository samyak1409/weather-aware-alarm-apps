// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CourtsTable extends Courts with TableInfo<$CourtsTable, Court> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourtsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PlaceSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PlaceSource>($CourtsTable.$convertersource);
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  @override
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    lat,
    lon,
    source,
    region,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'courts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Court> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Court map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Court(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      source: $CourtsTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $CourtsTable createAlias(String alias) {
    return $CourtsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PlaceSource, String, String> $convertersource =
      const EnumNameConverter<PlaceSource>(PlaceSource.values);
}

class Court extends DataClass implements Insertable<Court> {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final PlaceSource source;
  final String? region;
  final int position;
  const Court({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.source,
    this.region,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    {
      map['source'] = Variable<String>(
        $CourtsTable.$convertersource.toSql(source),
      );
    }
    if (!nullToAbsent || region != null) {
      map['region'] = Variable<String>(region);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  CourtsCompanion toCompanion(bool nullToAbsent) {
    return CourtsCompanion(
      id: Value(id),
      name: Value(name),
      lat: Value(lat),
      lon: Value(lon),
      source: Value(source),
      region: region == null && nullToAbsent
          ? const Value.absent()
          : Value(region),
      position: Value(position),
    );
  }

  factory Court.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Court(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      source: $CourtsTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      region: serializer.fromJson<String?>(json['region']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'source': serializer.toJson<String>(
        $CourtsTable.$convertersource.toJson(source),
      ),
      'region': serializer.toJson<String?>(region),
      'position': serializer.toJson<int>(position),
    };
  }

  Court copyWith({
    String? id,
    String? name,
    double? lat,
    double? lon,
    PlaceSource? source,
    Value<String?> region = const Value.absent(),
    int? position,
  }) => Court(
    id: id ?? this.id,
    name: name ?? this.name,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    source: source ?? this.source,
    region: region.present ? region.value : this.region,
    position: position ?? this.position,
  );
  Court copyWithCompanion(CourtsCompanion data) {
    return Court(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      source: data.source.present ? data.source.value : this.source,
      region: data.region.present ? data.region.value : this.region,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Court(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('source: $source, ')
          ..write('region: $region, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, lat, lon, source, region, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Court &&
          other.id == this.id &&
          other.name == this.name &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.source == this.source &&
          other.region == this.region &&
          other.position == this.position);
}

class CourtsCompanion extends UpdateCompanion<Court> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> lat;
  final Value<double> lon;
  final Value<PlaceSource> source;
  final Value<String?> region;
  final Value<int> position;
  final Value<int> rowid;
  const CourtsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.source = const Value.absent(),
    this.region = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CourtsCompanion.insert({
    required String id,
    required String name,
    required double lat,
    required double lon,
    required PlaceSource source,
    this.region = const Value.absent(),
    required int position,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       lat = Value(lat),
       lon = Value(lon),
       source = Value(source),
       position = Value(position);
  static Insertable<Court> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<String>? source,
    Expression<String>? region,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (source != null) 'source': source,
      if (region != null) 'region': region,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CourtsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? lat,
    Value<double>? lon,
    Value<PlaceSource>? source,
    Value<String?>? region,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return CourtsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      source: source ?? this.source,
      region: region ?? this.region,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $CourtsTable.$convertersource.toSql(source.value),
      );
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourtsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('source: $source, ')
          ..write('region: $region, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NivaatAlarmsTable extends NivaatAlarms
    with TableInfo<$NivaatAlarmsTable, AlarmRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NivaatAlarmsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hourMeta = const VerificationMeta('hour');
  @override
  late final GeneratedColumn<int> hour = GeneratedColumn<int>(
    'hour',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minuteMeta = const VerificationMeta('minute');
  @override
  late final GeneratedColumn<int> minute = GeneratedColumn<int>(
    'minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courtIdMeta = const VerificationMeta(
    'courtId',
  );
  @override
  late final GeneratedColumn<String> courtId = GeneratedColumn<String>(
    'court_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courtSpeedLimitKmhMeta =
      const VerificationMeta('courtSpeedLimitKmh');
  @override
  late final GeneratedColumn<int> courtSpeedLimitKmh = GeneratedColumn<int>(
    'court_speed_limit_kmh',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryMinutesAfterMeta = const VerificationMeta(
    'retryMinutesAfter',
  );
  @override
  late final GeneratedColumn<int> retryMinutesAfter = GeneratedColumn<int>(
    'retry_minutes_after',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Set<int>, String> weekdays =
      GeneratedColumn<String>(
        'weekdays',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Set<int>>($NivaatAlarmsTable.$converterweekdays);
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hour,
    minute,
    courtId,
    courtSpeedLimitKmh,
    retryMinutesAfter,
    weekdays,
    enabled,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nivaat_alarms';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('hour')) {
      context.handle(
        _hourMeta,
        hour.isAcceptableOrUnknown(data['hour']!, _hourMeta),
      );
    } else if (isInserting) {
      context.missing(_hourMeta);
    }
    if (data.containsKey('minute')) {
      context.handle(
        _minuteMeta,
        minute.isAcceptableOrUnknown(data['minute']!, _minuteMeta),
      );
    } else if (isInserting) {
      context.missing(_minuteMeta);
    }
    if (data.containsKey('court_id')) {
      context.handle(
        _courtIdMeta,
        courtId.isAcceptableOrUnknown(data['court_id']!, _courtIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courtIdMeta);
    }
    if (data.containsKey('court_speed_limit_kmh')) {
      context.handle(
        _courtSpeedLimitKmhMeta,
        courtSpeedLimitKmh.isAcceptableOrUnknown(
          data['court_speed_limit_kmh']!,
          _courtSpeedLimitKmhMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_courtSpeedLimitKmhMeta);
    }
    if (data.containsKey('retry_minutes_after')) {
      context.handle(
        _retryMinutesAfterMeta,
        retryMinutesAfter.isAcceptableOrUnknown(
          data['retry_minutes_after']!,
          _retryMinutesAfterMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_retryMinutesAfterMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    } else if (isInserting) {
      context.missing(_enabledMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      hour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hour'],
      )!,
      minute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minute'],
      )!,
      courtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}court_id'],
      )!,
      courtSpeedLimitKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}court_speed_limit_kmh'],
      )!,
      retryMinutesAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_minutes_after'],
      )!,
      weekdays: $NivaatAlarmsTable.$converterweekdays.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}weekdays'],
        )!,
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $NivaatAlarmsTable createAlias(String alias) {
    return $NivaatAlarmsTable(attachedDatabase, alias);
  }

  static TypeConverter<Set<int>, String> $converterweekdays = weekdaySet;
}

class AlarmRow extends DataClass implements Insertable<AlarmRow> {
  final int id;
  final int hour;
  final int minute;
  final String courtId;
  final int courtSpeedLimitKmh;
  final int retryMinutesAfter;
  final Set<int> weekdays;
  final bool enabled;
  final int position;
  const AlarmRow({
    required this.id,
    required this.hour,
    required this.minute,
    required this.courtId,
    required this.courtSpeedLimitKmh,
    required this.retryMinutesAfter,
    required this.weekdays,
    required this.enabled,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['hour'] = Variable<int>(hour);
    map['minute'] = Variable<int>(minute);
    map['court_id'] = Variable<String>(courtId);
    map['court_speed_limit_kmh'] = Variable<int>(courtSpeedLimitKmh);
    map['retry_minutes_after'] = Variable<int>(retryMinutesAfter);
    {
      map['weekdays'] = Variable<String>(
        $NivaatAlarmsTable.$converterweekdays.toSql(weekdays),
      );
    }
    map['enabled'] = Variable<bool>(enabled);
    map['position'] = Variable<int>(position);
    return map;
  }

  NivaatAlarmsCompanion toCompanion(bool nullToAbsent) {
    return NivaatAlarmsCompanion(
      id: Value(id),
      hour: Value(hour),
      minute: Value(minute),
      courtId: Value(courtId),
      courtSpeedLimitKmh: Value(courtSpeedLimitKmh),
      retryMinutesAfter: Value(retryMinutesAfter),
      weekdays: Value(weekdays),
      enabled: Value(enabled),
      position: Value(position),
    );
  }

  factory AlarmRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmRow(
      id: serializer.fromJson<int>(json['id']),
      hour: serializer.fromJson<int>(json['hour']),
      minute: serializer.fromJson<int>(json['minute']),
      courtId: serializer.fromJson<String>(json['courtId']),
      courtSpeedLimitKmh: serializer.fromJson<int>(json['courtSpeedLimitKmh']),
      retryMinutesAfter: serializer.fromJson<int>(json['retryMinutesAfter']),
      weekdays: serializer.fromJson<Set<int>>(json['weekdays']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'hour': serializer.toJson<int>(hour),
      'minute': serializer.toJson<int>(minute),
      'courtId': serializer.toJson<String>(courtId),
      'courtSpeedLimitKmh': serializer.toJson<int>(courtSpeedLimitKmh),
      'retryMinutesAfter': serializer.toJson<int>(retryMinutesAfter),
      'weekdays': serializer.toJson<Set<int>>(weekdays),
      'enabled': serializer.toJson<bool>(enabled),
      'position': serializer.toJson<int>(position),
    };
  }

  AlarmRow copyWith({
    int? id,
    int? hour,
    int? minute,
    String? courtId,
    int? courtSpeedLimitKmh,
    int? retryMinutesAfter,
    Set<int>? weekdays,
    bool? enabled,
    int? position,
  }) => AlarmRow(
    id: id ?? this.id,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    courtId: courtId ?? this.courtId,
    courtSpeedLimitKmh: courtSpeedLimitKmh ?? this.courtSpeedLimitKmh,
    retryMinutesAfter: retryMinutesAfter ?? this.retryMinutesAfter,
    weekdays: weekdays ?? this.weekdays,
    enabled: enabled ?? this.enabled,
    position: position ?? this.position,
  );
  AlarmRow copyWithCompanion(NivaatAlarmsCompanion data) {
    return AlarmRow(
      id: data.id.present ? data.id.value : this.id,
      hour: data.hour.present ? data.hour.value : this.hour,
      minute: data.minute.present ? data.minute.value : this.minute,
      courtId: data.courtId.present ? data.courtId.value : this.courtId,
      courtSpeedLimitKmh: data.courtSpeedLimitKmh.present
          ? data.courtSpeedLimitKmh.value
          : this.courtSpeedLimitKmh,
      retryMinutesAfter: data.retryMinutesAfter.present
          ? data.retryMinutesAfter.value
          : this.retryMinutesAfter,
      weekdays: data.weekdays.present ? data.weekdays.value : this.weekdays,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmRow(')
          ..write('id: $id, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('courtId: $courtId, ')
          ..write('courtSpeedLimitKmh: $courtSpeedLimitKmh, ')
          ..write('retryMinutesAfter: $retryMinutesAfter, ')
          ..write('weekdays: $weekdays, ')
          ..write('enabled: $enabled, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hour,
    minute,
    courtId,
    courtSpeedLimitKmh,
    retryMinutesAfter,
    weekdays,
    enabled,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmRow &&
          other.id == this.id &&
          other.hour == this.hour &&
          other.minute == this.minute &&
          other.courtId == this.courtId &&
          other.courtSpeedLimitKmh == this.courtSpeedLimitKmh &&
          other.retryMinutesAfter == this.retryMinutesAfter &&
          other.weekdays == this.weekdays &&
          other.enabled == this.enabled &&
          other.position == this.position);
}

class NivaatAlarmsCompanion extends UpdateCompanion<AlarmRow> {
  final Value<int> id;
  final Value<int> hour;
  final Value<int> minute;
  final Value<String> courtId;
  final Value<int> courtSpeedLimitKmh;
  final Value<int> retryMinutesAfter;
  final Value<Set<int>> weekdays;
  final Value<bool> enabled;
  final Value<int> position;
  const NivaatAlarmsCompanion({
    this.id = const Value.absent(),
    this.hour = const Value.absent(),
    this.minute = const Value.absent(),
    this.courtId = const Value.absent(),
    this.courtSpeedLimitKmh = const Value.absent(),
    this.retryMinutesAfter = const Value.absent(),
    this.weekdays = const Value.absent(),
    this.enabled = const Value.absent(),
    this.position = const Value.absent(),
  });
  NivaatAlarmsCompanion.insert({
    this.id = const Value.absent(),
    required int hour,
    required int minute,
    required String courtId,
    required int courtSpeedLimitKmh,
    required int retryMinutesAfter,
    required Set<int> weekdays,
    required bool enabled,
    required int position,
  }) : hour = Value(hour),
       minute = Value(minute),
       courtId = Value(courtId),
       courtSpeedLimitKmh = Value(courtSpeedLimitKmh),
       retryMinutesAfter = Value(retryMinutesAfter),
       weekdays = Value(weekdays),
       enabled = Value(enabled),
       position = Value(position);
  static Insertable<AlarmRow> custom({
    Expression<int>? id,
    Expression<int>? hour,
    Expression<int>? minute,
    Expression<String>? courtId,
    Expression<int>? courtSpeedLimitKmh,
    Expression<int>? retryMinutesAfter,
    Expression<String>? weekdays,
    Expression<bool>? enabled,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hour != null) 'hour': hour,
      if (minute != null) 'minute': minute,
      if (courtId != null) 'court_id': courtId,
      if (courtSpeedLimitKmh != null)
        'court_speed_limit_kmh': courtSpeedLimitKmh,
      if (retryMinutesAfter != null) 'retry_minutes_after': retryMinutesAfter,
      if (weekdays != null) 'weekdays': weekdays,
      if (enabled != null) 'enabled': enabled,
      if (position != null) 'position': position,
    });
  }

  NivaatAlarmsCompanion copyWith({
    Value<int>? id,
    Value<int>? hour,
    Value<int>? minute,
    Value<String>? courtId,
    Value<int>? courtSpeedLimitKmh,
    Value<int>? retryMinutesAfter,
    Value<Set<int>>? weekdays,
    Value<bool>? enabled,
    Value<int>? position,
  }) {
    return NivaatAlarmsCompanion(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      courtId: courtId ?? this.courtId,
      courtSpeedLimitKmh: courtSpeedLimitKmh ?? this.courtSpeedLimitKmh,
      retryMinutesAfter: retryMinutesAfter ?? this.retryMinutesAfter,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (hour.present) {
      map['hour'] = Variable<int>(hour.value);
    }
    if (minute.present) {
      map['minute'] = Variable<int>(minute.value);
    }
    if (courtId.present) {
      map['court_id'] = Variable<String>(courtId.value);
    }
    if (courtSpeedLimitKmh.present) {
      map['court_speed_limit_kmh'] = Variable<int>(courtSpeedLimitKmh.value);
    }
    if (retryMinutesAfter.present) {
      map['retry_minutes_after'] = Variable<int>(retryMinutesAfter.value);
    }
    if (weekdays.present) {
      map['weekdays'] = Variable<String>(
        $NivaatAlarmsTable.$converterweekdays.toSql(weekdays.value),
      );
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NivaatAlarmsCompanion(')
          ..write('id: $id, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('courtId: $courtId, ')
          ..write('courtSpeedLimitKmh: $courtSpeedLimitKmh, ')
          ..write('retryMinutesAfter: $retryMinutesAfter, ')
          ..write('weekdays: $weekdays, ')
          ..write('enabled: $enabled, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $CountersTable extends Counters with TableInfo<$CountersTable, Counter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CountersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [name, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'counters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Counter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  Counter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Counter(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $CountersTable createAlias(String alias) {
    return $CountersTable(attachedDatabase, alias);
  }
}

class Counter extends DataClass implements Insertable<Counter> {
  final String name;
  final int value;
  const Counter({required this.name, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['value'] = Variable<int>(value);
    return map;
  }

  CountersCompanion toCompanion(bool nullToAbsent) {
    return CountersCompanion(name: Value(name), value: Value(value));
  }

  factory Counter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Counter(
      name: serializer.fromJson<String>(json['name']),
      value: serializer.fromJson<int>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'value': serializer.toJson<int>(value),
    };
  }

  Counter copyWith({String? name, int? value}) =>
      Counter(name: name ?? this.name, value: value ?? this.value);
  Counter copyWithCompanion(CountersCompanion data) {
    return Counter(
      name: data.name.present ? data.name.value : this.name,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Counter(')
          ..write('name: $name, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Counter &&
          other.name == this.name &&
          other.value == this.value);
}

class CountersCompanion extends UpdateCompanion<Counter> {
  final Value<String> name;
  final Value<int> value;
  final Value<int> rowid;
  const CountersCompanion({
    this.name = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CountersCompanion.insert({
    required String name,
    required int value,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       value = Value(value);
  static Insertable<Counter> custom({
    Expression<String>? name,
    Expression<int>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CountersCompanion copyWith({
    Value<String>? name,
    Value<int>? value,
    Value<int>? rowid,
  }) {
    return CountersCompanion(
      name: name ?? this.name,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CountersCompanion(')
          ..write('name: $name, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryEntriesTable extends HistoryEntries
    with TableInfo<$HistoryEntriesTable, HistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowSeqMeta = const VerificationMeta('rowSeq');
  @override
  late final GeneratedColumn<int> rowSeq = GeneratedColumn<int>(
    'row_seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _alarmIdMeta = const VerificationMeta(
    'alarmId',
  );
  @override
  late final GeneratedColumn<int> alarmId = GeneratedColumn<int>(
    'alarm_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> at =
      GeneratedColumn<int>(
        'at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($HistoryEntriesTable.$converterat);
  static const VerificationMeta _pushSeqMeta = const VerificationMeta(
    'pushSeq',
  );
  @override
  late final GeneratedColumn<int> pushSeq = GeneratedColumn<int>(
    'push_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courtIdMeta = const VerificationMeta(
    'courtId',
  );
  @override
  late final GeneratedColumn<String> courtId = GeneratedColumn<String>(
    'court_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CheckOutcome, String> outcome =
      GeneratedColumn<String>(
        'outcome',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CheckOutcome>($HistoryEntriesTable.$converteroutcome);
  @override
  late final GeneratedColumnWithTypeConverter<HistoryKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<HistoryKind>($HistoryEntriesTable.$converterkind);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> checkedAt =
      GeneratedColumn<int>(
        'checked_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($HistoryEntriesTable.$convertercheckedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> watchedUntil =
      GeneratedColumn<int>(
        'watched_until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($HistoryEntriesTable.$converterwatchedUntil);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> checkingEndedAt =
      GeneratedColumn<int>(
        'checking_ended_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>(
        $HistoryEntriesTable.$convertercheckingEndedAt,
      );
  static const VerificationMeta _courtSpeedKmhMeta = const VerificationMeta(
    'courtSpeedKmh',
  );
  @override
  late final GeneratedColumn<double> courtSpeedKmh = GeneratedColumn<double>(
    'court_speed_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawGustKmhMeta = const VerificationMeta(
    'rawGustKmh',
  );
  @override
  late final GeneratedColumn<double> rawGustKmh = GeneratedColumn<double>(
    'raw_gust_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _courtSpeedLimitKmhMeta =
      const VerificationMeta('courtSpeedLimitKmh');
  @override
  late final GeneratedColumn<int> courtSpeedLimitKmh = GeneratedColumn<int>(
    'court_speed_limit_kmh',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawGustLimitKmhMeta = const VerificationMeta(
    'rawGustLimitKmh',
  );
  @override
  late final GeneratedColumn<double> rawGustLimitKmh = GeneratedColumn<double>(
    'raw_gust_limit_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<double> volume = GeneratedColumn<double>(
    'volume',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RingDisposition?, String>
  ringDisposition =
      GeneratedColumn<String>(
        'ring_disposition',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<RingDisposition?>(
        $HistoryEntriesTable.$converterringDispositionn,
      );
  static const VerificationMeta _hostEventKeyMeta = const VerificationMeta(
    'hostEventKey',
  );
  @override
  late final GeneratedColumn<String> hostEventKey = GeneratedColumn<String>(
    'host_event_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    rowSeq,
    alarmId,
    at,
    pushSeq,
    courtId,
    outcome,
    kind,
    checkedAt,
    watchedUntil,
    checkingEndedAt,
    courtSpeedKmh,
    rawGustKmh,
    courtSpeedLimitKmh,
    rawGustLimitKmh,
    volume,
    ringDisposition,
    hostEventKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_seq')) {
      context.handle(
        _rowSeqMeta,
        rowSeq.isAcceptableOrUnknown(data['row_seq']!, _rowSeqMeta),
      );
    }
    if (data.containsKey('alarm_id')) {
      context.handle(
        _alarmIdMeta,
        alarmId.isAcceptableOrUnknown(data['alarm_id']!, _alarmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_alarmIdMeta);
    }
    if (data.containsKey('push_seq')) {
      context.handle(
        _pushSeqMeta,
        pushSeq.isAcceptableOrUnknown(data['push_seq']!, _pushSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_pushSeqMeta);
    }
    if (data.containsKey('court_id')) {
      context.handle(
        _courtIdMeta,
        courtId.isAcceptableOrUnknown(data['court_id']!, _courtIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courtIdMeta);
    }
    if (data.containsKey('court_speed_kmh')) {
      context.handle(
        _courtSpeedKmhMeta,
        courtSpeedKmh.isAcceptableOrUnknown(
          data['court_speed_kmh']!,
          _courtSpeedKmhMeta,
        ),
      );
    }
    if (data.containsKey('raw_gust_kmh')) {
      context.handle(
        _rawGustKmhMeta,
        rawGustKmh.isAcceptableOrUnknown(
          data['raw_gust_kmh']!,
          _rawGustKmhMeta,
        ),
      );
    }
    if (data.containsKey('court_speed_limit_kmh')) {
      context.handle(
        _courtSpeedLimitKmhMeta,
        courtSpeedLimitKmh.isAcceptableOrUnknown(
          data['court_speed_limit_kmh']!,
          _courtSpeedLimitKmhMeta,
        ),
      );
    }
    if (data.containsKey('raw_gust_limit_kmh')) {
      context.handle(
        _rawGustLimitKmhMeta,
        rawGustLimitKmh.isAcceptableOrUnknown(
          data['raw_gust_limit_kmh']!,
          _rawGustLimitKmhMeta,
        ),
      );
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    if (data.containsKey('host_event_key')) {
      context.handle(
        _hostEventKeyMeta,
        hostEventKey.isAcceptableOrUnknown(
          data['host_event_key']!,
          _hostEventKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowSeq};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {alarmId, at, pushSeq},
  ];
  @override
  HistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryEntry(
      rowSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_seq'],
      )!,
      alarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alarm_id'],
      )!,
      at: $HistoryEntriesTable.$converterat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}at'],
        )!,
      ),
      pushSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}push_seq'],
      )!,
      courtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}court_id'],
      )!,
      outcome: $HistoryEntriesTable.$converteroutcome.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}outcome'],
        )!,
      ),
      kind: $HistoryEntriesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      checkedAt: $HistoryEntriesTable.$convertercheckedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}checked_at'],
        ),
      ),
      watchedUntil: $HistoryEntriesTable.$converterwatchedUntil.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}watched_until'],
        ),
      ),
      checkingEndedAt: $HistoryEntriesTable.$convertercheckingEndedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}checking_ended_at'],
        ),
      ),
      courtSpeedKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}court_speed_kmh'],
      ),
      rawGustKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}raw_gust_kmh'],
      ),
      courtSpeedLimitKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}court_speed_limit_kmh'],
      ),
      rawGustLimitKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}raw_gust_limit_kmh'],
      ),
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume'],
      ),
      ringDisposition: $HistoryEntriesTable.$converterringDispositionn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ring_disposition'],
        ),
      ),
      hostEventKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_event_key'],
      ),
    );
  }

  @override
  $HistoryEntriesTable createAlias(String alias) {
    return $HistoryEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterat = dateTimeMicros;
  static JsonTypeConverter2<CheckOutcome, String, String> $converteroutcome =
      const EnumNameConverter<CheckOutcome>(CheckOutcome.values);
  static JsonTypeConverter2<HistoryKind, String, String> $converterkind =
      const EnumNameConverter<HistoryKind>(HistoryKind.values);
  static TypeConverter<DateTime?, int?> $convertercheckedAt =
      nullableDateTimeMicros;
  static TypeConverter<DateTime?, int?> $converterwatchedUntil =
      nullableDateTimeMicros;
  static TypeConverter<DateTime?, int?> $convertercheckingEndedAt =
      nullableDateTimeMicros;
  static JsonTypeConverter2<RingDisposition, String, String>
  $converterringDisposition = const EnumNameConverter<RingDisposition>(
    RingDisposition.values,
  );
  static JsonTypeConverter2<RingDisposition?, String?, String?>
  $converterringDispositionn = JsonTypeConverter2.asNullable(
    $converterringDisposition,
  );
}

class HistoryEntry extends DataClass implements Insertable<HistoryEntry> {
  final int rowSeq;
  final int alarmId;
  final DateTime at;
  final int pushSeq;
  final String courtId;
  final CheckOutcome outcome;
  final HistoryKind kind;
  final DateTime? checkedAt;
  final DateTime? watchedUntil;
  final DateTime? checkingEndedAt;
  final double? courtSpeedKmh;
  final double? rawGustKmh;
  final int? courtSpeedLimitKmh;
  final double? rawGustLimitKmh;
  final double? volume;
  final RingDisposition? ringDisposition;
  final String? hostEventKey;
  const HistoryEntry({
    required this.rowSeq,
    required this.alarmId,
    required this.at,
    required this.pushSeq,
    required this.courtId,
    required this.outcome,
    required this.kind,
    this.checkedAt,
    this.watchedUntil,
    this.checkingEndedAt,
    this.courtSpeedKmh,
    this.rawGustKmh,
    this.courtSpeedLimitKmh,
    this.rawGustLimitKmh,
    this.volume,
    this.ringDisposition,
    this.hostEventKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_seq'] = Variable<int>(rowSeq);
    map['alarm_id'] = Variable<int>(alarmId);
    {
      map['at'] = Variable<int>($HistoryEntriesTable.$converterat.toSql(at));
    }
    map['push_seq'] = Variable<int>(pushSeq);
    map['court_id'] = Variable<String>(courtId);
    {
      map['outcome'] = Variable<String>(
        $HistoryEntriesTable.$converteroutcome.toSql(outcome),
      );
    }
    {
      map['kind'] = Variable<String>(
        $HistoryEntriesTable.$converterkind.toSql(kind),
      );
    }
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<int>(
        $HistoryEntriesTable.$convertercheckedAt.toSql(checkedAt),
      );
    }
    if (!nullToAbsent || watchedUntil != null) {
      map['watched_until'] = Variable<int>(
        $HistoryEntriesTable.$converterwatchedUntil.toSql(watchedUntil),
      );
    }
    if (!nullToAbsent || checkingEndedAt != null) {
      map['checking_ended_at'] = Variable<int>(
        $HistoryEntriesTable.$convertercheckingEndedAt.toSql(checkingEndedAt),
      );
    }
    if (!nullToAbsent || courtSpeedKmh != null) {
      map['court_speed_kmh'] = Variable<double>(courtSpeedKmh);
    }
    if (!nullToAbsent || rawGustKmh != null) {
      map['raw_gust_kmh'] = Variable<double>(rawGustKmh);
    }
    if (!nullToAbsent || courtSpeedLimitKmh != null) {
      map['court_speed_limit_kmh'] = Variable<int>(courtSpeedLimitKmh);
    }
    if (!nullToAbsent || rawGustLimitKmh != null) {
      map['raw_gust_limit_kmh'] = Variable<double>(rawGustLimitKmh);
    }
    if (!nullToAbsent || volume != null) {
      map['volume'] = Variable<double>(volume);
    }
    if (!nullToAbsent || ringDisposition != null) {
      map['ring_disposition'] = Variable<String>(
        $HistoryEntriesTable.$converterringDispositionn.toSql(ringDisposition),
      );
    }
    if (!nullToAbsent || hostEventKey != null) {
      map['host_event_key'] = Variable<String>(hostEventKey);
    }
    return map;
  }

  HistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return HistoryEntriesCompanion(
      rowSeq: Value(rowSeq),
      alarmId: Value(alarmId),
      at: Value(at),
      pushSeq: Value(pushSeq),
      courtId: Value(courtId),
      outcome: Value(outcome),
      kind: Value(kind),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
      watchedUntil: watchedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(watchedUntil),
      checkingEndedAt: checkingEndedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkingEndedAt),
      courtSpeedKmh: courtSpeedKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(courtSpeedKmh),
      rawGustKmh: rawGustKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(rawGustKmh),
      courtSpeedLimitKmh: courtSpeedLimitKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(courtSpeedLimitKmh),
      rawGustLimitKmh: rawGustLimitKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(rawGustLimitKmh),
      volume: volume == null && nullToAbsent
          ? const Value.absent()
          : Value(volume),
      ringDisposition: ringDisposition == null && nullToAbsent
          ? const Value.absent()
          : Value(ringDisposition),
      hostEventKey: hostEventKey == null && nullToAbsent
          ? const Value.absent()
          : Value(hostEventKey),
    );
  }

  factory HistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryEntry(
      rowSeq: serializer.fromJson<int>(json['rowSeq']),
      alarmId: serializer.fromJson<int>(json['alarmId']),
      at: serializer.fromJson<DateTime>(json['at']),
      pushSeq: serializer.fromJson<int>(json['pushSeq']),
      courtId: serializer.fromJson<String>(json['courtId']),
      outcome: $HistoryEntriesTable.$converteroutcome.fromJson(
        serializer.fromJson<String>(json['outcome']),
      ),
      kind: $HistoryEntriesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      checkedAt: serializer.fromJson<DateTime?>(json['checkedAt']),
      watchedUntil: serializer.fromJson<DateTime?>(json['watchedUntil']),
      checkingEndedAt: serializer.fromJson<DateTime?>(json['checkingEndedAt']),
      courtSpeedKmh: serializer.fromJson<double?>(json['courtSpeedKmh']),
      rawGustKmh: serializer.fromJson<double?>(json['rawGustKmh']),
      courtSpeedLimitKmh: serializer.fromJson<int?>(json['courtSpeedLimitKmh']),
      rawGustLimitKmh: serializer.fromJson<double?>(json['rawGustLimitKmh']),
      volume: serializer.fromJson<double?>(json['volume']),
      ringDisposition: $HistoryEntriesTable.$converterringDispositionn.fromJson(
        serializer.fromJson<String?>(json['ringDisposition']),
      ),
      hostEventKey: serializer.fromJson<String?>(json['hostEventKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowSeq': serializer.toJson<int>(rowSeq),
      'alarmId': serializer.toJson<int>(alarmId),
      'at': serializer.toJson<DateTime>(at),
      'pushSeq': serializer.toJson<int>(pushSeq),
      'courtId': serializer.toJson<String>(courtId),
      'outcome': serializer.toJson<String>(
        $HistoryEntriesTable.$converteroutcome.toJson(outcome),
      ),
      'kind': serializer.toJson<String>(
        $HistoryEntriesTable.$converterkind.toJson(kind),
      ),
      'checkedAt': serializer.toJson<DateTime?>(checkedAt),
      'watchedUntil': serializer.toJson<DateTime?>(watchedUntil),
      'checkingEndedAt': serializer.toJson<DateTime?>(checkingEndedAt),
      'courtSpeedKmh': serializer.toJson<double?>(courtSpeedKmh),
      'rawGustKmh': serializer.toJson<double?>(rawGustKmh),
      'courtSpeedLimitKmh': serializer.toJson<int?>(courtSpeedLimitKmh),
      'rawGustLimitKmh': serializer.toJson<double?>(rawGustLimitKmh),
      'volume': serializer.toJson<double?>(volume),
      'ringDisposition': serializer.toJson<String?>(
        $HistoryEntriesTable.$converterringDispositionn.toJson(ringDisposition),
      ),
      'hostEventKey': serializer.toJson<String?>(hostEventKey),
    };
  }

  HistoryEntry copyWith({
    int? rowSeq,
    int? alarmId,
    DateTime? at,
    int? pushSeq,
    String? courtId,
    CheckOutcome? outcome,
    HistoryKind? kind,
    Value<DateTime?> checkedAt = const Value.absent(),
    Value<DateTime?> watchedUntil = const Value.absent(),
    Value<DateTime?> checkingEndedAt = const Value.absent(),
    Value<double?> courtSpeedKmh = const Value.absent(),
    Value<double?> rawGustKmh = const Value.absent(),
    Value<int?> courtSpeedLimitKmh = const Value.absent(),
    Value<double?> rawGustLimitKmh = const Value.absent(),
    Value<double?> volume = const Value.absent(),
    Value<RingDisposition?> ringDisposition = const Value.absent(),
    Value<String?> hostEventKey = const Value.absent(),
  }) => HistoryEntry(
    rowSeq: rowSeq ?? this.rowSeq,
    alarmId: alarmId ?? this.alarmId,
    at: at ?? this.at,
    pushSeq: pushSeq ?? this.pushSeq,
    courtId: courtId ?? this.courtId,
    outcome: outcome ?? this.outcome,
    kind: kind ?? this.kind,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
    watchedUntil: watchedUntil.present ? watchedUntil.value : this.watchedUntil,
    checkingEndedAt: checkingEndedAt.present
        ? checkingEndedAt.value
        : this.checkingEndedAt,
    courtSpeedKmh: courtSpeedKmh.present
        ? courtSpeedKmh.value
        : this.courtSpeedKmh,
    rawGustKmh: rawGustKmh.present ? rawGustKmh.value : this.rawGustKmh,
    courtSpeedLimitKmh: courtSpeedLimitKmh.present
        ? courtSpeedLimitKmh.value
        : this.courtSpeedLimitKmh,
    rawGustLimitKmh: rawGustLimitKmh.present
        ? rawGustLimitKmh.value
        : this.rawGustLimitKmh,
    volume: volume.present ? volume.value : this.volume,
    ringDisposition: ringDisposition.present
        ? ringDisposition.value
        : this.ringDisposition,
    hostEventKey: hostEventKey.present ? hostEventKey.value : this.hostEventKey,
  );
  HistoryEntry copyWithCompanion(HistoryEntriesCompanion data) {
    return HistoryEntry(
      rowSeq: data.rowSeq.present ? data.rowSeq.value : this.rowSeq,
      alarmId: data.alarmId.present ? data.alarmId.value : this.alarmId,
      at: data.at.present ? data.at.value : this.at,
      pushSeq: data.pushSeq.present ? data.pushSeq.value : this.pushSeq,
      courtId: data.courtId.present ? data.courtId.value : this.courtId,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      kind: data.kind.present ? data.kind.value : this.kind,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      watchedUntil: data.watchedUntil.present
          ? data.watchedUntil.value
          : this.watchedUntil,
      checkingEndedAt: data.checkingEndedAt.present
          ? data.checkingEndedAt.value
          : this.checkingEndedAt,
      courtSpeedKmh: data.courtSpeedKmh.present
          ? data.courtSpeedKmh.value
          : this.courtSpeedKmh,
      rawGustKmh: data.rawGustKmh.present
          ? data.rawGustKmh.value
          : this.rawGustKmh,
      courtSpeedLimitKmh: data.courtSpeedLimitKmh.present
          ? data.courtSpeedLimitKmh.value
          : this.courtSpeedLimitKmh,
      rawGustLimitKmh: data.rawGustLimitKmh.present
          ? data.rawGustLimitKmh.value
          : this.rawGustLimitKmh,
      volume: data.volume.present ? data.volume.value : this.volume,
      ringDisposition: data.ringDisposition.present
          ? data.ringDisposition.value
          : this.ringDisposition,
      hostEventKey: data.hostEventKey.present
          ? data.hostEventKey.value
          : this.hostEventKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntry(')
          ..write('rowSeq: $rowSeq, ')
          ..write('alarmId: $alarmId, ')
          ..write('at: $at, ')
          ..write('pushSeq: $pushSeq, ')
          ..write('courtId: $courtId, ')
          ..write('outcome: $outcome, ')
          ..write('kind: $kind, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('watchedUntil: $watchedUntil, ')
          ..write('checkingEndedAt: $checkingEndedAt, ')
          ..write('courtSpeedKmh: $courtSpeedKmh, ')
          ..write('rawGustKmh: $rawGustKmh, ')
          ..write('courtSpeedLimitKmh: $courtSpeedLimitKmh, ')
          ..write('rawGustLimitKmh: $rawGustLimitKmh, ')
          ..write('volume: $volume, ')
          ..write('ringDisposition: $ringDisposition, ')
          ..write('hostEventKey: $hostEventKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    rowSeq,
    alarmId,
    at,
    pushSeq,
    courtId,
    outcome,
    kind,
    checkedAt,
    watchedUntil,
    checkingEndedAt,
    courtSpeedKmh,
    rawGustKmh,
    courtSpeedLimitKmh,
    rawGustLimitKmh,
    volume,
    ringDisposition,
    hostEventKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryEntry &&
          other.rowSeq == this.rowSeq &&
          other.alarmId == this.alarmId &&
          other.at == this.at &&
          other.pushSeq == this.pushSeq &&
          other.courtId == this.courtId &&
          other.outcome == this.outcome &&
          other.kind == this.kind &&
          other.checkedAt == this.checkedAt &&
          other.watchedUntil == this.watchedUntil &&
          other.checkingEndedAt == this.checkingEndedAt &&
          other.courtSpeedKmh == this.courtSpeedKmh &&
          other.rawGustKmh == this.rawGustKmh &&
          other.courtSpeedLimitKmh == this.courtSpeedLimitKmh &&
          other.rawGustLimitKmh == this.rawGustLimitKmh &&
          other.volume == this.volume &&
          other.ringDisposition == this.ringDisposition &&
          other.hostEventKey == this.hostEventKey);
}

class HistoryEntriesCompanion extends UpdateCompanion<HistoryEntry> {
  final Value<int> rowSeq;
  final Value<int> alarmId;
  final Value<DateTime> at;
  final Value<int> pushSeq;
  final Value<String> courtId;
  final Value<CheckOutcome> outcome;
  final Value<HistoryKind> kind;
  final Value<DateTime?> checkedAt;
  final Value<DateTime?> watchedUntil;
  final Value<DateTime?> checkingEndedAt;
  final Value<double?> courtSpeedKmh;
  final Value<double?> rawGustKmh;
  final Value<int?> courtSpeedLimitKmh;
  final Value<double?> rawGustLimitKmh;
  final Value<double?> volume;
  final Value<RingDisposition?> ringDisposition;
  final Value<String?> hostEventKey;
  const HistoryEntriesCompanion({
    this.rowSeq = const Value.absent(),
    this.alarmId = const Value.absent(),
    this.at = const Value.absent(),
    this.pushSeq = const Value.absent(),
    this.courtId = const Value.absent(),
    this.outcome = const Value.absent(),
    this.kind = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.watchedUntil = const Value.absent(),
    this.checkingEndedAt = const Value.absent(),
    this.courtSpeedKmh = const Value.absent(),
    this.rawGustKmh = const Value.absent(),
    this.courtSpeedLimitKmh = const Value.absent(),
    this.rawGustLimitKmh = const Value.absent(),
    this.volume = const Value.absent(),
    this.ringDisposition = const Value.absent(),
    this.hostEventKey = const Value.absent(),
  });
  HistoryEntriesCompanion.insert({
    this.rowSeq = const Value.absent(),
    required int alarmId,
    required DateTime at,
    required int pushSeq,
    required String courtId,
    required CheckOutcome outcome,
    required HistoryKind kind,
    this.checkedAt = const Value.absent(),
    this.watchedUntil = const Value.absent(),
    this.checkingEndedAt = const Value.absent(),
    this.courtSpeedKmh = const Value.absent(),
    this.rawGustKmh = const Value.absent(),
    this.courtSpeedLimitKmh = const Value.absent(),
    this.rawGustLimitKmh = const Value.absent(),
    this.volume = const Value.absent(),
    this.ringDisposition = const Value.absent(),
    this.hostEventKey = const Value.absent(),
  }) : alarmId = Value(alarmId),
       at = Value(at),
       pushSeq = Value(pushSeq),
       courtId = Value(courtId),
       outcome = Value(outcome),
       kind = Value(kind);
  static Insertable<HistoryEntry> custom({
    Expression<int>? rowSeq,
    Expression<int>? alarmId,
    Expression<int>? at,
    Expression<int>? pushSeq,
    Expression<String>? courtId,
    Expression<String>? outcome,
    Expression<String>? kind,
    Expression<int>? checkedAt,
    Expression<int>? watchedUntil,
    Expression<int>? checkingEndedAt,
    Expression<double>? courtSpeedKmh,
    Expression<double>? rawGustKmh,
    Expression<int>? courtSpeedLimitKmh,
    Expression<double>? rawGustLimitKmh,
    Expression<double>? volume,
    Expression<String>? ringDisposition,
    Expression<String>? hostEventKey,
  }) {
    return RawValuesInsertable({
      if (rowSeq != null) 'row_seq': rowSeq,
      if (alarmId != null) 'alarm_id': alarmId,
      if (at != null) 'at': at,
      if (pushSeq != null) 'push_seq': pushSeq,
      if (courtId != null) 'court_id': courtId,
      if (outcome != null) 'outcome': outcome,
      if (kind != null) 'kind': kind,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (watchedUntil != null) 'watched_until': watchedUntil,
      if (checkingEndedAt != null) 'checking_ended_at': checkingEndedAt,
      if (courtSpeedKmh != null) 'court_speed_kmh': courtSpeedKmh,
      if (rawGustKmh != null) 'raw_gust_kmh': rawGustKmh,
      if (courtSpeedLimitKmh != null)
        'court_speed_limit_kmh': courtSpeedLimitKmh,
      if (rawGustLimitKmh != null) 'raw_gust_limit_kmh': rawGustLimitKmh,
      if (volume != null) 'volume': volume,
      if (ringDisposition != null) 'ring_disposition': ringDisposition,
      if (hostEventKey != null) 'host_event_key': hostEventKey,
    });
  }

  HistoryEntriesCompanion copyWith({
    Value<int>? rowSeq,
    Value<int>? alarmId,
    Value<DateTime>? at,
    Value<int>? pushSeq,
    Value<String>? courtId,
    Value<CheckOutcome>? outcome,
    Value<HistoryKind>? kind,
    Value<DateTime?>? checkedAt,
    Value<DateTime?>? watchedUntil,
    Value<DateTime?>? checkingEndedAt,
    Value<double?>? courtSpeedKmh,
    Value<double?>? rawGustKmh,
    Value<int?>? courtSpeedLimitKmh,
    Value<double?>? rawGustLimitKmh,
    Value<double?>? volume,
    Value<RingDisposition?>? ringDisposition,
    Value<String?>? hostEventKey,
  }) {
    return HistoryEntriesCompanion(
      rowSeq: rowSeq ?? this.rowSeq,
      alarmId: alarmId ?? this.alarmId,
      at: at ?? this.at,
      pushSeq: pushSeq ?? this.pushSeq,
      courtId: courtId ?? this.courtId,
      outcome: outcome ?? this.outcome,
      kind: kind ?? this.kind,
      checkedAt: checkedAt ?? this.checkedAt,
      watchedUntil: watchedUntil ?? this.watchedUntil,
      checkingEndedAt: checkingEndedAt ?? this.checkingEndedAt,
      courtSpeedKmh: courtSpeedKmh ?? this.courtSpeedKmh,
      rawGustKmh: rawGustKmh ?? this.rawGustKmh,
      courtSpeedLimitKmh: courtSpeedLimitKmh ?? this.courtSpeedLimitKmh,
      rawGustLimitKmh: rawGustLimitKmh ?? this.rawGustLimitKmh,
      volume: volume ?? this.volume,
      ringDisposition: ringDisposition ?? this.ringDisposition,
      hostEventKey: hostEventKey ?? this.hostEventKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowSeq.present) {
      map['row_seq'] = Variable<int>(rowSeq.value);
    }
    if (alarmId.present) {
      map['alarm_id'] = Variable<int>(alarmId.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(
        $HistoryEntriesTable.$converterat.toSql(at.value),
      );
    }
    if (pushSeq.present) {
      map['push_seq'] = Variable<int>(pushSeq.value);
    }
    if (courtId.present) {
      map['court_id'] = Variable<String>(courtId.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(
        $HistoryEntriesTable.$converteroutcome.toSql(outcome.value),
      );
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $HistoryEntriesTable.$converterkind.toSql(kind.value),
      );
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<int>(
        $HistoryEntriesTable.$convertercheckedAt.toSql(checkedAt.value),
      );
    }
    if (watchedUntil.present) {
      map['watched_until'] = Variable<int>(
        $HistoryEntriesTable.$converterwatchedUntil.toSql(watchedUntil.value),
      );
    }
    if (checkingEndedAt.present) {
      map['checking_ended_at'] = Variable<int>(
        $HistoryEntriesTable.$convertercheckingEndedAt.toSql(
          checkingEndedAt.value,
        ),
      );
    }
    if (courtSpeedKmh.present) {
      map['court_speed_kmh'] = Variable<double>(courtSpeedKmh.value);
    }
    if (rawGustKmh.present) {
      map['raw_gust_kmh'] = Variable<double>(rawGustKmh.value);
    }
    if (courtSpeedLimitKmh.present) {
      map['court_speed_limit_kmh'] = Variable<int>(courtSpeedLimitKmh.value);
    }
    if (rawGustLimitKmh.present) {
      map['raw_gust_limit_kmh'] = Variable<double>(rawGustLimitKmh.value);
    }
    if (volume.present) {
      map['volume'] = Variable<double>(volume.value);
    }
    if (ringDisposition.present) {
      map['ring_disposition'] = Variable<String>(
        $HistoryEntriesTable.$converterringDispositionn.toSql(
          ringDisposition.value,
        ),
      );
    }
    if (hostEventKey.present) {
      map['host_event_key'] = Variable<String>(hostEventKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntriesCompanion(')
          ..write('rowSeq: $rowSeq, ')
          ..write('alarmId: $alarmId, ')
          ..write('at: $at, ')
          ..write('pushSeq: $pushSeq, ')
          ..write('courtId: $courtId, ')
          ..write('outcome: $outcome, ')
          ..write('kind: $kind, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('watchedUntil: $watchedUntil, ')
          ..write('checkingEndedAt: $checkingEndedAt, ')
          ..write('courtSpeedKmh: $courtSpeedKmh, ')
          ..write('rawGustKmh: $rawGustKmh, ')
          ..write('courtSpeedLimitKmh: $courtSpeedLimitKmh, ')
          ..write('rawGustLimitKmh: $rawGustLimitKmh, ')
          ..write('volume: $volume, ')
          ..write('ringDisposition: $ringDisposition, ')
          ..write('hostEventKey: $hostEventKey')
          ..write(')'))
        .toString();
  }
}

class $CheckStatesTable extends CheckStates
    with TableInfo<$CheckStatesTable, CheckStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CheckStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _alarmIdMeta = const VerificationMeta(
    'alarmId',
  );
  @override
  late final GeneratedColumn<int> alarmId = GeneratedColumn<int>(
    'alarm_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> alarmAt =
      GeneratedColumn<int>(
        'alarm_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($CheckStatesTable.$converteralarmAt);
  static const VerificationMeta _ringScheduledMeta = const VerificationMeta(
    'ringScheduled',
  );
  @override
  late final GeneratedColumn<bool> ringScheduled = GeneratedColumn<bool>(
    'ring_scheduled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ring_scheduled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ringCourtSpeedKmhMeta = const VerificationMeta(
    'ringCourtSpeedKmh',
  );
  @override
  late final GeneratedColumn<double> ringCourtSpeedKmh =
      GeneratedColumn<double>(
        'ring_court_speed_kmh',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _ringRawGustKmhMeta = const VerificationMeta(
    'ringRawGustKmh',
  );
  @override
  late final GeneratedColumn<double> ringRawGustKmh = GeneratedColumn<double>(
    'ring_raw_gust_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ringVolumeMeta = const VerificationMeta(
    'ringVolume',
  );
  @override
  late final GeneratedColumn<double> ringVolume = GeneratedColumn<double>(
    'ring_volume',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardShownMeta = const VerificationMeta(
    'cardShown',
  );
  @override
  late final GeneratedColumn<bool> cardShown = GeneratedColumn<bool>(
    'card_shown',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("card_shown" IN (0, 1))',
    ),
  );
  static const VerificationMeta _skipCourtSpeedKmhMeta = const VerificationMeta(
    'skipCourtSpeedKmh',
  );
  @override
  late final GeneratedColumn<double> skipCourtSpeedKmh =
      GeneratedColumn<double>(
        'skip_court_speed_kmh',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _skipRawGustKmhMeta = const VerificationMeta(
    'skipRawGustKmh',
  );
  @override
  late final GeneratedColumn<double> skipRawGustKmh = GeneratedColumn<double>(
    'skip_raw_gust_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skipGustyMeta = const VerificationMeta(
    'skipGusty',
  );
  @override
  late final GeneratedColumn<bool> skipGusty = GeneratedColumn<bool>(
    'skip_gusty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("skip_gusty" IN (0, 1))',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastCheckAt =
      GeneratedColumn<int>(
        'last_check_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($CheckStatesTable.$converterlastCheckAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastAttemptAt =
      GeneratedColumn<int>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($CheckStatesTable.$converterlastAttemptAt);
  static const VerificationMeta _pushSeqMeta = const VerificationMeta(
    'pushSeq',
  );
  @override
  late final GeneratedColumn<int> pushSeq = GeneratedColumn<int>(
    'push_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    alarmId,
    alarmAt,
    ringScheduled,
    ringCourtSpeedKmh,
    ringRawGustKmh,
    ringVolume,
    cardShown,
    skipCourtSpeedKmh,
    skipRawGustKmh,
    skipGusty,
    lastCheckAt,
    lastAttemptAt,
    pushSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'check_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<CheckStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('alarm_id')) {
      context.handle(
        _alarmIdMeta,
        alarmId.isAcceptableOrUnknown(data['alarm_id']!, _alarmIdMeta),
      );
    }
    if (data.containsKey('ring_scheduled')) {
      context.handle(
        _ringScheduledMeta,
        ringScheduled.isAcceptableOrUnknown(
          data['ring_scheduled']!,
          _ringScheduledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ringScheduledMeta);
    }
    if (data.containsKey('ring_court_speed_kmh')) {
      context.handle(
        _ringCourtSpeedKmhMeta,
        ringCourtSpeedKmh.isAcceptableOrUnknown(
          data['ring_court_speed_kmh']!,
          _ringCourtSpeedKmhMeta,
        ),
      );
    }
    if (data.containsKey('ring_raw_gust_kmh')) {
      context.handle(
        _ringRawGustKmhMeta,
        ringRawGustKmh.isAcceptableOrUnknown(
          data['ring_raw_gust_kmh']!,
          _ringRawGustKmhMeta,
        ),
      );
    }
    if (data.containsKey('ring_volume')) {
      context.handle(
        _ringVolumeMeta,
        ringVolume.isAcceptableOrUnknown(data['ring_volume']!, _ringVolumeMeta),
      );
    }
    if (data.containsKey('card_shown')) {
      context.handle(
        _cardShownMeta,
        cardShown.isAcceptableOrUnknown(data['card_shown']!, _cardShownMeta),
      );
    } else if (isInserting) {
      context.missing(_cardShownMeta);
    }
    if (data.containsKey('skip_court_speed_kmh')) {
      context.handle(
        _skipCourtSpeedKmhMeta,
        skipCourtSpeedKmh.isAcceptableOrUnknown(
          data['skip_court_speed_kmh']!,
          _skipCourtSpeedKmhMeta,
        ),
      );
    }
    if (data.containsKey('skip_raw_gust_kmh')) {
      context.handle(
        _skipRawGustKmhMeta,
        skipRawGustKmh.isAcceptableOrUnknown(
          data['skip_raw_gust_kmh']!,
          _skipRawGustKmhMeta,
        ),
      );
    }
    if (data.containsKey('skip_gusty')) {
      context.handle(
        _skipGustyMeta,
        skipGusty.isAcceptableOrUnknown(data['skip_gusty']!, _skipGustyMeta),
      );
    } else if (isInserting) {
      context.missing(_skipGustyMeta);
    }
    if (data.containsKey('push_seq')) {
      context.handle(
        _pushSeqMeta,
        pushSeq.isAcceptableOrUnknown(data['push_seq']!, _pushSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_pushSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {alarmId};
  @override
  CheckStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CheckStateRow(
      alarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alarm_id'],
      )!,
      alarmAt: $CheckStatesTable.$converteralarmAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}alarm_at'],
        )!,
      ),
      ringScheduled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ring_scheduled'],
      )!,
      ringCourtSpeedKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ring_court_speed_kmh'],
      ),
      ringRawGustKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ring_raw_gust_kmh'],
      ),
      ringVolume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ring_volume'],
      ),
      cardShown: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}card_shown'],
      )!,
      skipCourtSpeedKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}skip_court_speed_kmh'],
      ),
      skipRawGustKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}skip_raw_gust_kmh'],
      ),
      skipGusty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}skip_gusty'],
      )!,
      lastCheckAt: $CheckStatesTable.$converterlastCheckAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_check_at'],
        ),
      ),
      lastAttemptAt: $CheckStatesTable.$converterlastAttemptAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_attempt_at'],
        ),
      ),
      pushSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}push_seq'],
      )!,
    );
  }

  @override
  $CheckStatesTable createAlias(String alias) {
    return $CheckStatesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converteralarmAt = dateTimeMicros;
  static TypeConverter<DateTime?, int?> $converterlastCheckAt =
      nullableDateTimeMicros;
  static TypeConverter<DateTime?, int?> $converterlastAttemptAt =
      nullableDateTimeMicros;
}

class CheckStateRow extends DataClass implements Insertable<CheckStateRow> {
  final int alarmId;
  final DateTime alarmAt;
  final bool ringScheduled;
  final double? ringCourtSpeedKmh;
  final double? ringRawGustKmh;
  final double? ringVolume;
  final bool cardShown;
  final double? skipCourtSpeedKmh;
  final double? skipRawGustKmh;
  final bool skipGusty;
  final DateTime? lastCheckAt;
  final DateTime? lastAttemptAt;
  final int pushSeq;
  const CheckStateRow({
    required this.alarmId,
    required this.alarmAt,
    required this.ringScheduled,
    this.ringCourtSpeedKmh,
    this.ringRawGustKmh,
    this.ringVolume,
    required this.cardShown,
    this.skipCourtSpeedKmh,
    this.skipRawGustKmh,
    required this.skipGusty,
    this.lastCheckAt,
    this.lastAttemptAt,
    required this.pushSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['alarm_id'] = Variable<int>(alarmId);
    {
      map['alarm_at'] = Variable<int>(
        $CheckStatesTable.$converteralarmAt.toSql(alarmAt),
      );
    }
    map['ring_scheduled'] = Variable<bool>(ringScheduled);
    if (!nullToAbsent || ringCourtSpeedKmh != null) {
      map['ring_court_speed_kmh'] = Variable<double>(ringCourtSpeedKmh);
    }
    if (!nullToAbsent || ringRawGustKmh != null) {
      map['ring_raw_gust_kmh'] = Variable<double>(ringRawGustKmh);
    }
    if (!nullToAbsent || ringVolume != null) {
      map['ring_volume'] = Variable<double>(ringVolume);
    }
    map['card_shown'] = Variable<bool>(cardShown);
    if (!nullToAbsent || skipCourtSpeedKmh != null) {
      map['skip_court_speed_kmh'] = Variable<double>(skipCourtSpeedKmh);
    }
    if (!nullToAbsent || skipRawGustKmh != null) {
      map['skip_raw_gust_kmh'] = Variable<double>(skipRawGustKmh);
    }
    map['skip_gusty'] = Variable<bool>(skipGusty);
    if (!nullToAbsent || lastCheckAt != null) {
      map['last_check_at'] = Variable<int>(
        $CheckStatesTable.$converterlastCheckAt.toSql(lastCheckAt),
      );
    }
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<int>(
        $CheckStatesTable.$converterlastAttemptAt.toSql(lastAttemptAt),
      );
    }
    map['push_seq'] = Variable<int>(pushSeq);
    return map;
  }

  CheckStatesCompanion toCompanion(bool nullToAbsent) {
    return CheckStatesCompanion(
      alarmId: Value(alarmId),
      alarmAt: Value(alarmAt),
      ringScheduled: Value(ringScheduled),
      ringCourtSpeedKmh: ringCourtSpeedKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(ringCourtSpeedKmh),
      ringRawGustKmh: ringRawGustKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(ringRawGustKmh),
      ringVolume: ringVolume == null && nullToAbsent
          ? const Value.absent()
          : Value(ringVolume),
      cardShown: Value(cardShown),
      skipCourtSpeedKmh: skipCourtSpeedKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(skipCourtSpeedKmh),
      skipRawGustKmh: skipRawGustKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(skipRawGustKmh),
      skipGusty: Value(skipGusty),
      lastCheckAt: lastCheckAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      pushSeq: Value(pushSeq),
    );
  }

  factory CheckStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CheckStateRow(
      alarmId: serializer.fromJson<int>(json['alarmId']),
      alarmAt: serializer.fromJson<DateTime>(json['alarmAt']),
      ringScheduled: serializer.fromJson<bool>(json['ringScheduled']),
      ringCourtSpeedKmh: serializer.fromJson<double?>(
        json['ringCourtSpeedKmh'],
      ),
      ringRawGustKmh: serializer.fromJson<double?>(json['ringRawGustKmh']),
      ringVolume: serializer.fromJson<double?>(json['ringVolume']),
      cardShown: serializer.fromJson<bool>(json['cardShown']),
      skipCourtSpeedKmh: serializer.fromJson<double?>(
        json['skipCourtSpeedKmh'],
      ),
      skipRawGustKmh: serializer.fromJson<double?>(json['skipRawGustKmh']),
      skipGusty: serializer.fromJson<bool>(json['skipGusty']),
      lastCheckAt: serializer.fromJson<DateTime?>(json['lastCheckAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      pushSeq: serializer.fromJson<int>(json['pushSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'alarmId': serializer.toJson<int>(alarmId),
      'alarmAt': serializer.toJson<DateTime>(alarmAt),
      'ringScheduled': serializer.toJson<bool>(ringScheduled),
      'ringCourtSpeedKmh': serializer.toJson<double?>(ringCourtSpeedKmh),
      'ringRawGustKmh': serializer.toJson<double?>(ringRawGustKmh),
      'ringVolume': serializer.toJson<double?>(ringVolume),
      'cardShown': serializer.toJson<bool>(cardShown),
      'skipCourtSpeedKmh': serializer.toJson<double?>(skipCourtSpeedKmh),
      'skipRawGustKmh': serializer.toJson<double?>(skipRawGustKmh),
      'skipGusty': serializer.toJson<bool>(skipGusty),
      'lastCheckAt': serializer.toJson<DateTime?>(lastCheckAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'pushSeq': serializer.toJson<int>(pushSeq),
    };
  }

  CheckStateRow copyWith({
    int? alarmId,
    DateTime? alarmAt,
    bool? ringScheduled,
    Value<double?> ringCourtSpeedKmh = const Value.absent(),
    Value<double?> ringRawGustKmh = const Value.absent(),
    Value<double?> ringVolume = const Value.absent(),
    bool? cardShown,
    Value<double?> skipCourtSpeedKmh = const Value.absent(),
    Value<double?> skipRawGustKmh = const Value.absent(),
    bool? skipGusty,
    Value<DateTime?> lastCheckAt = const Value.absent(),
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    int? pushSeq,
  }) => CheckStateRow(
    alarmId: alarmId ?? this.alarmId,
    alarmAt: alarmAt ?? this.alarmAt,
    ringScheduled: ringScheduled ?? this.ringScheduled,
    ringCourtSpeedKmh: ringCourtSpeedKmh.present
        ? ringCourtSpeedKmh.value
        : this.ringCourtSpeedKmh,
    ringRawGustKmh: ringRawGustKmh.present
        ? ringRawGustKmh.value
        : this.ringRawGustKmh,
    ringVolume: ringVolume.present ? ringVolume.value : this.ringVolume,
    cardShown: cardShown ?? this.cardShown,
    skipCourtSpeedKmh: skipCourtSpeedKmh.present
        ? skipCourtSpeedKmh.value
        : this.skipCourtSpeedKmh,
    skipRawGustKmh: skipRawGustKmh.present
        ? skipRawGustKmh.value
        : this.skipRawGustKmh,
    skipGusty: skipGusty ?? this.skipGusty,
    lastCheckAt: lastCheckAt.present ? lastCheckAt.value : this.lastCheckAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    pushSeq: pushSeq ?? this.pushSeq,
  );
  CheckStateRow copyWithCompanion(CheckStatesCompanion data) {
    return CheckStateRow(
      alarmId: data.alarmId.present ? data.alarmId.value : this.alarmId,
      alarmAt: data.alarmAt.present ? data.alarmAt.value : this.alarmAt,
      ringScheduled: data.ringScheduled.present
          ? data.ringScheduled.value
          : this.ringScheduled,
      ringCourtSpeedKmh: data.ringCourtSpeedKmh.present
          ? data.ringCourtSpeedKmh.value
          : this.ringCourtSpeedKmh,
      ringRawGustKmh: data.ringRawGustKmh.present
          ? data.ringRawGustKmh.value
          : this.ringRawGustKmh,
      ringVolume: data.ringVolume.present
          ? data.ringVolume.value
          : this.ringVolume,
      cardShown: data.cardShown.present ? data.cardShown.value : this.cardShown,
      skipCourtSpeedKmh: data.skipCourtSpeedKmh.present
          ? data.skipCourtSpeedKmh.value
          : this.skipCourtSpeedKmh,
      skipRawGustKmh: data.skipRawGustKmh.present
          ? data.skipRawGustKmh.value
          : this.skipRawGustKmh,
      skipGusty: data.skipGusty.present ? data.skipGusty.value : this.skipGusty,
      lastCheckAt: data.lastCheckAt.present
          ? data.lastCheckAt.value
          : this.lastCheckAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      pushSeq: data.pushSeq.present ? data.pushSeq.value : this.pushSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CheckStateRow(')
          ..write('alarmId: $alarmId, ')
          ..write('alarmAt: $alarmAt, ')
          ..write('ringScheduled: $ringScheduled, ')
          ..write('ringCourtSpeedKmh: $ringCourtSpeedKmh, ')
          ..write('ringRawGustKmh: $ringRawGustKmh, ')
          ..write('ringVolume: $ringVolume, ')
          ..write('cardShown: $cardShown, ')
          ..write('skipCourtSpeedKmh: $skipCourtSpeedKmh, ')
          ..write('skipRawGustKmh: $skipRawGustKmh, ')
          ..write('skipGusty: $skipGusty, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('pushSeq: $pushSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    alarmId,
    alarmAt,
    ringScheduled,
    ringCourtSpeedKmh,
    ringRawGustKmh,
    ringVolume,
    cardShown,
    skipCourtSpeedKmh,
    skipRawGustKmh,
    skipGusty,
    lastCheckAt,
    lastAttemptAt,
    pushSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CheckStateRow &&
          other.alarmId == this.alarmId &&
          other.alarmAt == this.alarmAt &&
          other.ringScheduled == this.ringScheduled &&
          other.ringCourtSpeedKmh == this.ringCourtSpeedKmh &&
          other.ringRawGustKmh == this.ringRawGustKmh &&
          other.ringVolume == this.ringVolume &&
          other.cardShown == this.cardShown &&
          other.skipCourtSpeedKmh == this.skipCourtSpeedKmh &&
          other.skipRawGustKmh == this.skipRawGustKmh &&
          other.skipGusty == this.skipGusty &&
          other.lastCheckAt == this.lastCheckAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.pushSeq == this.pushSeq);
}

class CheckStatesCompanion extends UpdateCompanion<CheckStateRow> {
  final Value<int> alarmId;
  final Value<DateTime> alarmAt;
  final Value<bool> ringScheduled;
  final Value<double?> ringCourtSpeedKmh;
  final Value<double?> ringRawGustKmh;
  final Value<double?> ringVolume;
  final Value<bool> cardShown;
  final Value<double?> skipCourtSpeedKmh;
  final Value<double?> skipRawGustKmh;
  final Value<bool> skipGusty;
  final Value<DateTime?> lastCheckAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<int> pushSeq;
  const CheckStatesCompanion({
    this.alarmId = const Value.absent(),
    this.alarmAt = const Value.absent(),
    this.ringScheduled = const Value.absent(),
    this.ringCourtSpeedKmh = const Value.absent(),
    this.ringRawGustKmh = const Value.absent(),
    this.ringVolume = const Value.absent(),
    this.cardShown = const Value.absent(),
    this.skipCourtSpeedKmh = const Value.absent(),
    this.skipRawGustKmh = const Value.absent(),
    this.skipGusty = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.pushSeq = const Value.absent(),
  });
  CheckStatesCompanion.insert({
    this.alarmId = const Value.absent(),
    required DateTime alarmAt,
    required bool ringScheduled,
    this.ringCourtSpeedKmh = const Value.absent(),
    this.ringRawGustKmh = const Value.absent(),
    this.ringVolume = const Value.absent(),
    required bool cardShown,
    this.skipCourtSpeedKmh = const Value.absent(),
    this.skipRawGustKmh = const Value.absent(),
    required bool skipGusty,
    this.lastCheckAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    required int pushSeq,
  }) : alarmAt = Value(alarmAt),
       ringScheduled = Value(ringScheduled),
       cardShown = Value(cardShown),
       skipGusty = Value(skipGusty),
       pushSeq = Value(pushSeq);
  static Insertable<CheckStateRow> custom({
    Expression<int>? alarmId,
    Expression<int>? alarmAt,
    Expression<bool>? ringScheduled,
    Expression<double>? ringCourtSpeedKmh,
    Expression<double>? ringRawGustKmh,
    Expression<double>? ringVolume,
    Expression<bool>? cardShown,
    Expression<double>? skipCourtSpeedKmh,
    Expression<double>? skipRawGustKmh,
    Expression<bool>? skipGusty,
    Expression<int>? lastCheckAt,
    Expression<int>? lastAttemptAt,
    Expression<int>? pushSeq,
  }) {
    return RawValuesInsertable({
      if (alarmId != null) 'alarm_id': alarmId,
      if (alarmAt != null) 'alarm_at': alarmAt,
      if (ringScheduled != null) 'ring_scheduled': ringScheduled,
      if (ringCourtSpeedKmh != null) 'ring_court_speed_kmh': ringCourtSpeedKmh,
      if (ringRawGustKmh != null) 'ring_raw_gust_kmh': ringRawGustKmh,
      if (ringVolume != null) 'ring_volume': ringVolume,
      if (cardShown != null) 'card_shown': cardShown,
      if (skipCourtSpeedKmh != null) 'skip_court_speed_kmh': skipCourtSpeedKmh,
      if (skipRawGustKmh != null) 'skip_raw_gust_kmh': skipRawGustKmh,
      if (skipGusty != null) 'skip_gusty': skipGusty,
      if (lastCheckAt != null) 'last_check_at': lastCheckAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (pushSeq != null) 'push_seq': pushSeq,
    });
  }

  CheckStatesCompanion copyWith({
    Value<int>? alarmId,
    Value<DateTime>? alarmAt,
    Value<bool>? ringScheduled,
    Value<double?>? ringCourtSpeedKmh,
    Value<double?>? ringRawGustKmh,
    Value<double?>? ringVolume,
    Value<bool>? cardShown,
    Value<double?>? skipCourtSpeedKmh,
    Value<double?>? skipRawGustKmh,
    Value<bool>? skipGusty,
    Value<DateTime?>? lastCheckAt,
    Value<DateTime?>? lastAttemptAt,
    Value<int>? pushSeq,
  }) {
    return CheckStatesCompanion(
      alarmId: alarmId ?? this.alarmId,
      alarmAt: alarmAt ?? this.alarmAt,
      ringScheduled: ringScheduled ?? this.ringScheduled,
      ringCourtSpeedKmh: ringCourtSpeedKmh ?? this.ringCourtSpeedKmh,
      ringRawGustKmh: ringRawGustKmh ?? this.ringRawGustKmh,
      ringVolume: ringVolume ?? this.ringVolume,
      cardShown: cardShown ?? this.cardShown,
      skipCourtSpeedKmh: skipCourtSpeedKmh ?? this.skipCourtSpeedKmh,
      skipRawGustKmh: skipRawGustKmh ?? this.skipRawGustKmh,
      skipGusty: skipGusty ?? this.skipGusty,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      pushSeq: pushSeq ?? this.pushSeq,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (alarmId.present) {
      map['alarm_id'] = Variable<int>(alarmId.value);
    }
    if (alarmAt.present) {
      map['alarm_at'] = Variable<int>(
        $CheckStatesTable.$converteralarmAt.toSql(alarmAt.value),
      );
    }
    if (ringScheduled.present) {
      map['ring_scheduled'] = Variable<bool>(ringScheduled.value);
    }
    if (ringCourtSpeedKmh.present) {
      map['ring_court_speed_kmh'] = Variable<double>(ringCourtSpeedKmh.value);
    }
    if (ringRawGustKmh.present) {
      map['ring_raw_gust_kmh'] = Variable<double>(ringRawGustKmh.value);
    }
    if (ringVolume.present) {
      map['ring_volume'] = Variable<double>(ringVolume.value);
    }
    if (cardShown.present) {
      map['card_shown'] = Variable<bool>(cardShown.value);
    }
    if (skipCourtSpeedKmh.present) {
      map['skip_court_speed_kmh'] = Variable<double>(skipCourtSpeedKmh.value);
    }
    if (skipRawGustKmh.present) {
      map['skip_raw_gust_kmh'] = Variable<double>(skipRawGustKmh.value);
    }
    if (skipGusty.present) {
      map['skip_gusty'] = Variable<bool>(skipGusty.value);
    }
    if (lastCheckAt.present) {
      map['last_check_at'] = Variable<int>(
        $CheckStatesTable.$converterlastCheckAt.toSql(lastCheckAt.value),
      );
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<int>(
        $CheckStatesTable.$converterlastAttemptAt.toSql(lastAttemptAt.value),
      );
    }
    if (pushSeq.present) {
      map['push_seq'] = Variable<int>(pushSeq.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CheckStatesCompanion(')
          ..write('alarmId: $alarmId, ')
          ..write('alarmAt: $alarmAt, ')
          ..write('ringScheduled: $ringScheduled, ')
          ..write('ringCourtSpeedKmh: $ringCourtSpeedKmh, ')
          ..write('ringRawGustKmh: $ringRawGustKmh, ')
          ..write('ringVolume: $ringVolume, ')
          ..write('cardShown: $cardShown, ')
          ..write('skipCourtSpeedKmh: $skipCourtSpeedKmh, ')
          ..write('skipRawGustKmh: $skipRawGustKmh, ')
          ..write('skipGusty: $skipGusty, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('pushSeq: $pushSeq')
          ..write(')'))
        .toString();
  }
}

class $PendingRingsTable extends PendingRings
    with TableInfo<$PendingRingsTable, PendingRingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingRingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _alarmIdMeta = const VerificationMeta(
    'alarmId',
  );
  @override
  late final GeneratedColumn<int> alarmId = GeneratedColumn<int>(
    'alarm_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pluginIdMeta = const VerificationMeta(
    'pluginId',
  );
  @override
  late final GeneratedColumn<int> pluginId = GeneratedColumn<int>(
    'plugin_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RingLockerRole, String> role =
      GeneratedColumn<String>(
        'role',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RingLockerRole>($PendingRingsTable.$converterrole);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> occurrenceAt =
      GeneratedColumn<int>(
        'occurrence_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PendingRingsTable.$converteroccurrenceAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> scheduledFor =
      GeneratedColumn<int>(
        'scheduled_for',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PendingRingsTable.$converterscheduledFor);
  static const VerificationMeta _courtIdMeta = const VerificationMeta(
    'courtId',
  );
  @override
  late final GeneratedColumn<String> courtId = GeneratedColumn<String>(
    'court_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<double> volume = GeneratedColumn<double>(
    'volume',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _courtSpeedKmhMeta = const VerificationMeta(
    'courtSpeedKmh',
  );
  @override
  late final GeneratedColumn<double> courtSpeedKmh = GeneratedColumn<double>(
    'court_speed_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawGustKmhMeta = const VerificationMeta(
    'rawGustKmh',
  );
  @override
  late final GeneratedColumn<double> rawGustKmh = GeneratedColumn<double>(
    'raw_gust_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _courtSpeedLimitKmhMeta =
      const VerificationMeta('courtSpeedLimitKmh');
  @override
  late final GeneratedColumn<int> courtSpeedLimitKmh = GeneratedColumn<int>(
    'court_speed_limit_kmh',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawGustLimitKmhMeta = const VerificationMeta(
    'rawGustLimitKmh',
  );
  @override
  late final GeneratedColumn<double> rawGustLimitKmh = GeneratedColumn<double>(
    'raw_gust_limit_kmh',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastCheckAt =
      GeneratedColumn<int>(
        'last_check_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($PendingRingsTable.$converterlastCheckAt);
  static const VerificationMeta _rollOnDoneMeta = const VerificationMeta(
    'rollOnDone',
  );
  @override
  late final GeneratedColumn<bool> rollOnDone = GeneratedColumn<bool>(
    'roll_on_done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("roll_on_done" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    alarmId,
    pluginId,
    role,
    occurrenceAt,
    scheduledFor,
    courtId,
    volume,
    courtSpeedKmh,
    rawGustKmh,
    courtSpeedLimitKmh,
    rawGustLimitKmh,
    lastCheckAt,
    rollOnDone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_rings';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingRingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('alarm_id')) {
      context.handle(
        _alarmIdMeta,
        alarmId.isAcceptableOrUnknown(data['alarm_id']!, _alarmIdMeta),
      );
    }
    if (data.containsKey('plugin_id')) {
      context.handle(
        _pluginIdMeta,
        pluginId.isAcceptableOrUnknown(data['plugin_id']!, _pluginIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pluginIdMeta);
    }
    if (data.containsKey('court_id')) {
      context.handle(
        _courtIdMeta,
        courtId.isAcceptableOrUnknown(data['court_id']!, _courtIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courtIdMeta);
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    if (data.containsKey('court_speed_kmh')) {
      context.handle(
        _courtSpeedKmhMeta,
        courtSpeedKmh.isAcceptableOrUnknown(
          data['court_speed_kmh']!,
          _courtSpeedKmhMeta,
        ),
      );
    }
    if (data.containsKey('raw_gust_kmh')) {
      context.handle(
        _rawGustKmhMeta,
        rawGustKmh.isAcceptableOrUnknown(
          data['raw_gust_kmh']!,
          _rawGustKmhMeta,
        ),
      );
    }
    if (data.containsKey('court_speed_limit_kmh')) {
      context.handle(
        _courtSpeedLimitKmhMeta,
        courtSpeedLimitKmh.isAcceptableOrUnknown(
          data['court_speed_limit_kmh']!,
          _courtSpeedLimitKmhMeta,
        ),
      );
    }
    if (data.containsKey('raw_gust_limit_kmh')) {
      context.handle(
        _rawGustLimitKmhMeta,
        rawGustLimitKmh.isAcceptableOrUnknown(
          data['raw_gust_limit_kmh']!,
          _rawGustLimitKmhMeta,
        ),
      );
    }
    if (data.containsKey('roll_on_done')) {
      context.handle(
        _rollOnDoneMeta,
        rollOnDone.isAcceptableOrUnknown(
          data['roll_on_done']!,
          _rollOnDoneMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rollOnDoneMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {alarmId};
  @override
  PendingRingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingRingRow(
      alarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alarm_id'],
      )!,
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}plugin_id'],
      )!,
      role: $PendingRingsTable.$converterrole.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}role'],
        )!,
      ),
      occurrenceAt: $PendingRingsTable.$converteroccurrenceAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}occurrence_at'],
        )!,
      ),
      scheduledFor: $PendingRingsTable.$converterscheduledFor.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}scheduled_for'],
        )!,
      ),
      courtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}court_id'],
      )!,
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume'],
      ),
      courtSpeedKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}court_speed_kmh'],
      ),
      rawGustKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}raw_gust_kmh'],
      ),
      courtSpeedLimitKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}court_speed_limit_kmh'],
      ),
      rawGustLimitKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}raw_gust_limit_kmh'],
      ),
      lastCheckAt: $PendingRingsTable.$converterlastCheckAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_check_at'],
        ),
      ),
      rollOnDone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}roll_on_done'],
      )!,
    );
  }

  @override
  $PendingRingsTable createAlias(String alias) {
    return $PendingRingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RingLockerRole, String, String> $converterrole =
      const EnumNameConverter<RingLockerRole>(RingLockerRole.values);
  static TypeConverter<DateTime, int> $converteroccurrenceAt = dateTimeMicros;
  static TypeConverter<DateTime, int> $converterscheduledFor = dateTimeMicros;
  static TypeConverter<DateTime?, int?> $converterlastCheckAt =
      nullableDateTimeMicros;
}

class PendingRingRow extends DataClass implements Insertable<PendingRingRow> {
  final int alarmId;
  final int pluginId;
  final RingLockerRole role;
  final DateTime occurrenceAt;
  final DateTime scheduledFor;
  final String courtId;
  final double? volume;
  final double? courtSpeedKmh;
  final double? rawGustKmh;
  final int? courtSpeedLimitKmh;
  final double? rawGustLimitKmh;
  final DateTime? lastCheckAt;
  final bool rollOnDone;
  const PendingRingRow({
    required this.alarmId,
    required this.pluginId,
    required this.role,
    required this.occurrenceAt,
    required this.scheduledFor,
    required this.courtId,
    this.volume,
    this.courtSpeedKmh,
    this.rawGustKmh,
    this.courtSpeedLimitKmh,
    this.rawGustLimitKmh,
    this.lastCheckAt,
    required this.rollOnDone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['alarm_id'] = Variable<int>(alarmId);
    map['plugin_id'] = Variable<int>(pluginId);
    {
      map['role'] = Variable<String>(
        $PendingRingsTable.$converterrole.toSql(role),
      );
    }
    {
      map['occurrence_at'] = Variable<int>(
        $PendingRingsTable.$converteroccurrenceAt.toSql(occurrenceAt),
      );
    }
    {
      map['scheduled_for'] = Variable<int>(
        $PendingRingsTable.$converterscheduledFor.toSql(scheduledFor),
      );
    }
    map['court_id'] = Variable<String>(courtId);
    if (!nullToAbsent || volume != null) {
      map['volume'] = Variable<double>(volume);
    }
    if (!nullToAbsent || courtSpeedKmh != null) {
      map['court_speed_kmh'] = Variable<double>(courtSpeedKmh);
    }
    if (!nullToAbsent || rawGustKmh != null) {
      map['raw_gust_kmh'] = Variable<double>(rawGustKmh);
    }
    if (!nullToAbsent || courtSpeedLimitKmh != null) {
      map['court_speed_limit_kmh'] = Variable<int>(courtSpeedLimitKmh);
    }
    if (!nullToAbsent || rawGustLimitKmh != null) {
      map['raw_gust_limit_kmh'] = Variable<double>(rawGustLimitKmh);
    }
    if (!nullToAbsent || lastCheckAt != null) {
      map['last_check_at'] = Variable<int>(
        $PendingRingsTable.$converterlastCheckAt.toSql(lastCheckAt),
      );
    }
    map['roll_on_done'] = Variable<bool>(rollOnDone);
    return map;
  }

  PendingRingsCompanion toCompanion(bool nullToAbsent) {
    return PendingRingsCompanion(
      alarmId: Value(alarmId),
      pluginId: Value(pluginId),
      role: Value(role),
      occurrenceAt: Value(occurrenceAt),
      scheduledFor: Value(scheduledFor),
      courtId: Value(courtId),
      volume: volume == null && nullToAbsent
          ? const Value.absent()
          : Value(volume),
      courtSpeedKmh: courtSpeedKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(courtSpeedKmh),
      rawGustKmh: rawGustKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(rawGustKmh),
      courtSpeedLimitKmh: courtSpeedLimitKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(courtSpeedLimitKmh),
      rawGustLimitKmh: rawGustLimitKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(rawGustLimitKmh),
      lastCheckAt: lastCheckAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckAt),
      rollOnDone: Value(rollOnDone),
    );
  }

  factory PendingRingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingRingRow(
      alarmId: serializer.fromJson<int>(json['alarmId']),
      pluginId: serializer.fromJson<int>(json['pluginId']),
      role: $PendingRingsTable.$converterrole.fromJson(
        serializer.fromJson<String>(json['role']),
      ),
      occurrenceAt: serializer.fromJson<DateTime>(json['occurrenceAt']),
      scheduledFor: serializer.fromJson<DateTime>(json['scheduledFor']),
      courtId: serializer.fromJson<String>(json['courtId']),
      volume: serializer.fromJson<double?>(json['volume']),
      courtSpeedKmh: serializer.fromJson<double?>(json['courtSpeedKmh']),
      rawGustKmh: serializer.fromJson<double?>(json['rawGustKmh']),
      courtSpeedLimitKmh: serializer.fromJson<int?>(json['courtSpeedLimitKmh']),
      rawGustLimitKmh: serializer.fromJson<double?>(json['rawGustLimitKmh']),
      lastCheckAt: serializer.fromJson<DateTime?>(json['lastCheckAt']),
      rollOnDone: serializer.fromJson<bool>(json['rollOnDone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'alarmId': serializer.toJson<int>(alarmId),
      'pluginId': serializer.toJson<int>(pluginId),
      'role': serializer.toJson<String>(
        $PendingRingsTable.$converterrole.toJson(role),
      ),
      'occurrenceAt': serializer.toJson<DateTime>(occurrenceAt),
      'scheduledFor': serializer.toJson<DateTime>(scheduledFor),
      'courtId': serializer.toJson<String>(courtId),
      'volume': serializer.toJson<double?>(volume),
      'courtSpeedKmh': serializer.toJson<double?>(courtSpeedKmh),
      'rawGustKmh': serializer.toJson<double?>(rawGustKmh),
      'courtSpeedLimitKmh': serializer.toJson<int?>(courtSpeedLimitKmh),
      'rawGustLimitKmh': serializer.toJson<double?>(rawGustLimitKmh),
      'lastCheckAt': serializer.toJson<DateTime?>(lastCheckAt),
      'rollOnDone': serializer.toJson<bool>(rollOnDone),
    };
  }

  PendingRingRow copyWith({
    int? alarmId,
    int? pluginId,
    RingLockerRole? role,
    DateTime? occurrenceAt,
    DateTime? scheduledFor,
    String? courtId,
    Value<double?> volume = const Value.absent(),
    Value<double?> courtSpeedKmh = const Value.absent(),
    Value<double?> rawGustKmh = const Value.absent(),
    Value<int?> courtSpeedLimitKmh = const Value.absent(),
    Value<double?> rawGustLimitKmh = const Value.absent(),
    Value<DateTime?> lastCheckAt = const Value.absent(),
    bool? rollOnDone,
  }) => PendingRingRow(
    alarmId: alarmId ?? this.alarmId,
    pluginId: pluginId ?? this.pluginId,
    role: role ?? this.role,
    occurrenceAt: occurrenceAt ?? this.occurrenceAt,
    scheduledFor: scheduledFor ?? this.scheduledFor,
    courtId: courtId ?? this.courtId,
    volume: volume.present ? volume.value : this.volume,
    courtSpeedKmh: courtSpeedKmh.present
        ? courtSpeedKmh.value
        : this.courtSpeedKmh,
    rawGustKmh: rawGustKmh.present ? rawGustKmh.value : this.rawGustKmh,
    courtSpeedLimitKmh: courtSpeedLimitKmh.present
        ? courtSpeedLimitKmh.value
        : this.courtSpeedLimitKmh,
    rawGustLimitKmh: rawGustLimitKmh.present
        ? rawGustLimitKmh.value
        : this.rawGustLimitKmh,
    lastCheckAt: lastCheckAt.present ? lastCheckAt.value : this.lastCheckAt,
    rollOnDone: rollOnDone ?? this.rollOnDone,
  );
  PendingRingRow copyWithCompanion(PendingRingsCompanion data) {
    return PendingRingRow(
      alarmId: data.alarmId.present ? data.alarmId.value : this.alarmId,
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      role: data.role.present ? data.role.value : this.role,
      occurrenceAt: data.occurrenceAt.present
          ? data.occurrenceAt.value
          : this.occurrenceAt,
      scheduledFor: data.scheduledFor.present
          ? data.scheduledFor.value
          : this.scheduledFor,
      courtId: data.courtId.present ? data.courtId.value : this.courtId,
      volume: data.volume.present ? data.volume.value : this.volume,
      courtSpeedKmh: data.courtSpeedKmh.present
          ? data.courtSpeedKmh.value
          : this.courtSpeedKmh,
      rawGustKmh: data.rawGustKmh.present
          ? data.rawGustKmh.value
          : this.rawGustKmh,
      courtSpeedLimitKmh: data.courtSpeedLimitKmh.present
          ? data.courtSpeedLimitKmh.value
          : this.courtSpeedLimitKmh,
      rawGustLimitKmh: data.rawGustLimitKmh.present
          ? data.rawGustLimitKmh.value
          : this.rawGustLimitKmh,
      lastCheckAt: data.lastCheckAt.present
          ? data.lastCheckAt.value
          : this.lastCheckAt,
      rollOnDone: data.rollOnDone.present
          ? data.rollOnDone.value
          : this.rollOnDone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingRingRow(')
          ..write('alarmId: $alarmId, ')
          ..write('pluginId: $pluginId, ')
          ..write('role: $role, ')
          ..write('occurrenceAt: $occurrenceAt, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('courtId: $courtId, ')
          ..write('volume: $volume, ')
          ..write('courtSpeedKmh: $courtSpeedKmh, ')
          ..write('rawGustKmh: $rawGustKmh, ')
          ..write('courtSpeedLimitKmh: $courtSpeedLimitKmh, ')
          ..write('rawGustLimitKmh: $rawGustLimitKmh, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('rollOnDone: $rollOnDone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    alarmId,
    pluginId,
    role,
    occurrenceAt,
    scheduledFor,
    courtId,
    volume,
    courtSpeedKmh,
    rawGustKmh,
    courtSpeedLimitKmh,
    rawGustLimitKmh,
    lastCheckAt,
    rollOnDone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingRingRow &&
          other.alarmId == this.alarmId &&
          other.pluginId == this.pluginId &&
          other.role == this.role &&
          other.occurrenceAt == this.occurrenceAt &&
          other.scheduledFor == this.scheduledFor &&
          other.courtId == this.courtId &&
          other.volume == this.volume &&
          other.courtSpeedKmh == this.courtSpeedKmh &&
          other.rawGustKmh == this.rawGustKmh &&
          other.courtSpeedLimitKmh == this.courtSpeedLimitKmh &&
          other.rawGustLimitKmh == this.rawGustLimitKmh &&
          other.lastCheckAt == this.lastCheckAt &&
          other.rollOnDone == this.rollOnDone);
}

class PendingRingsCompanion extends UpdateCompanion<PendingRingRow> {
  final Value<int> alarmId;
  final Value<int> pluginId;
  final Value<RingLockerRole> role;
  final Value<DateTime> occurrenceAt;
  final Value<DateTime> scheduledFor;
  final Value<String> courtId;
  final Value<double?> volume;
  final Value<double?> courtSpeedKmh;
  final Value<double?> rawGustKmh;
  final Value<int?> courtSpeedLimitKmh;
  final Value<double?> rawGustLimitKmh;
  final Value<DateTime?> lastCheckAt;
  final Value<bool> rollOnDone;
  const PendingRingsCompanion({
    this.alarmId = const Value.absent(),
    this.pluginId = const Value.absent(),
    this.role = const Value.absent(),
    this.occurrenceAt = const Value.absent(),
    this.scheduledFor = const Value.absent(),
    this.courtId = const Value.absent(),
    this.volume = const Value.absent(),
    this.courtSpeedKmh = const Value.absent(),
    this.rawGustKmh = const Value.absent(),
    this.courtSpeedLimitKmh = const Value.absent(),
    this.rawGustLimitKmh = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.rollOnDone = const Value.absent(),
  });
  PendingRingsCompanion.insert({
    this.alarmId = const Value.absent(),
    required int pluginId,
    required RingLockerRole role,
    required DateTime occurrenceAt,
    required DateTime scheduledFor,
    required String courtId,
    this.volume = const Value.absent(),
    this.courtSpeedKmh = const Value.absent(),
    this.rawGustKmh = const Value.absent(),
    this.courtSpeedLimitKmh = const Value.absent(),
    this.rawGustLimitKmh = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    required bool rollOnDone,
  }) : pluginId = Value(pluginId),
       role = Value(role),
       occurrenceAt = Value(occurrenceAt),
       scheduledFor = Value(scheduledFor),
       courtId = Value(courtId),
       rollOnDone = Value(rollOnDone);
  static Insertable<PendingRingRow> custom({
    Expression<int>? alarmId,
    Expression<int>? pluginId,
    Expression<String>? role,
    Expression<int>? occurrenceAt,
    Expression<int>? scheduledFor,
    Expression<String>? courtId,
    Expression<double>? volume,
    Expression<double>? courtSpeedKmh,
    Expression<double>? rawGustKmh,
    Expression<int>? courtSpeedLimitKmh,
    Expression<double>? rawGustLimitKmh,
    Expression<int>? lastCheckAt,
    Expression<bool>? rollOnDone,
  }) {
    return RawValuesInsertable({
      if (alarmId != null) 'alarm_id': alarmId,
      if (pluginId != null) 'plugin_id': pluginId,
      if (role != null) 'role': role,
      if (occurrenceAt != null) 'occurrence_at': occurrenceAt,
      if (scheduledFor != null) 'scheduled_for': scheduledFor,
      if (courtId != null) 'court_id': courtId,
      if (volume != null) 'volume': volume,
      if (courtSpeedKmh != null) 'court_speed_kmh': courtSpeedKmh,
      if (rawGustKmh != null) 'raw_gust_kmh': rawGustKmh,
      if (courtSpeedLimitKmh != null)
        'court_speed_limit_kmh': courtSpeedLimitKmh,
      if (rawGustLimitKmh != null) 'raw_gust_limit_kmh': rawGustLimitKmh,
      if (lastCheckAt != null) 'last_check_at': lastCheckAt,
      if (rollOnDone != null) 'roll_on_done': rollOnDone,
    });
  }

  PendingRingsCompanion copyWith({
    Value<int>? alarmId,
    Value<int>? pluginId,
    Value<RingLockerRole>? role,
    Value<DateTime>? occurrenceAt,
    Value<DateTime>? scheduledFor,
    Value<String>? courtId,
    Value<double?>? volume,
    Value<double?>? courtSpeedKmh,
    Value<double?>? rawGustKmh,
    Value<int?>? courtSpeedLimitKmh,
    Value<double?>? rawGustLimitKmh,
    Value<DateTime?>? lastCheckAt,
    Value<bool>? rollOnDone,
  }) {
    return PendingRingsCompanion(
      alarmId: alarmId ?? this.alarmId,
      pluginId: pluginId ?? this.pluginId,
      role: role ?? this.role,
      occurrenceAt: occurrenceAt ?? this.occurrenceAt,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      courtId: courtId ?? this.courtId,
      volume: volume ?? this.volume,
      courtSpeedKmh: courtSpeedKmh ?? this.courtSpeedKmh,
      rawGustKmh: rawGustKmh ?? this.rawGustKmh,
      courtSpeedLimitKmh: courtSpeedLimitKmh ?? this.courtSpeedLimitKmh,
      rawGustLimitKmh: rawGustLimitKmh ?? this.rawGustLimitKmh,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      rollOnDone: rollOnDone ?? this.rollOnDone,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (alarmId.present) {
      map['alarm_id'] = Variable<int>(alarmId.value);
    }
    if (pluginId.present) {
      map['plugin_id'] = Variable<int>(pluginId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(
        $PendingRingsTable.$converterrole.toSql(role.value),
      );
    }
    if (occurrenceAt.present) {
      map['occurrence_at'] = Variable<int>(
        $PendingRingsTable.$converteroccurrenceAt.toSql(occurrenceAt.value),
      );
    }
    if (scheduledFor.present) {
      map['scheduled_for'] = Variable<int>(
        $PendingRingsTable.$converterscheduledFor.toSql(scheduledFor.value),
      );
    }
    if (courtId.present) {
      map['court_id'] = Variable<String>(courtId.value);
    }
    if (volume.present) {
      map['volume'] = Variable<double>(volume.value);
    }
    if (courtSpeedKmh.present) {
      map['court_speed_kmh'] = Variable<double>(courtSpeedKmh.value);
    }
    if (rawGustKmh.present) {
      map['raw_gust_kmh'] = Variable<double>(rawGustKmh.value);
    }
    if (courtSpeedLimitKmh.present) {
      map['court_speed_limit_kmh'] = Variable<int>(courtSpeedLimitKmh.value);
    }
    if (rawGustLimitKmh.present) {
      map['raw_gust_limit_kmh'] = Variable<double>(rawGustLimitKmh.value);
    }
    if (lastCheckAt.present) {
      map['last_check_at'] = Variable<int>(
        $PendingRingsTable.$converterlastCheckAt.toSql(lastCheckAt.value),
      );
    }
    if (rollOnDone.present) {
      map['roll_on_done'] = Variable<bool>(rollOnDone.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingRingsCompanion(')
          ..write('alarmId: $alarmId, ')
          ..write('pluginId: $pluginId, ')
          ..write('role: $role, ')
          ..write('occurrenceAt: $occurrenceAt, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('courtId: $courtId, ')
          ..write('volume: $volume, ')
          ..write('courtSpeedKmh: $courtSpeedKmh, ')
          ..write('rawGustKmh: $rawGustKmh, ')
          ..write('courtSpeedLimitKmh: $courtSpeedLimitKmh, ')
          ..write('rawGustLimitKmh: $rawGustLimitKmh, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('rollOnDone: $rollOnDone')
          ..write(')'))
        .toString();
  }
}

class $HostEventClaimsTable extends HostEventClaims
    with TableInfo<$HostEventClaimsTable, HostEventClaim> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostEventClaimsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _claimKeyMeta = const VerificationMeta(
    'claimKey',
  );
  @override
  late final GeneratedColumn<String> claimKey = GeneratedColumn<String>(
    'claim_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<HostEventClaimState, String>
  state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<HostEventClaimState>($HostEventClaimsTable.$converterstate);
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> leasedUntil =
      GeneratedColumn<int>(
        'leased_until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($HostEventClaimsTable.$converterleasedUntil);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> recordedAt =
      GeneratedColumn<int>(
        'recorded_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($HostEventClaimsTable.$converterrecordedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($HostEventClaimsTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    claimKey,
    state,
    attempts,
    leasedUntil,
    recordedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'host_event_claims';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostEventClaim> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('claim_key')) {
      context.handle(
        _claimKeyMeta,
        claimKey.isAcceptableOrUnknown(data['claim_key']!, _claimKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_claimKeyMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {claimKey};
  @override
  HostEventClaim map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostEventClaim(
      claimKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claim_key'],
      )!,
      state: $HostEventClaimsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      leasedUntil: $HostEventClaimsTable.$converterleasedUntil.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}leased_until'],
        ),
      ),
      recordedAt: $HostEventClaimsTable.$converterrecordedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}recorded_at'],
        )!,
      ),
      updatedAt: $HostEventClaimsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $HostEventClaimsTable createAlias(String alias) {
    return $HostEventClaimsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<HostEventClaimState, String, String>
  $converterstate = const EnumNameConverter<HostEventClaimState>(
    HostEventClaimState.values,
  );
  static TypeConverter<DateTime?, int?> $converterleasedUntil =
      nullableDateTimeMicros;
  static TypeConverter<DateTime, int> $converterrecordedAt = dateTimeMicros;
  static TypeConverter<DateTime, int> $converterupdatedAt = dateTimeMicros;
}

class HostEventClaim extends DataClass implements Insertable<HostEventClaim> {
  final String claimKey;
  final HostEventClaimState state;
  final int attempts;
  final DateTime? leasedUntil;

  /// The event's own `recordedAt`, kept as a column rather than parsed back out
  /// of [claimKey] so the TTL sweep is a `WHERE` clause instead of a scan.
  final DateTime recordedAt;
  final DateTime updatedAt;
  const HostEventClaim({
    required this.claimKey,
    required this.state,
    required this.attempts,
    this.leasedUntil,
    required this.recordedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['claim_key'] = Variable<String>(claimKey);
    {
      map['state'] = Variable<String>(
        $HostEventClaimsTable.$converterstate.toSql(state),
      );
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || leasedUntil != null) {
      map['leased_until'] = Variable<int>(
        $HostEventClaimsTable.$converterleasedUntil.toSql(leasedUntil),
      );
    }
    {
      map['recorded_at'] = Variable<int>(
        $HostEventClaimsTable.$converterrecordedAt.toSql(recordedAt),
      );
    }
    {
      map['updated_at'] = Variable<int>(
        $HostEventClaimsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  HostEventClaimsCompanion toCompanion(bool nullToAbsent) {
    return HostEventClaimsCompanion(
      claimKey: Value(claimKey),
      state: Value(state),
      attempts: Value(attempts),
      leasedUntil: leasedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(leasedUntil),
      recordedAt: Value(recordedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory HostEventClaim.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostEventClaim(
      claimKey: serializer.fromJson<String>(json['claimKey']),
      state: $HostEventClaimsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      attempts: serializer.fromJson<int>(json['attempts']),
      leasedUntil: serializer.fromJson<DateTime?>(json['leasedUntil']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'claimKey': serializer.toJson<String>(claimKey),
      'state': serializer.toJson<String>(
        $HostEventClaimsTable.$converterstate.toJson(state),
      ),
      'attempts': serializer.toJson<int>(attempts),
      'leasedUntil': serializer.toJson<DateTime?>(leasedUntil),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  HostEventClaim copyWith({
    String? claimKey,
    HostEventClaimState? state,
    int? attempts,
    Value<DateTime?> leasedUntil = const Value.absent(),
    DateTime? recordedAt,
    DateTime? updatedAt,
  }) => HostEventClaim(
    claimKey: claimKey ?? this.claimKey,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    leasedUntil: leasedUntil.present ? leasedUntil.value : this.leasedUntil,
    recordedAt: recordedAt ?? this.recordedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  HostEventClaim copyWithCompanion(HostEventClaimsCompanion data) {
    return HostEventClaim(
      claimKey: data.claimKey.present ? data.claimKey.value : this.claimKey,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      leasedUntil: data.leasedUntil.present
          ? data.leasedUntil.value
          : this.leasedUntil,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostEventClaim(')
          ..write('claimKey: $claimKey, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('leasedUntil: $leasedUntil, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    claimKey,
    state,
    attempts,
    leasedUntil,
    recordedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostEventClaim &&
          other.claimKey == this.claimKey &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.leasedUntil == this.leasedUntil &&
          other.recordedAt == this.recordedAt &&
          other.updatedAt == this.updatedAt);
}

class HostEventClaimsCompanion extends UpdateCompanion<HostEventClaim> {
  final Value<String> claimKey;
  final Value<HostEventClaimState> state;
  final Value<int> attempts;
  final Value<DateTime?> leasedUntil;
  final Value<DateTime> recordedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const HostEventClaimsCompanion({
    this.claimKey = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.leasedUntil = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostEventClaimsCompanion.insert({
    required String claimKey,
    required HostEventClaimState state,
    this.attempts = const Value.absent(),
    this.leasedUntil = const Value.absent(),
    required DateTime recordedAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : claimKey = Value(claimKey),
       state = Value(state),
       recordedAt = Value(recordedAt),
       updatedAt = Value(updatedAt);
  static Insertable<HostEventClaim> custom({
    Expression<String>? claimKey,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<int>? leasedUntil,
    Expression<int>? recordedAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (claimKey != null) 'claim_key': claimKey,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (leasedUntil != null) 'leased_until': leasedUntil,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostEventClaimsCompanion copyWith({
    Value<String>? claimKey,
    Value<HostEventClaimState>? state,
    Value<int>? attempts,
    Value<DateTime?>? leasedUntil,
    Value<DateTime>? recordedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return HostEventClaimsCompanion(
      claimKey: claimKey ?? this.claimKey,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      leasedUntil: leasedUntil ?? this.leasedUntil,
      recordedAt: recordedAt ?? this.recordedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (claimKey.present) {
      map['claim_key'] = Variable<String>(claimKey.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $HostEventClaimsTable.$converterstate.toSql(state.value),
      );
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (leasedUntil.present) {
      map['leased_until'] = Variable<int>(
        $HostEventClaimsTable.$converterleasedUntil.toSql(leasedUntil.value),
      );
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<int>(
        $HostEventClaimsTable.$converterrecordedAt.toSql(recordedAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $HostEventClaimsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostEventClaimsCompanion(')
          ..write('claimKey: $claimKey, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('leasedUntil: $leasedUntil, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlarmKitHandlesTable extends AlarmKitHandles
    with TableInfo<$AlarmKitHandlesTable, AlarmKitHandle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmKitHandlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _alarmIdMeta = const VerificationMeta(
    'alarmId',
  );
  @override
  late final GeneratedColumn<int> alarmId = GeneratedColumn<int>(
    'alarm_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($AlarmKitHandlesTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [alarmId, uuid, seq, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_kit_handles';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmKitHandle> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('alarm_id')) {
      context.handle(
        _alarmIdMeta,
        alarmId.isAcceptableOrUnknown(data['alarm_id']!, _alarmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_alarmIdMeta);
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {alarmId, uuid};
  @override
  AlarmKitHandle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmKitHandle(
      alarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alarm_id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      createdAt: $AlarmKitHandlesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $AlarmKitHandlesTable createAlias(String alias) {
    return $AlarmKitHandlesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt = dateTimeMicros;
}

class AlarmKitHandle extends DataClass implements Insertable<AlarmKitHandle> {
  final int alarmId;
  final String uuid;
  final int seq;

  /// When this handle was recorded — the fence the prune compares against.
  ///
  /// Pruning asks AlarmKit what it still knows and deletes everything else, and
  /// that answer is a SNAPSHOT. Another isolate arming an alarm in the gap
  /// between the snapshot and the delete would have its brand-new handle read
  /// as "AlarmKit has forgotten this" and removed — orphaning an armed alarm,
  /// which is the exact failure the map exists to prevent. A handle recorded
  /// after the snapshot was taken is therefore never eligible: `scheduleRing`
  /// writes the row only once `scheduleOneShotAlarm` has returned, so anything
  /// recorded before the snapshot was already known to AlarmKit when it was
  /// asked.
  final DateTime createdAt;
  const AlarmKitHandle({
    required this.alarmId,
    required this.uuid,
    required this.seq,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['alarm_id'] = Variable<int>(alarmId);
    map['uuid'] = Variable<String>(uuid);
    map['seq'] = Variable<int>(seq);
    {
      map['created_at'] = Variable<int>(
        $AlarmKitHandlesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  AlarmKitHandlesCompanion toCompanion(bool nullToAbsent) {
    return AlarmKitHandlesCompanion(
      alarmId: Value(alarmId),
      uuid: Value(uuid),
      seq: Value(seq),
      createdAt: Value(createdAt),
    );
  }

  factory AlarmKitHandle.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmKitHandle(
      alarmId: serializer.fromJson<int>(json['alarmId']),
      uuid: serializer.fromJson<String>(json['uuid']),
      seq: serializer.fromJson<int>(json['seq']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'alarmId': serializer.toJson<int>(alarmId),
      'uuid': serializer.toJson<String>(uuid),
      'seq': serializer.toJson<int>(seq),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AlarmKitHandle copyWith({
    int? alarmId,
    String? uuid,
    int? seq,
    DateTime? createdAt,
  }) => AlarmKitHandle(
    alarmId: alarmId ?? this.alarmId,
    uuid: uuid ?? this.uuid,
    seq: seq ?? this.seq,
    createdAt: createdAt ?? this.createdAt,
  );
  AlarmKitHandle copyWithCompanion(AlarmKitHandlesCompanion data) {
    return AlarmKitHandle(
      alarmId: data.alarmId.present ? data.alarmId.value : this.alarmId,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      seq: data.seq.present ? data.seq.value : this.seq,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmKitHandle(')
          ..write('alarmId: $alarmId, ')
          ..write('uuid: $uuid, ')
          ..write('seq: $seq, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(alarmId, uuid, seq, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmKitHandle &&
          other.alarmId == this.alarmId &&
          other.uuid == this.uuid &&
          other.seq == this.seq &&
          other.createdAt == this.createdAt);
}

class AlarmKitHandlesCompanion extends UpdateCompanion<AlarmKitHandle> {
  final Value<int> alarmId;
  final Value<String> uuid;
  final Value<int> seq;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AlarmKitHandlesCompanion({
    this.alarmId = const Value.absent(),
    this.uuid = const Value.absent(),
    this.seq = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlarmKitHandlesCompanion.insert({
    required int alarmId,
    required String uuid,
    required int seq,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : alarmId = Value(alarmId),
       uuid = Value(uuid),
       seq = Value(seq),
       createdAt = Value(createdAt);
  static Insertable<AlarmKitHandle> custom({
    Expression<int>? alarmId,
    Expression<String>? uuid,
    Expression<int>? seq,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (alarmId != null) 'alarm_id': alarmId,
      if (uuid != null) 'uuid': uuid,
      if (seq != null) 'seq': seq,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlarmKitHandlesCompanion copyWith({
    Value<int>? alarmId,
    Value<String>? uuid,
    Value<int>? seq,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AlarmKitHandlesCompanion(
      alarmId: alarmId ?? this.alarmId,
      uuid: uuid ?? this.uuid,
      seq: seq ?? this.seq,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (alarmId.present) {
      map['alarm_id'] = Variable<int>(alarmId.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $AlarmKitHandlesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmKitHandlesCompanion(')
          ..write('alarmId: $alarmId, ')
          ..write('uuid: $uuid, ')
          ..write('seq: $seq, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dedupKeyMeta = const VerificationMeta(
    'dedupKey',
  );
  @override
  late final GeneratedColumn<String> dedupKey = GeneratedColumn<String>(
    'dedup_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<OutboxState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<OutboxState>($OutboxEntriesTable.$converterstate);
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> leasedUntil =
      GeneratedColumn<int>(
        'leased_until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($OutboxEntriesTable.$converterleasedUntil);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($OutboxEntriesTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($OutboxEntriesTable.$converterupdatedAt);
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    dedupKey,
    payload,
    state,
    attempts,
    leasedUntil,
    createdAt,
    updatedAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('dedup_key')) {
      context.handle(
        _dedupKeyMeta,
        dedupKey.isAcceptableOrUnknown(data['dedup_key']!, _dedupKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dedupKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      dedupKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dedup_key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      state: $OutboxEntriesTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      leasedUntil: $OutboxEntriesTable.$converterleasedUntil.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}leased_until'],
        ),
      ),
      createdAt: $OutboxEntriesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $OutboxEntriesTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OutboxState, String, String> $converterstate =
      const EnumNameConverter<OutboxState>(OutboxState.values);
  static TypeConverter<DateTime?, int?> $converterleasedUntil =
      nullableDateTimeMicros;
  static TypeConverter<DateTime, int> $convertercreatedAt = dateTimeMicros;
  static TypeConverter<DateTime, int> $converterupdatedAt = dateTimeMicros;
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final int id;
  final String kind;
  final String dedupKey;
  final String payload;
  final OutboxState state;
  final int attempts;
  final DateTime? leasedUntil;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;
  const OutboxEntry({
    required this.id,
    required this.kind,
    required this.dedupKey,
    required this.payload,
    required this.state,
    required this.attempts,
    this.leasedUntil,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['dedup_key'] = Variable<String>(dedupKey);
    map['payload'] = Variable<String>(payload);
    {
      map['state'] = Variable<String>(
        $OutboxEntriesTable.$converterstate.toSql(state),
      );
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || leasedUntil != null) {
      map['leased_until'] = Variable<int>(
        $OutboxEntriesTable.$converterleasedUntil.toSql(leasedUntil),
      );
    }
    {
      map['created_at'] = Variable<int>(
        $OutboxEntriesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<int>(
        $OutboxEntriesTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      id: Value(id),
      kind: Value(kind),
      dedupKey: Value(dedupKey),
      payload: Value(payload),
      state: Value(state),
      attempts: Value(attempts),
      leasedUntil: leasedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(leasedUntil),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      dedupKey: serializer.fromJson<String>(json['dedupKey']),
      payload: serializer.fromJson<String>(json['payload']),
      state: $OutboxEntriesTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      attempts: serializer.fromJson<int>(json['attempts']),
      leasedUntil: serializer.fromJson<DateTime?>(json['leasedUntil']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'dedupKey': serializer.toJson<String>(dedupKey),
      'payload': serializer.toJson<String>(payload),
      'state': serializer.toJson<String>(
        $OutboxEntriesTable.$converterstate.toJson(state),
      ),
      'attempts': serializer.toJson<int>(attempts),
      'leasedUntil': serializer.toJson<DateTime?>(leasedUntil),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxEntry copyWith({
    int? id,
    String? kind,
    String? dedupKey,
    String? payload,
    OutboxState? state,
    int? attempts,
    Value<DateTime?> leasedUntil = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxEntry(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    dedupKey: dedupKey ?? this.dedupKey,
    payload: payload ?? this.payload,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    leasedUntil: leasedUntil.present ? leasedUntil.value : this.leasedUntil,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxEntry copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxEntry(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      dedupKey: data.dedupKey.present ? data.dedupKey.value : this.dedupKey,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      leasedUntil: data.leasedUntil.present
          ? data.leasedUntil.value
          : this.leasedUntil,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('dedupKey: $dedupKey, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('leasedUntil: $leasedUntil, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    dedupKey,
    payload,
    state,
    attempts,
    leasedUntil,
    createdAt,
    updatedAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.dedupKey == this.dedupKey &&
          other.payload == this.payload &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.leasedUntil == this.leasedUntil &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastError == this.lastError);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> dedupKey;
  final Value<String> payload;
  final Value<OutboxState> state;
  final Value<int> attempts;
  final Value<DateTime?> leasedUntil;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> lastError;
  const OutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.dedupKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.leasedUntil = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String dedupKey,
    required String payload,
    required OutboxState state,
    this.attempts = const Value.absent(),
    this.leasedUntil = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.lastError = const Value.absent(),
  }) : kind = Value(kind),
       dedupKey = Value(dedupKey),
       payload = Value(payload),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<OutboxEntry> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? dedupKey,
    Expression<String>? payload,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<int>? leasedUntil,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (dedupKey != null) 'dedup_key': dedupKey,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (leasedUntil != null) 'leased_until': leasedUntil,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? dedupKey,
    Value<String>? payload,
    Value<OutboxState>? state,
    Value<int>? attempts,
    Value<DateTime?>? leasedUntil,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? lastError,
  }) {
    return OutboxEntriesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      dedupKey: dedupKey ?? this.dedupKey,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      leasedUntil: leasedUntil ?? this.leasedUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (dedupKey.present) {
      map['dedup_key'] = Variable<String>(dedupKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $OutboxEntriesTable.$converterstate.toSql(state.value),
      );
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (leasedUntil.present) {
      map['leased_until'] = Variable<int>(
        $OutboxEntriesTable.$converterleasedUntil.toSql(leasedUntil.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $OutboxEntriesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $OutboxEntriesTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('dedupKey: $dedupKey, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('leasedUntil: $leasedUntil, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CourtsTable courts = $CourtsTable(this);
  late final $NivaatAlarmsTable nivaatAlarms = $NivaatAlarmsTable(this);
  late final $CountersTable counters = $CountersTable(this);
  late final $HistoryEntriesTable historyEntries = $HistoryEntriesTable(this);
  late final $CheckStatesTable checkStates = $CheckStatesTable(this);
  late final $PendingRingsTable pendingRings = $PendingRingsTable(this);
  late final $HostEventClaimsTable hostEventClaims = $HostEventClaimsTable(
    this,
  );
  late final $AlarmKitHandlesTable alarmKitHandles = $AlarmKitHandlesTable(
    this,
  );
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    courts,
    nivaatAlarms,
    counters,
    historyEntries,
    checkStates,
    pendingRings,
    hostEventClaims,
    alarmKitHandles,
    outboxEntries,
  ];
}

typedef $$CourtsTableCreateCompanionBuilder =
    CourtsCompanion Function({
      required String id,
      required String name,
      required double lat,
      required double lon,
      required PlaceSource source,
      Value<String?> region,
      required int position,
      Value<int> rowid,
    });
typedef $$CourtsTableUpdateCompanionBuilder =
    CourtsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> lat,
      Value<double> lon,
      Value<PlaceSource> source,
      Value<String?> region,
      Value<int> position,
      Value<int> rowid,
    });

class $$CourtsTableFilterComposer
    extends Composer<_$AppDatabase, $CourtsTable> {
  $$CourtsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PlaceSource, PlaceSource, String> get source =>
      $composableBuilder(
        column: $table.source,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CourtsTableOrderingComposer
    extends Composer<_$AppDatabase, $CourtsTable> {
  $$CourtsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get region => $composableBuilder(
    column: $table.region,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CourtsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourtsTable> {
  $$CourtsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PlaceSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get region =>
      $composableBuilder(column: $table.region, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$CourtsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CourtsTable,
          Court,
          $$CourtsTableFilterComposer,
          $$CourtsTableOrderingComposer,
          $$CourtsTableAnnotationComposer,
          $$CourtsTableCreateCompanionBuilder,
          $$CourtsTableUpdateCompanionBuilder,
          (Court, BaseReferences<_$AppDatabase, $CourtsTable, Court>),
          Court,
          PrefetchHooks Function()
        > {
  $$CourtsTableTableManager(_$AppDatabase db, $CourtsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourtsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourtsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourtsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<PlaceSource> source = const Value.absent(),
                Value<String?> region = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CourtsCompanion(
                id: id,
                name: name,
                lat: lat,
                lon: lon,
                source: source,
                region: region,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required double lat,
                required double lon,
                required PlaceSource source,
                Value<String?> region = const Value.absent(),
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => CourtsCompanion.insert(
                id: id,
                name: name,
                lat: lat,
                lon: lon,
                source: source,
                region: region,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CourtsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CourtsTable,
      Court,
      $$CourtsTableFilterComposer,
      $$CourtsTableOrderingComposer,
      $$CourtsTableAnnotationComposer,
      $$CourtsTableCreateCompanionBuilder,
      $$CourtsTableUpdateCompanionBuilder,
      (Court, BaseReferences<_$AppDatabase, $CourtsTable, Court>),
      Court,
      PrefetchHooks Function()
    >;
typedef $$NivaatAlarmsTableCreateCompanionBuilder =
    NivaatAlarmsCompanion Function({
      Value<int> id,
      required int hour,
      required int minute,
      required String courtId,
      required int courtSpeedLimitKmh,
      required int retryMinutesAfter,
      required Set<int> weekdays,
      required bool enabled,
      required int position,
    });
typedef $$NivaatAlarmsTableUpdateCompanionBuilder =
    NivaatAlarmsCompanion Function({
      Value<int> id,
      Value<int> hour,
      Value<int> minute,
      Value<String> courtId,
      Value<int> courtSpeedLimitKmh,
      Value<int> retryMinutesAfter,
      Value<Set<int>> weekdays,
      Value<bool> enabled,
      Value<int> position,
    });

class $$NivaatAlarmsTableFilterComposer
    extends Composer<_$AppDatabase, $NivaatAlarmsTable> {
  $$NivaatAlarmsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hour => $composableBuilder(
    column: $table.hour,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minute => $composableBuilder(
    column: $table.minute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get courtId => $composableBuilder(
    column: $table.courtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryMinutesAfter => $composableBuilder(
    column: $table.retryMinutesAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Set<int>, Set<int>, String> get weekdays =>
      $composableBuilder(
        column: $table.weekdays,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NivaatAlarmsTableOrderingComposer
    extends Composer<_$AppDatabase, $NivaatAlarmsTable> {
  $$NivaatAlarmsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hour => $composableBuilder(
    column: $table.hour,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minute => $composableBuilder(
    column: $table.minute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courtId => $composableBuilder(
    column: $table.courtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryMinutesAfter => $composableBuilder(
    column: $table.retryMinutesAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekdays => $composableBuilder(
    column: $table.weekdays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NivaatAlarmsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NivaatAlarmsTable> {
  $$NivaatAlarmsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get hour =>
      $composableBuilder(column: $table.hour, builder: (column) => column);

  GeneratedColumn<int> get minute =>
      $composableBuilder(column: $table.minute, builder: (column) => column);

  GeneratedColumn<String> get courtId =>
      $composableBuilder(column: $table.courtId, builder: (column) => column);

  GeneratedColumn<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryMinutesAfter => $composableBuilder(
    column: $table.retryMinutesAfter,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Set<int>, String> get weekdays =>
      $composableBuilder(column: $table.weekdays, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$NivaatAlarmsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NivaatAlarmsTable,
          AlarmRow,
          $$NivaatAlarmsTableFilterComposer,
          $$NivaatAlarmsTableOrderingComposer,
          $$NivaatAlarmsTableAnnotationComposer,
          $$NivaatAlarmsTableCreateCompanionBuilder,
          $$NivaatAlarmsTableUpdateCompanionBuilder,
          (
            AlarmRow,
            BaseReferences<_$AppDatabase, $NivaatAlarmsTable, AlarmRow>,
          ),
          AlarmRow,
          PrefetchHooks Function()
        > {
  $$NivaatAlarmsTableTableManager(_$AppDatabase db, $NivaatAlarmsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NivaatAlarmsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NivaatAlarmsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NivaatAlarmsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> hour = const Value.absent(),
                Value<int> minute = const Value.absent(),
                Value<String> courtId = const Value.absent(),
                Value<int> courtSpeedLimitKmh = const Value.absent(),
                Value<int> retryMinutesAfter = const Value.absent(),
                Value<Set<int>> weekdays = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => NivaatAlarmsCompanion(
                id: id,
                hour: hour,
                minute: minute,
                courtId: courtId,
                courtSpeedLimitKmh: courtSpeedLimitKmh,
                retryMinutesAfter: retryMinutesAfter,
                weekdays: weekdays,
                enabled: enabled,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int hour,
                required int minute,
                required String courtId,
                required int courtSpeedLimitKmh,
                required int retryMinutesAfter,
                required Set<int> weekdays,
                required bool enabled,
                required int position,
              }) => NivaatAlarmsCompanion.insert(
                id: id,
                hour: hour,
                minute: minute,
                courtId: courtId,
                courtSpeedLimitKmh: courtSpeedLimitKmh,
                retryMinutesAfter: retryMinutesAfter,
                weekdays: weekdays,
                enabled: enabled,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NivaatAlarmsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NivaatAlarmsTable,
      AlarmRow,
      $$NivaatAlarmsTableFilterComposer,
      $$NivaatAlarmsTableOrderingComposer,
      $$NivaatAlarmsTableAnnotationComposer,
      $$NivaatAlarmsTableCreateCompanionBuilder,
      $$NivaatAlarmsTableUpdateCompanionBuilder,
      (AlarmRow, BaseReferences<_$AppDatabase, $NivaatAlarmsTable, AlarmRow>),
      AlarmRow,
      PrefetchHooks Function()
    >;
typedef $$CountersTableCreateCompanionBuilder =
    CountersCompanion Function({
      required String name,
      required int value,
      Value<int> rowid,
    });
typedef $$CountersTableUpdateCompanionBuilder =
    CountersCompanion Function({
      Value<String> name,
      Value<int> value,
      Value<int> rowid,
    });

class $$CountersTableFilterComposer
    extends Composer<_$AppDatabase, $CountersTable> {
  $$CountersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CountersTableOrderingComposer
    extends Composer<_$AppDatabase, $CountersTable> {
  $$CountersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CountersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CountersTable> {
  $$CountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$CountersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CountersTable,
          Counter,
          $$CountersTableFilterComposer,
          $$CountersTableOrderingComposer,
          $$CountersTableAnnotationComposer,
          $$CountersTableCreateCompanionBuilder,
          $$CountersTableUpdateCompanionBuilder,
          (Counter, BaseReferences<_$AppDatabase, $CountersTable, Counter>),
          Counter,
          PrefetchHooks Function()
        > {
  $$CountersTableTableManager(_$AppDatabase db, $CountersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<int> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CountersCompanion(name: name, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String name,
                required int value,
                Value<int> rowid = const Value.absent(),
              }) => CountersCompanion.insert(
                name: name,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CountersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CountersTable,
      Counter,
      $$CountersTableFilterComposer,
      $$CountersTableOrderingComposer,
      $$CountersTableAnnotationComposer,
      $$CountersTableCreateCompanionBuilder,
      $$CountersTableUpdateCompanionBuilder,
      (Counter, BaseReferences<_$AppDatabase, $CountersTable, Counter>),
      Counter,
      PrefetchHooks Function()
    >;
typedef $$HistoryEntriesTableCreateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<int> rowSeq,
      required int alarmId,
      required DateTime at,
      required int pushSeq,
      required String courtId,
      required CheckOutcome outcome,
      required HistoryKind kind,
      Value<DateTime?> checkedAt,
      Value<DateTime?> watchedUntil,
      Value<DateTime?> checkingEndedAt,
      Value<double?> courtSpeedKmh,
      Value<double?> rawGustKmh,
      Value<int?> courtSpeedLimitKmh,
      Value<double?> rawGustLimitKmh,
      Value<double?> volume,
      Value<RingDisposition?> ringDisposition,
      Value<String?> hostEventKey,
    });
typedef $$HistoryEntriesTableUpdateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<int> rowSeq,
      Value<int> alarmId,
      Value<DateTime> at,
      Value<int> pushSeq,
      Value<String> courtId,
      Value<CheckOutcome> outcome,
      Value<HistoryKind> kind,
      Value<DateTime?> checkedAt,
      Value<DateTime?> watchedUntil,
      Value<DateTime?> checkingEndedAt,
      Value<double?> courtSpeedKmh,
      Value<double?> rawGustKmh,
      Value<int?> courtSpeedLimitKmh,
      Value<double?> rawGustLimitKmh,
      Value<double?> volume,
      Value<RingDisposition?> ringDisposition,
      Value<String?> hostEventKey,
    });

class $$HistoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowSeq => $composableBuilder(
    column: $table.rowSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get at =>
      $composableBuilder(
        column: $table.at,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get pushSeq => $composableBuilder(
    column: $table.pushSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get courtId => $composableBuilder(
    column: $table.courtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CheckOutcome, CheckOutcome, String>
  get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<HistoryKind, HistoryKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get checkedAt =>
      $composableBuilder(
        column: $table.checkedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get watchedUntil =>
      $composableBuilder(
        column: $table.watchedUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get checkingEndedAt => $composableBuilder(
    column: $table.checkingEndedAt,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<double> get courtSpeedKmh => $composableBuilder(
    column: $table.courtSpeedKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rawGustKmh => $composableBuilder(
    column: $table.rawGustKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rawGustLimitKmh => $composableBuilder(
    column: $table.rawGustLimitKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RingDisposition?, RingDisposition, String>
  get ringDisposition => $composableBuilder(
    column: $table.ringDisposition,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get hostEventKey => $composableBuilder(
    column: $table.hostEventKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowSeq => $composableBuilder(
    column: $table.rowSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pushSeq => $composableBuilder(
    column: $table.pushSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courtId => $composableBuilder(
    column: $table.courtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchedUntil => $composableBuilder(
    column: $table.watchedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get checkingEndedAt => $composableBuilder(
    column: $table.checkingEndedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get courtSpeedKmh => $composableBuilder(
    column: $table.courtSpeedKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rawGustKmh => $composableBuilder(
    column: $table.rawGustKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rawGustLimitKmh => $composableBuilder(
    column: $table.rawGustLimitKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ringDisposition => $composableBuilder(
    column: $table.ringDisposition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostEventKey => $composableBuilder(
    column: $table.hostEventKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowSeq =>
      $composableBuilder(column: $table.rowSeq, builder: (column) => column);

  GeneratedColumn<int> get alarmId =>
      $composableBuilder(column: $table.alarmId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<int> get pushSeq =>
      $composableBuilder(column: $table.pushSeq, builder: (column) => column);

  GeneratedColumn<String> get courtId =>
      $composableBuilder(column: $table.courtId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CheckOutcome, String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumnWithTypeConverter<HistoryKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get watchedUntil =>
      $composableBuilder(
        column: $table.watchedUntil,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get checkingEndedAt =>
      $composableBuilder(
        column: $table.checkingEndedAt,
        builder: (column) => column,
      );

  GeneratedColumn<double> get courtSpeedKmh => $composableBuilder(
    column: $table.courtSpeedKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rawGustKmh => $composableBuilder(
    column: $table.rawGustKmh,
    builder: (column) => column,
  );

  GeneratedColumn<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rawGustLimitKmh => $composableBuilder(
    column: $table.rawGustLimitKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RingDisposition?, String>
  get ringDisposition => $composableBuilder(
    column: $table.ringDisposition,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostEventKey => $composableBuilder(
    column: $table.hostEventKey,
    builder: (column) => column,
  );
}

class $$HistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HistoryEntriesTable,
          HistoryEntry,
          $$HistoryEntriesTableFilterComposer,
          $$HistoryEntriesTableOrderingComposer,
          $$HistoryEntriesTableAnnotationComposer,
          $$HistoryEntriesTableCreateCompanionBuilder,
          $$HistoryEntriesTableUpdateCompanionBuilder,
          (
            HistoryEntry,
            BaseReferences<_$AppDatabase, $HistoryEntriesTable, HistoryEntry>,
          ),
          HistoryEntry,
          PrefetchHooks Function()
        > {
  $$HistoryEntriesTableTableManager(
    _$AppDatabase db,
    $HistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rowSeq = const Value.absent(),
                Value<int> alarmId = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<int> pushSeq = const Value.absent(),
                Value<String> courtId = const Value.absent(),
                Value<CheckOutcome> outcome = const Value.absent(),
                Value<HistoryKind> kind = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<DateTime?> watchedUntil = const Value.absent(),
                Value<DateTime?> checkingEndedAt = const Value.absent(),
                Value<double?> courtSpeedKmh = const Value.absent(),
                Value<double?> rawGustKmh = const Value.absent(),
                Value<int?> courtSpeedLimitKmh = const Value.absent(),
                Value<double?> rawGustLimitKmh = const Value.absent(),
                Value<double?> volume = const Value.absent(),
                Value<RingDisposition?> ringDisposition = const Value.absent(),
                Value<String?> hostEventKey = const Value.absent(),
              }) => HistoryEntriesCompanion(
                rowSeq: rowSeq,
                alarmId: alarmId,
                at: at,
                pushSeq: pushSeq,
                courtId: courtId,
                outcome: outcome,
                kind: kind,
                checkedAt: checkedAt,
                watchedUntil: watchedUntil,
                checkingEndedAt: checkingEndedAt,
                courtSpeedKmh: courtSpeedKmh,
                rawGustKmh: rawGustKmh,
                courtSpeedLimitKmh: courtSpeedLimitKmh,
                rawGustLimitKmh: rawGustLimitKmh,
                volume: volume,
                ringDisposition: ringDisposition,
                hostEventKey: hostEventKey,
              ),
          createCompanionCallback:
              ({
                Value<int> rowSeq = const Value.absent(),
                required int alarmId,
                required DateTime at,
                required int pushSeq,
                required String courtId,
                required CheckOutcome outcome,
                required HistoryKind kind,
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<DateTime?> watchedUntil = const Value.absent(),
                Value<DateTime?> checkingEndedAt = const Value.absent(),
                Value<double?> courtSpeedKmh = const Value.absent(),
                Value<double?> rawGustKmh = const Value.absent(),
                Value<int?> courtSpeedLimitKmh = const Value.absent(),
                Value<double?> rawGustLimitKmh = const Value.absent(),
                Value<double?> volume = const Value.absent(),
                Value<RingDisposition?> ringDisposition = const Value.absent(),
                Value<String?> hostEventKey = const Value.absent(),
              }) => HistoryEntriesCompanion.insert(
                rowSeq: rowSeq,
                alarmId: alarmId,
                at: at,
                pushSeq: pushSeq,
                courtId: courtId,
                outcome: outcome,
                kind: kind,
                checkedAt: checkedAt,
                watchedUntil: watchedUntil,
                checkingEndedAt: checkingEndedAt,
                courtSpeedKmh: courtSpeedKmh,
                rawGustKmh: rawGustKmh,
                courtSpeedLimitKmh: courtSpeedLimitKmh,
                rawGustLimitKmh: rawGustLimitKmh,
                volume: volume,
                ringDisposition: ringDisposition,
                hostEventKey: hostEventKey,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HistoryEntriesTable,
      HistoryEntry,
      $$HistoryEntriesTableFilterComposer,
      $$HistoryEntriesTableOrderingComposer,
      $$HistoryEntriesTableAnnotationComposer,
      $$HistoryEntriesTableCreateCompanionBuilder,
      $$HistoryEntriesTableUpdateCompanionBuilder,
      (
        HistoryEntry,
        BaseReferences<_$AppDatabase, $HistoryEntriesTable, HistoryEntry>,
      ),
      HistoryEntry,
      PrefetchHooks Function()
    >;
typedef $$CheckStatesTableCreateCompanionBuilder =
    CheckStatesCompanion Function({
      Value<int> alarmId,
      required DateTime alarmAt,
      required bool ringScheduled,
      Value<double?> ringCourtSpeedKmh,
      Value<double?> ringRawGustKmh,
      Value<double?> ringVolume,
      required bool cardShown,
      Value<double?> skipCourtSpeedKmh,
      Value<double?> skipRawGustKmh,
      required bool skipGusty,
      Value<DateTime?> lastCheckAt,
      Value<DateTime?> lastAttemptAt,
      required int pushSeq,
    });
typedef $$CheckStatesTableUpdateCompanionBuilder =
    CheckStatesCompanion Function({
      Value<int> alarmId,
      Value<DateTime> alarmAt,
      Value<bool> ringScheduled,
      Value<double?> ringCourtSpeedKmh,
      Value<double?> ringRawGustKmh,
      Value<double?> ringVolume,
      Value<bool> cardShown,
      Value<double?> skipCourtSpeedKmh,
      Value<double?> skipRawGustKmh,
      Value<bool> skipGusty,
      Value<DateTime?> lastCheckAt,
      Value<DateTime?> lastAttemptAt,
      Value<int> pushSeq,
    });

class $$CheckStatesTableFilterComposer
    extends Composer<_$AppDatabase, $CheckStatesTable> {
  $$CheckStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get alarmAt =>
      $composableBuilder(
        column: $table.alarmAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get ringScheduled => $composableBuilder(
    column: $table.ringScheduled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ringCourtSpeedKmh => $composableBuilder(
    column: $table.ringCourtSpeedKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ringRawGustKmh => $composableBuilder(
    column: $table.ringRawGustKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ringVolume => $composableBuilder(
    column: $table.ringVolume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cardShown => $composableBuilder(
    column: $table.cardShown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get skipCourtSpeedKmh => $composableBuilder(
    column: $table.skipCourtSpeedKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get skipRawGustKmh => $composableBuilder(
    column: $table.skipRawGustKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get skipGusty => $composableBuilder(
    column: $table.skipGusty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastCheckAt =>
      $composableBuilder(
        column: $table.lastCheckAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastAttemptAt =>
      $composableBuilder(
        column: $table.lastAttemptAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get pushSeq => $composableBuilder(
    column: $table.pushSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CheckStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $CheckStatesTable> {
  $$CheckStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alarmAt => $composableBuilder(
    column: $table.alarmAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get ringScheduled => $composableBuilder(
    column: $table.ringScheduled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ringCourtSpeedKmh => $composableBuilder(
    column: $table.ringCourtSpeedKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ringRawGustKmh => $composableBuilder(
    column: $table.ringRawGustKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ringVolume => $composableBuilder(
    column: $table.ringVolume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cardShown => $composableBuilder(
    column: $table.cardShown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get skipCourtSpeedKmh => $composableBuilder(
    column: $table.skipCourtSpeedKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get skipRawGustKmh => $composableBuilder(
    column: $table.skipRawGustKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get skipGusty => $composableBuilder(
    column: $table.skipGusty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pushSeq => $composableBuilder(
    column: $table.pushSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CheckStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CheckStatesTable> {
  $$CheckStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get alarmId =>
      $composableBuilder(column: $table.alarmId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get alarmAt =>
      $composableBuilder(column: $table.alarmAt, builder: (column) => column);

  GeneratedColumn<bool> get ringScheduled => $composableBuilder(
    column: $table.ringScheduled,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ringCourtSpeedKmh => $composableBuilder(
    column: $table.ringCourtSpeedKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ringRawGustKmh => $composableBuilder(
    column: $table.ringRawGustKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ringVolume => $composableBuilder(
    column: $table.ringVolume,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cardShown =>
      $composableBuilder(column: $table.cardShown, builder: (column) => column);

  GeneratedColumn<double> get skipCourtSpeedKmh => $composableBuilder(
    column: $table.skipCourtSpeedKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get skipRawGustKmh => $composableBuilder(
    column: $table.skipRawGustKmh,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get skipGusty =>
      $composableBuilder(column: $table.skipGusty, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastCheckAt =>
      $composableBuilder(
        column: $table.lastCheckAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastAttemptAt =>
      $composableBuilder(
        column: $table.lastAttemptAt,
        builder: (column) => column,
      );

  GeneratedColumn<int> get pushSeq =>
      $composableBuilder(column: $table.pushSeq, builder: (column) => column);
}

class $$CheckStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CheckStatesTable,
          CheckStateRow,
          $$CheckStatesTableFilterComposer,
          $$CheckStatesTableOrderingComposer,
          $$CheckStatesTableAnnotationComposer,
          $$CheckStatesTableCreateCompanionBuilder,
          $$CheckStatesTableUpdateCompanionBuilder,
          (
            CheckStateRow,
            BaseReferences<_$AppDatabase, $CheckStatesTable, CheckStateRow>,
          ),
          CheckStateRow,
          PrefetchHooks Function()
        > {
  $$CheckStatesTableTableManager(_$AppDatabase db, $CheckStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CheckStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CheckStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CheckStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> alarmId = const Value.absent(),
                Value<DateTime> alarmAt = const Value.absent(),
                Value<bool> ringScheduled = const Value.absent(),
                Value<double?> ringCourtSpeedKmh = const Value.absent(),
                Value<double?> ringRawGustKmh = const Value.absent(),
                Value<double?> ringVolume = const Value.absent(),
                Value<bool> cardShown = const Value.absent(),
                Value<double?> skipCourtSpeedKmh = const Value.absent(),
                Value<double?> skipRawGustKmh = const Value.absent(),
                Value<bool> skipGusty = const Value.absent(),
                Value<DateTime?> lastCheckAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<int> pushSeq = const Value.absent(),
              }) => CheckStatesCompanion(
                alarmId: alarmId,
                alarmAt: alarmAt,
                ringScheduled: ringScheduled,
                ringCourtSpeedKmh: ringCourtSpeedKmh,
                ringRawGustKmh: ringRawGustKmh,
                ringVolume: ringVolume,
                cardShown: cardShown,
                skipCourtSpeedKmh: skipCourtSpeedKmh,
                skipRawGustKmh: skipRawGustKmh,
                skipGusty: skipGusty,
                lastCheckAt: lastCheckAt,
                lastAttemptAt: lastAttemptAt,
                pushSeq: pushSeq,
              ),
          createCompanionCallback:
              ({
                Value<int> alarmId = const Value.absent(),
                required DateTime alarmAt,
                required bool ringScheduled,
                Value<double?> ringCourtSpeedKmh = const Value.absent(),
                Value<double?> ringRawGustKmh = const Value.absent(),
                Value<double?> ringVolume = const Value.absent(),
                required bool cardShown,
                Value<double?> skipCourtSpeedKmh = const Value.absent(),
                Value<double?> skipRawGustKmh = const Value.absent(),
                required bool skipGusty,
                Value<DateTime?> lastCheckAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                required int pushSeq,
              }) => CheckStatesCompanion.insert(
                alarmId: alarmId,
                alarmAt: alarmAt,
                ringScheduled: ringScheduled,
                ringCourtSpeedKmh: ringCourtSpeedKmh,
                ringRawGustKmh: ringRawGustKmh,
                ringVolume: ringVolume,
                cardShown: cardShown,
                skipCourtSpeedKmh: skipCourtSpeedKmh,
                skipRawGustKmh: skipRawGustKmh,
                skipGusty: skipGusty,
                lastCheckAt: lastCheckAt,
                lastAttemptAt: lastAttemptAt,
                pushSeq: pushSeq,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CheckStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CheckStatesTable,
      CheckStateRow,
      $$CheckStatesTableFilterComposer,
      $$CheckStatesTableOrderingComposer,
      $$CheckStatesTableAnnotationComposer,
      $$CheckStatesTableCreateCompanionBuilder,
      $$CheckStatesTableUpdateCompanionBuilder,
      (
        CheckStateRow,
        BaseReferences<_$AppDatabase, $CheckStatesTable, CheckStateRow>,
      ),
      CheckStateRow,
      PrefetchHooks Function()
    >;
typedef $$PendingRingsTableCreateCompanionBuilder =
    PendingRingsCompanion Function({
      Value<int> alarmId,
      required int pluginId,
      required RingLockerRole role,
      required DateTime occurrenceAt,
      required DateTime scheduledFor,
      required String courtId,
      Value<double?> volume,
      Value<double?> courtSpeedKmh,
      Value<double?> rawGustKmh,
      Value<int?> courtSpeedLimitKmh,
      Value<double?> rawGustLimitKmh,
      Value<DateTime?> lastCheckAt,
      required bool rollOnDone,
    });
typedef $$PendingRingsTableUpdateCompanionBuilder =
    PendingRingsCompanion Function({
      Value<int> alarmId,
      Value<int> pluginId,
      Value<RingLockerRole> role,
      Value<DateTime> occurrenceAt,
      Value<DateTime> scheduledFor,
      Value<String> courtId,
      Value<double?> volume,
      Value<double?> courtSpeedKmh,
      Value<double?> rawGustKmh,
      Value<int?> courtSpeedLimitKmh,
      Value<double?> rawGustLimitKmh,
      Value<DateTime?> lastCheckAt,
      Value<bool> rollOnDone,
    });

class $$PendingRingsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingRingsTable> {
  $$PendingRingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RingLockerRole, RingLockerRole, String>
  get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get occurrenceAt =>
      $composableBuilder(
        column: $table.occurrenceAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get scheduledFor =>
      $composableBuilder(
        column: $table.scheduledFor,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get courtId => $composableBuilder(
    column: $table.courtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get courtSpeedKmh => $composableBuilder(
    column: $table.courtSpeedKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rawGustKmh => $composableBuilder(
    column: $table.rawGustKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rawGustLimitKmh => $composableBuilder(
    column: $table.rawGustLimitKmh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastCheckAt =>
      $composableBuilder(
        column: $table.lastCheckAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get rollOnDone => $composableBuilder(
    column: $table.rollOnDone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingRingsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingRingsTable> {
  $$PendingRingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurrenceAt => $composableBuilder(
    column: $table.occurrenceAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courtId => $composableBuilder(
    column: $table.courtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get courtSpeedKmh => $composableBuilder(
    column: $table.courtSpeedKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rawGustKmh => $composableBuilder(
    column: $table.rawGustKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rawGustLimitKmh => $composableBuilder(
    column: $table.rawGustLimitKmh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get rollOnDone => $composableBuilder(
    column: $table.rollOnDone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingRingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingRingsTable> {
  $$PendingRingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get alarmId =>
      $composableBuilder(column: $table.alarmId, builder: (column) => column);

  GeneratedColumn<int> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RingLockerRole, String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get occurrenceAt =>
      $composableBuilder(
        column: $table.occurrenceAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get scheduledFor =>
      $composableBuilder(
        column: $table.scheduledFor,
        builder: (column) => column,
      );

  GeneratedColumn<String> get courtId =>
      $composableBuilder(column: $table.courtId, builder: (column) => column);

  GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumn<double> get courtSpeedKmh => $composableBuilder(
    column: $table.courtSpeedKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rawGustKmh => $composableBuilder(
    column: $table.rawGustKmh,
    builder: (column) => column,
  );

  GeneratedColumn<int> get courtSpeedLimitKmh => $composableBuilder(
    column: $table.courtSpeedLimitKmh,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rawGustLimitKmh => $composableBuilder(
    column: $table.rawGustLimitKmh,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastCheckAt =>
      $composableBuilder(
        column: $table.lastCheckAt,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get rollOnDone => $composableBuilder(
    column: $table.rollOnDone,
    builder: (column) => column,
  );
}

class $$PendingRingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingRingsTable,
          PendingRingRow,
          $$PendingRingsTableFilterComposer,
          $$PendingRingsTableOrderingComposer,
          $$PendingRingsTableAnnotationComposer,
          $$PendingRingsTableCreateCompanionBuilder,
          $$PendingRingsTableUpdateCompanionBuilder,
          (
            PendingRingRow,
            BaseReferences<_$AppDatabase, $PendingRingsTable, PendingRingRow>,
          ),
          PendingRingRow,
          PrefetchHooks Function()
        > {
  $$PendingRingsTableTableManager(_$AppDatabase db, $PendingRingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingRingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingRingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingRingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> alarmId = const Value.absent(),
                Value<int> pluginId = const Value.absent(),
                Value<RingLockerRole> role = const Value.absent(),
                Value<DateTime> occurrenceAt = const Value.absent(),
                Value<DateTime> scheduledFor = const Value.absent(),
                Value<String> courtId = const Value.absent(),
                Value<double?> volume = const Value.absent(),
                Value<double?> courtSpeedKmh = const Value.absent(),
                Value<double?> rawGustKmh = const Value.absent(),
                Value<int?> courtSpeedLimitKmh = const Value.absent(),
                Value<double?> rawGustLimitKmh = const Value.absent(),
                Value<DateTime?> lastCheckAt = const Value.absent(),
                Value<bool> rollOnDone = const Value.absent(),
              }) => PendingRingsCompanion(
                alarmId: alarmId,
                pluginId: pluginId,
                role: role,
                occurrenceAt: occurrenceAt,
                scheduledFor: scheduledFor,
                courtId: courtId,
                volume: volume,
                courtSpeedKmh: courtSpeedKmh,
                rawGustKmh: rawGustKmh,
                courtSpeedLimitKmh: courtSpeedLimitKmh,
                rawGustLimitKmh: rawGustLimitKmh,
                lastCheckAt: lastCheckAt,
                rollOnDone: rollOnDone,
              ),
          createCompanionCallback:
              ({
                Value<int> alarmId = const Value.absent(),
                required int pluginId,
                required RingLockerRole role,
                required DateTime occurrenceAt,
                required DateTime scheduledFor,
                required String courtId,
                Value<double?> volume = const Value.absent(),
                Value<double?> courtSpeedKmh = const Value.absent(),
                Value<double?> rawGustKmh = const Value.absent(),
                Value<int?> courtSpeedLimitKmh = const Value.absent(),
                Value<double?> rawGustLimitKmh = const Value.absent(),
                Value<DateTime?> lastCheckAt = const Value.absent(),
                required bool rollOnDone,
              }) => PendingRingsCompanion.insert(
                alarmId: alarmId,
                pluginId: pluginId,
                role: role,
                occurrenceAt: occurrenceAt,
                scheduledFor: scheduledFor,
                courtId: courtId,
                volume: volume,
                courtSpeedKmh: courtSpeedKmh,
                rawGustKmh: rawGustKmh,
                courtSpeedLimitKmh: courtSpeedLimitKmh,
                rawGustLimitKmh: rawGustLimitKmh,
                lastCheckAt: lastCheckAt,
                rollOnDone: rollOnDone,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingRingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingRingsTable,
      PendingRingRow,
      $$PendingRingsTableFilterComposer,
      $$PendingRingsTableOrderingComposer,
      $$PendingRingsTableAnnotationComposer,
      $$PendingRingsTableCreateCompanionBuilder,
      $$PendingRingsTableUpdateCompanionBuilder,
      (
        PendingRingRow,
        BaseReferences<_$AppDatabase, $PendingRingsTable, PendingRingRow>,
      ),
      PendingRingRow,
      PrefetchHooks Function()
    >;
typedef $$HostEventClaimsTableCreateCompanionBuilder =
    HostEventClaimsCompanion Function({
      required String claimKey,
      required HostEventClaimState state,
      Value<int> attempts,
      Value<DateTime?> leasedUntil,
      required DateTime recordedAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$HostEventClaimsTableUpdateCompanionBuilder =
    HostEventClaimsCompanion Function({
      Value<String> claimKey,
      Value<HostEventClaimState> state,
      Value<int> attempts,
      Value<DateTime?> leasedUntil,
      Value<DateTime> recordedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$HostEventClaimsTableFilterComposer
    extends Composer<_$AppDatabase, $HostEventClaimsTable> {
  $$HostEventClaimsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get claimKey => $composableBuilder(
    column: $table.claimKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    HostEventClaimState,
    HostEventClaimState,
    String
  >
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get leasedUntil =>
      $composableBuilder(
        column: $table.leasedUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get recordedAt =>
      $composableBuilder(
        column: $table.recordedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$HostEventClaimsTableOrderingComposer
    extends Composer<_$AppDatabase, $HostEventClaimsTable> {
  $$HostEventClaimsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get claimKey => $composableBuilder(
    column: $table.claimKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leasedUntil => $composableBuilder(
    column: $table.leasedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostEventClaimsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostEventClaimsTable> {
  $$HostEventClaimsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get claimKey =>
      $composableBuilder(column: $table.claimKey, builder: (column) => column);

  GeneratedColumnWithTypeConverter<HostEventClaimState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get leasedUntil =>
      $composableBuilder(
        column: $table.leasedUntil,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get recordedAt =>
      $composableBuilder(
        column: $table.recordedAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$HostEventClaimsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostEventClaimsTable,
          HostEventClaim,
          $$HostEventClaimsTableFilterComposer,
          $$HostEventClaimsTableOrderingComposer,
          $$HostEventClaimsTableAnnotationComposer,
          $$HostEventClaimsTableCreateCompanionBuilder,
          $$HostEventClaimsTableUpdateCompanionBuilder,
          (
            HostEventClaim,
            BaseReferences<
              _$AppDatabase,
              $HostEventClaimsTable,
              HostEventClaim
            >,
          ),
          HostEventClaim,
          PrefetchHooks Function()
        > {
  $$HostEventClaimsTableTableManager(
    _$AppDatabase db,
    $HostEventClaimsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostEventClaimsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostEventClaimsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostEventClaimsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> claimKey = const Value.absent(),
                Value<HostEventClaimState> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> leasedUntil = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostEventClaimsCompanion(
                claimKey: claimKey,
                state: state,
                attempts: attempts,
                leasedUntil: leasedUntil,
                recordedAt: recordedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String claimKey,
                required HostEventClaimState state,
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> leasedUntil = const Value.absent(),
                required DateTime recordedAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => HostEventClaimsCompanion.insert(
                claimKey: claimKey,
                state: state,
                attempts: attempts,
                leasedUntil: leasedUntil,
                recordedAt: recordedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostEventClaimsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostEventClaimsTable,
      HostEventClaim,
      $$HostEventClaimsTableFilterComposer,
      $$HostEventClaimsTableOrderingComposer,
      $$HostEventClaimsTableAnnotationComposer,
      $$HostEventClaimsTableCreateCompanionBuilder,
      $$HostEventClaimsTableUpdateCompanionBuilder,
      (
        HostEventClaim,
        BaseReferences<_$AppDatabase, $HostEventClaimsTable, HostEventClaim>,
      ),
      HostEventClaim,
      PrefetchHooks Function()
    >;
typedef $$AlarmKitHandlesTableCreateCompanionBuilder =
    AlarmKitHandlesCompanion Function({
      required int alarmId,
      required String uuid,
      required int seq,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$AlarmKitHandlesTableUpdateCompanionBuilder =
    AlarmKitHandlesCompanion Function({
      Value<int> alarmId,
      Value<String> uuid,
      Value<int> seq,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$AlarmKitHandlesTableFilterComposer
    extends Composer<_$AppDatabase, $AlarmKitHandlesTable> {
  $$AlarmKitHandlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$AlarmKitHandlesTableOrderingComposer
    extends Composer<_$AppDatabase, $AlarmKitHandlesTable> {
  $$AlarmKitHandlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlarmKitHandlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlarmKitHandlesTable> {
  $$AlarmKitHandlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get alarmId =>
      $composableBuilder(column: $table.alarmId, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AlarmKitHandlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlarmKitHandlesTable,
          AlarmKitHandle,
          $$AlarmKitHandlesTableFilterComposer,
          $$AlarmKitHandlesTableOrderingComposer,
          $$AlarmKitHandlesTableAnnotationComposer,
          $$AlarmKitHandlesTableCreateCompanionBuilder,
          $$AlarmKitHandlesTableUpdateCompanionBuilder,
          (
            AlarmKitHandle,
            BaseReferences<
              _$AppDatabase,
              $AlarmKitHandlesTable,
              AlarmKitHandle
            >,
          ),
          AlarmKitHandle,
          PrefetchHooks Function()
        > {
  $$AlarmKitHandlesTableTableManager(
    _$AppDatabase db,
    $AlarmKitHandlesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmKitHandlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmKitHandlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmKitHandlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> alarmId = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlarmKitHandlesCompanion(
                alarmId: alarmId,
                uuid: uuid,
                seq: seq,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int alarmId,
                required String uuid,
                required int seq,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AlarmKitHandlesCompanion.insert(
                alarmId: alarmId,
                uuid: uuid,
                seq: seq,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlarmKitHandlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlarmKitHandlesTable,
      AlarmKitHandle,
      $$AlarmKitHandlesTableFilterComposer,
      $$AlarmKitHandlesTableOrderingComposer,
      $$AlarmKitHandlesTableAnnotationComposer,
      $$AlarmKitHandlesTableCreateCompanionBuilder,
      $$AlarmKitHandlesTableUpdateCompanionBuilder,
      (
        AlarmKitHandle,
        BaseReferences<_$AppDatabase, $AlarmKitHandlesTable, AlarmKitHandle>,
      ),
      AlarmKitHandle,
      PrefetchHooks Function()
    >;
typedef $$OutboxEntriesTableCreateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<int> id,
      required String kind,
      required String dedupKey,
      required String payload,
      required OutboxState state,
      Value<int> attempts,
      Value<DateTime?> leasedUntil,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> lastError,
    });
typedef $$OutboxEntriesTableUpdateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> dedupKey,
      Value<String> payload,
      Value<OutboxState> state,
      Value<int> attempts,
      Value<DateTime?> leasedUntil,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> lastError,
    });

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dedupKey => $composableBuilder(
    column: $table.dedupKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<OutboxState, OutboxState, String> get state =>
      $composableBuilder(
        column: $table.state,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get leasedUntil =>
      $composableBuilder(
        column: $table.leasedUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dedupKey => $composableBuilder(
    column: $table.dedupKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leasedUntil => $composableBuilder(
    column: $table.leasedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get dedupKey =>
      $composableBuilder(column: $table.dedupKey, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OutboxState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get leasedUntil =>
      $composableBuilder(
        column: $table.leasedUntil,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxEntriesTable,
          OutboxEntry,
          $$OutboxEntriesTableFilterComposer,
          $$OutboxEntriesTableOrderingComposer,
          $$OutboxEntriesTableAnnotationComposer,
          $$OutboxEntriesTableCreateCompanionBuilder,
          $$OutboxEntriesTableUpdateCompanionBuilder,
          (
            OutboxEntry,
            BaseReferences<_$AppDatabase, $OutboxEntriesTable, OutboxEntry>,
          ),
          OutboxEntry,
          PrefetchHooks Function()
        > {
  $$OutboxEntriesTableTableManager(_$AppDatabase db, $OutboxEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> dedupKey = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<OutboxState> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> leasedUntil = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxEntriesCompanion(
                id: id,
                kind: kind,
                dedupKey: dedupKey,
                payload: payload,
                state: state,
                attempts: attempts,
                leasedUntil: leasedUntil,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String dedupKey,
                required String payload,
                required OutboxState state,
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> leasedUntil = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> lastError = const Value.absent(),
              }) => OutboxEntriesCompanion.insert(
                id: id,
                kind: kind,
                dedupKey: dedupKey,
                payload: payload,
                state: state,
                attempts: attempts,
                leasedUntil: leasedUntil,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxEntriesTable,
      OutboxEntry,
      $$OutboxEntriesTableFilterComposer,
      $$OutboxEntriesTableOrderingComposer,
      $$OutboxEntriesTableAnnotationComposer,
      $$OutboxEntriesTableCreateCompanionBuilder,
      $$OutboxEntriesTableUpdateCompanionBuilder,
      (
        OutboxEntry,
        BaseReferences<_$AppDatabase, $OutboxEntriesTable, OutboxEntry>,
      ),
      OutboxEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CourtsTableTableManager get courts =>
      $$CourtsTableTableManager(_db, _db.courts);
  $$NivaatAlarmsTableTableManager get nivaatAlarms =>
      $$NivaatAlarmsTableTableManager(_db, _db.nivaatAlarms);
  $$CountersTableTableManager get counters =>
      $$CountersTableTableManager(_db, _db.counters);
  $$HistoryEntriesTableTableManager get historyEntries =>
      $$HistoryEntriesTableTableManager(_db, _db.historyEntries);
  $$CheckStatesTableTableManager get checkStates =>
      $$CheckStatesTableTableManager(_db, _db.checkStates);
  $$PendingRingsTableTableManager get pendingRings =>
      $$PendingRingsTableTableManager(_db, _db.pendingRings);
  $$HostEventClaimsTableTableManager get hostEventClaims =>
      $$HostEventClaimsTableTableManager(_db, _db.hostEventClaims);
  $$AlarmKitHandlesTableTableManager get alarmKitHandles =>
      $$AlarmKitHandlesTableTableManager(_db, _db.alarmKitHandles);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
}
