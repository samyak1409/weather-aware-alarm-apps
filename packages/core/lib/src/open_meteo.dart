import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'wind.dart';

/// Minimal Open-Meteo client (free, no API key) using dart:io directly so
/// core carries no HTTP dependency. Endpoints validated live on 2026-08-25.
class OpenMeteo {
  OpenMeteo({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  static const Duration _timeout = Duration(seconds: 15);

  /// The seven models averaged for every wind reading — **one per weather
  /// agency, de-duplicated** (Samyak, 2026-08-25).
  ///
  /// Open-Meteo offers far more names than distinct forecasts. Each provider
  /// ships a `_seamless` product that stitches their regional model to a global
  /// fallback, and for the European agencies **that fallback is ECMWF IFS** —
  /// so over India, where no regional model reaches, `dmi_seamless`,
  /// `knmi_seamless`, `geosphere_seamless`, `metno_seamless` and `ecmwf_ifs`
  /// are ONE forecast under five names (measured identical at five separate
  /// timestamps). Averaging the names rather than the forecasts weighted ECMWF
  /// 35% and CMA 6% — a bias nobody chose.
  ///
  /// Also excluded: `jma_*` and the two AI models, which return wind but **no
  /// gusts** at all, and gusts are half the decision.
  ///
  /// **This list is correct for India specifically.** Elsewhere the `_seamless`
  /// names would resolve to genuinely better regional models, and pinning the
  /// globals would throw that away.
  static const List<String> defaultWindModels = [
    'ecmwf_ifs',
    'ncep_gfs_global',
    'dwd_icon_global',
    'ukmo_global_deterministic_10km',
    'cmc_gem_gdps',
    'meteofrance_arpege_world',
    'cma_grapes_global',
  ];

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = _clientFactory()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(uri).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      if (res.statusCode != 200) {
        // Every refusal has a reason body, and a bad model names itself in
        // there — see [OpenMeteoUnknownModel] for why that is the only notice
        // a retirement gives us.
        final unknown = unknownModelIn(body);
        if (unknown != null) throw OpenMeteoUnknownModel(unknown);
        throw OpenMeteoException('HTTP ${res.statusCode} for $uri');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// The model name inside a 400 body, or null when the failure is something
  /// else. Public so a test can pin the shape against a recorded body.
  static String? unknownModelIn(String body) {
    final m = RegExp(r'invalid String value ([A-Za-z0-9_]+)').firstMatch(body);
    return m?.group(1);
  }

  /// The `minutely_15` grid key for [t] — **UTC, floored to the quarter hour**.
  ///
  /// UTC because we omit `timezone`, so the API's grid is UTC and we match it
  /// there. That matters more than it looks: the OLD hourly lookup floored to
  /// the UTC *hour*, and India is UTC+5:30, so a 06:00 IST alarm asked for
  /// 00:00 UTC — **05:30 IST, half an hour before the alarm**, systematically,
  /// for every Indian user. Every world offset is a whole number of quarter
  /// hours, so the 15-minute grid has no such skew anywhere.
  static String slotKey(DateTime t) {
    final u = t.toUtc();
    final f = DateTime.utc(u.year, u.month, u.day, u.hour, u.minute ~/ 15 * 15);
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(f.year, 4)}-${p(f.month)}-${p(f.day)}'
        'T${p(f.hour)}:${p(f.minute)}';
  }

  /// Every 15-minute slot from [from] to [to] inclusive, each one the **mean
  /// across the models that answered**.
  ///
  /// One request covers the whole play window: `start_minutely_15` /
  /// `end_minutely_15` take exact timestamps, so a three-slot window is three
  /// array entries and nothing more — the smallest payload and call weight the
  /// API can serve.
  ///
  /// `minutely_15` rather than `current` for two reasons. `current` cannot be
  /// split by model at all (it returns one value however many you ask for), and
  /// it describes **now**, which is never the moment the alarm is about — a
  /// check at 05:45 must read the slot for 06:30, not for 05:45.
  ///
  /// A model that does not cover the location is dropped silently by the API
  /// and simply missing here; a model name it does not RECOGNISE is a hard 400
  /// that fails the whole request, which is what [OpenMeteoUnknownModel] and
  /// the caller's prune-and-retry exist for.
  Future<List<WindSample>> windWindow(
    double lat,
    double lon,
    DateTime from,
    DateTime to, {
    List<String> models = defaultWindModels,
  }) async {
    if (models.isEmpty) throw OpenMeteoException('no wind models to ask');
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'minutely_15': 'wind_speed_10m,wind_gusts_10m',
      'models': models.join(','),
      'start_minutely_15': slotKey(from),
      'end_minutely_15': slotKey(to),
      // No timezone=auto: keep the grid in UTC and match in UTC.
    });
    return windowFrom(await _getJson(uri), models, where: '$lat,$lon');
  }

