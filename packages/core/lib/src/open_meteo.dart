import 'dart:convert';
import 'dart:io';

import 'wind.dart';

/// Minimal Open-Meteo client (free, no API key) using dart:io directly so
/// core carries no HTTP dependency. Endpoints validated live on 2026-07-11.
class OpenMeteo {
  OpenMeteo({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = _clientFactory()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(uri).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw OpenMeteoException('HTTP ${res.statusCode} for $uri');
      }
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Forecast 10 m wind for the hour containing [target] (device-local time).
  Future<WindSample> forecastWindAt(
    double lat,
    double lon,
    DateTime target,
  ) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'hourly': 'wind_speed_10m,wind_gusts_10m',
      'forecast_days': '3',
      'timezone': 'auto',
    });
    final json = await _getJson(uri);
    final hourly = json['hourly'] as Map<String, dynamic>;
    final times = (hourly['time'] as List).cast<String>();
    final speeds = (hourly['wind_speed_10m'] as List);
    final gusts = (hourly['wind_gusts_10m'] as List);

    final key = '${target.year.toString().padLeft(4, '0')}-'
        '${target.month.toString().padLeft(2, '0')}-'
        '${target.day.toString().padLeft(2, '0')}T'
        '${target.hour.toString().padLeft(2, '0')}:00';
    final i = times.indexOf(key);
    if (i < 0 || speeds[i] == null || gusts[i] == null) {
      throw OpenMeteoException('no forecast for $key');
    }
    return WindSample(
      rawSpeedKmh: (speeds[i] as num).toDouble(),
      rawGustKmh: (gusts[i] as num).toDouble(),
      observedAt: target,
      isForecast: true,
    );
  }

  /// Current observed 10 m wind at the location.
  Future<WindSample> currentWind(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'wind_speed_10m,wind_gusts_10m',
      'timezone': 'auto',
    });
    final json = await _getJson(uri);
    final current = json['current'] as Map<String, dynamic>;
    final speed = current['wind_speed_10m'];
    final gust = current['wind_gusts_10m'];
    if (speed == null || gust == null) {
      throw OpenMeteoException('no current wind in response');
    }
    return WindSample(
      rawSpeedKmh: (speed as num).toDouble(),
      rawGustKmh: (gust as num).toDouble(),
      observedAt: DateTime.now(),
      isForecast: false,
    );
  }

  /// City/place search for the saved-locations UI.
  Future<List<GeoPlace>> geocode(String query) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '8',
      'language': 'en',
      'format': 'json',
    });
    final json = await _getJson(uri);
    final results = json['results'] as List? ?? const [];
    return results
        .cast<Map<String, dynamic>>()
        .map((r) => GeoPlace(
              name: r['name'] as String,
              region: [r['admin1'], r['country']]
                  .whereType<String>()
                  .join(', '),
              lat: (r['latitude'] as num).toDouble(),
              lon: (r['longitude'] as num).toDouble(),
            ))
        .toList();
  }
}

class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.region,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String region;
  final double lat;
  final double lon;
}

class OpenMeteoException implements Exception {
  OpenMeteoException(this.message);
  final String message;
  @override
  String toString() => 'OpenMeteoException: $message';
}