  /// The `minutely_15` block of an Open-Meteo response, as one mean sample per
  /// slot — **pure, and public so a test can name it**.
  ///
  /// It lived inside [windWindow] until 2026-08-30, which put it behind an
  /// HTTP call and so behind this repo's "plugin wrappers are not unit-tested"
  /// line. It is not a wrapper: it is the arithmetic every decision rests on,
  /// and it shipped a real bug (see the suffix note below) that no test could
  /// have caught where it was. Same lesson as the message builders extracted
  /// out of the widgets that hid them.
  ///
  /// [where] only names the location in the error, so a log line says which
  /// court went dark.
  static List<WindSample> windowFrom(
    Map<String, dynamic> json,
    List<String> models, {
    String where = '',
  }) {
    final block = json['minutely_15'] as Map<String, dynamic>;
    final times = (block['time'] as List).cast<String>();

    // Several models ANSWERING come back suffixed (`wind_speed_10m_ecmwf_ifs`);
    // exactly one answering comes back unsuffixed (`wind_speed_10m`).
    List<num?>? series(String variable, String model) {
      final suffixed = block['${variable}_$model'];
      return suffixed is List ? suffixed.cast<num?>() : null;
    }

    // Paired, not two lists kept in step by hand: a model contributes its wind
    // and its gusts or neither, and holding them together is what makes that
    // structural. Both or neither, because a model with speed and no gusts
    // cannot take part in a decision that is half gusts, and letting it into
    // the speed mean alone would silently average two different model sets.
    final answered = <(List<num?>, List<num?>)>[];
    for (final m in models) {
      final s = series('wind_speed_10m', m);
      final g = series('wind_gusts_10m', m);
      if (s != null && g != null) answered.add((s, g));
    }
    // **The suffix depends on how many models ANSWERED, not on how many we
    // asked for** (2026-08-30, measured live — caught in review by Cursor Grok
    // 4.6). Asking for `dwd_icon_d2,ecmwf_ifs` over Jaipur, where the German
    // regional model has no data, returns a bare `wind_speed_10m` for the one
    // that does. The old test was `models.length == 1`, which covered "we
    // asked for one" and not "one answered" — so a court that several of our
    // names do not cover read as no-data forever while the API was answering
    // it perfectly well. Reachable once pruning leaves two or more names and
    // only one of them has data there.
    //
    // The two shapes are taken to be mutually exclusive: the API suffixes only
    // when more than one model answers, so an unsuffixed pair IS the single
    // answering model — and which one it was does not matter to a mean of one.
    // Consequence if that ever stopped holding: a covering model hiding only in
    // the bare keys would be dropped once any suffixed series matched, since
    // this fallback runs only when none did. Left as one sentence rather than a
    // speculative branch — the API has never emitted both, and a branch nothing
    // can reach is what this repo deletes on sight.
    if (answered.isEmpty) {
      final s = block['wind_speed_10m'];
      final g = block['wind_gusts_10m'];
      if (s is List && g is List) {
        answered.add((s.cast<num?>(), g.cast<num?>()));
      }
    }
    if (answered.isEmpty) {
      throw OpenMeteoException('no wind model answered for $where');
    }

    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    final out = <WindSample>[];
    for (var i = 0; i < times.length; i++) {
      final s = <double>[];
      final g = <double>[];
      for (final (speed, gust) in answered) {
        final sv = i < speed.length ? speed[i] : null;
        final gv = i < gust.length ? gust[i] : null;
        if (sv != null && gv != null) {
          s.add(sv.toDouble());
          g.add(gv.toDouble());
        }
      }
      if (s.isEmpty) continue;
      out.add(WindSample(
        rawSpeedKmh: mean(s),
        rawGustKmh: mean(g),
        slotAt: DateTime.parse('${times[i]}Z').toLocal(),
      ));
    }
    if (out.isEmpty) throw OpenMeteoException('no wind slots for $where');
    return out;
  }

  /// City/place search for the saved-locations UI.
  Future<List<GeoPlace>> geocode(String query) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      // The API's own default. Eight was an arbitrary trim (Samyak, 2026-08-25).
      'count': '10',
      'language': 'en',
      'format': 'json',
    });
    final json = await _getJson(uri);
    final results = json['results'] as List? ?? const [];
    return results
        .cast<Map<String, dynamic>>()
        .map((r) => GeoPlace(
              name: r['name'] as String,
              region: regionLabel(r),
              lat: (r['latitude'] as num).toDouble(),
              lon: (r['longitude'] as num).toDouble(),
            ))
        .toList();
  }

  /// `{admin2}, {admin1}` — district then state (Samyak, 2026-08-25).
  ///
  /// It used to be `{admin1}, {country}`, which could not separate results at
  /// all inside one state: searching `Koramangala` returned three places all
  /// labelled `Karnataka, India`. District first fixes exactly that —
  /// `Bengaluru Urban` / `Bengaluru Rural` / `Ramanagara District`.
  ///
  /// **The country is deliberately dropped** (Samyak): you do not need it to
  /// recognise your own area. Known cost, accepted — `Jayanagar` matches in
  /// both India and Nepal, and the two now read `Bengaluru Urban, Karnataka`
  /// and `Chitwan, Bagmati Province` with nothing naming the country.
  ///
  /// `admin2` is skipped when it merely repeats the place name (Tonk's district
  /// is also called Tonk), and empties are dropped rather than leaving a
  /// dangling comma.
  static String regionLabel(Map<String, dynamic> r) {
    final name = r['name'] as String?;
    final admin2 = r['admin2'] as String?;
    final admin1 = r['admin1'] as String?;
    return [
      if (admin2 != null && admin2.isNotEmpty && admin2 != name) admin2,
      if (admin1 != null && admin1.isNotEmpty) admin1,
    ].join(', ');
  }
}

class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.region,
    required this.lat,
    required this.lon,
    this.source = PlaceSource.search,
  });

  final String name;

  /// The geocoder's own sub-line (`Bengaluru Urban, Karnataka`). For a GPS pick
  /// this is the coordinates instead — a stand-in the picker never renders, and
  /// one [source] tells a caller not to quote (see [savedLocationDetail]).
  final String region;

  /// Which half of the picker produced this place (X5). Defaults to the
  /// geocoder, which is what every result parsed here is.
  final PlaceSource source;

  final double lat;
  final double lon;

  /// The place as the apps store it — **one conversion, three call sites**
  /// (Arunoday's home and settings both add a location; Nivaat adds a court).
  /// Each carried its own copy of these four fields, and the ⓘ's provenance
  /// would have made that three copies of a rule instead: a GPS pick keeps no
  /// [region], because the string there is a coordinate stand-in rather than a
  /// place the geocoder named.
  ///
  /// The id is minted here for the same reason — it was the same expression in
  /// all three.
  SavedLocation toSavedLocation() => SavedLocation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        lat: lat,
        lon: lon,
        source: source,
        region: source == PlaceSource.gps ? null : region,
      );
}

class OpenMeteoException implements Exception {
  OpenMeteoException(this.message);
  final String message;
  @override
  String toString() => 'OpenMeteoException: $message';
}

/// Open-Meteo rejected a model NAME outright (HTTP 400), which fails the whole
/// request — every court, every alarm — rather than dropping that one model.
///
/// The caller prunes [model] from the stored list, saves, and retries. **This
/// is the only signal we get** that a hard-coded name has been retired
/// upstream: there is no endpoint that lists models (`/v1/models` is a 404),
/// so the refusal body — `{"error":true,"reason":"..."}`, with the bad name
/// inside it — is the whole recovery path.
///
/// [OpenMeteo._getJson] throws it, `WindModels` stores the list it prunes from,
/// and `NivaatEngine._windowFor` does the pruning — all three point here rather
/// than restating the rule.
class OpenMeteoUnknownModel implements Exception {
  OpenMeteoUnknownModel(this.model);
  final String model;
  @override
  String toString() => 'OpenMeteoUnknownModel: $model';
}
