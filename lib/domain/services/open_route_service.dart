import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/charging_models.dart';

class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    required this.isRoadRoute,
    this.elevationGainM,
    this.usesTraffic = false,
    this.isGeographicallyUnreachable = false,
    this.unavailableMessage,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
  final bool isRoadRoute;
  final double? elevationGainM;
  final bool usesTraffic;
  final bool isGeographicallyUnreachable;
  final String? unavailableMessage;
}

class OpenRouteService {
  const OpenRouteService._();

  static const _primaryEndpoint = 'https://router.project-osrm.org';
  static const _fallbackEndpoint =
      'https://routing.openstreetmap.de/routed-car';
  static final Map<String, _CachedRoadRoute> _routeCache = {};
  static final Map<String, Future<RoadRoute>> _inFlightRoutes = {};

  static Future<RoadRoute> drivingRoute({
    required GeoLocation origin,
    required GeoLocation destination,
    bool includeElevation = false,
  }) async {
    final cacheKey = _cacheKey(origin, destination);
    final cached = _routeCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.route;
    }
    if (cached != null) _routeCache.remove(cacheKey);
    final inFlight = _inFlightRoutes[cacheKey];
    if (inFlight != null) return inFlight;
    final request = _loadRoute(origin: origin, destination: destination);
    _inFlightRoutes[cacheKey] = request;
    try {
      final route = await request;
      if (route.isRoadRoute || route.isGeographicallyUnreachable) {
        _rememberRoute(cacheKey, route);
      }
      return route;
    } finally {
      if (identical(_inFlightRoutes[cacheKey], request)) {
        _inFlightRoutes.remove(cacheKey);
      }
    }
  }

  static Future<RoadRoute> _loadRoute({
    required GeoLocation origin,
    required GeoLocation destination,
  }) async {
    if (_requiresSeaCrossing(origin, destination)) {
      final distanceKm = _straightLineKm(origin, destination);
      return RoadRoute(
        points: const [],
        distanceKm: distanceKm,
        durationMinutes: 0,
        isRoadRoute: false,
        isGeographicallyUnreachable: true,
        unavailableMessage:
            'This destination cannot be reached entirely by road. Sea or air travel is required.',
      );
    }
    final primary = await _osrmRoute(
      endpoint: _primaryEndpoint,
      origin: origin,
      destination: destination,
      timeout: const Duration(seconds: 3),
    );
    if (primary != null) return primary;
    final fallback = await _osrmRoute(
      endpoint: _fallbackEndpoint,
      origin: origin,
      destination: destination,
      timeout: const Duration(seconds: 5),
    );
    if (fallback != null) return fallback;
    return RoadRoute(
      points: [
        LatLng(origin.latitude, origin.longitude),
        LatLng(destination.latitude, destination.longitude),
      ],
      distanceKm: _straightLineKm(origin, destination),
      durationMinutes: (_straightLineKm(origin, destination) / 40).ceil(),
      isRoadRoute: false,
      unavailableMessage:
          'We could not load a road route right now. Check your internet connection and retry.',
    );
  }

  static String _cacheKey(GeoLocation origin, GeoLocation destination) => [
    origin.latitude.toStringAsFixed(4),
    origin.longitude.toStringAsFixed(4),
    destination.latitude.toStringAsFixed(4),
    destination.longitude.toStringAsFixed(4),
  ].join(':');

  static void _rememberRoute(String key, RoadRoute route) {
    if (_routeCache.length >= 80) {
      _routeCache.remove(_routeCache.keys.first);
    }
    _routeCache[key] = _CachedRoadRoute(
      route,
      DateTime.now().add(
        route.isGeographicallyUnreachable
            ? const Duration(hours: 1)
            : const Duration(minutes: 15),
      ),
    );
  }

  static double _straightLineKm(GeoLocation first, GeoLocation second) {
    const earthRadiusKm = 6371.0;
    final lat1 = first.latitude * 3.141592653589793 / 180;
    final lat2 = second.latitude * 3.141592653589793 / 180;
    final dLat = (second.latitude - first.latitude) * 3.141592653589793 / 180;
    final dLon = (second.longitude - first.longitude) * 3.141592653589793 / 180;
    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static bool _requiresSeaCrossing(
    GeoLocation origin,
    GeoLocation destination,
  ) {
    bool isPeninsular(GeoLocation point) =>
        point.latitude >= 0.8 &&
        point.latitude <= 7.6 &&
        point.longitude >= 99.0 &&
        point.longitude <= 105.8;
    bool isBorneo(GeoLocation point) =>
        point.latitude >= -0.2 &&
        point.latitude <= 8.2 &&
        point.longitude >= 108.0 &&
        point.longitude <= 120.0;
    return (isPeninsular(origin) && isBorneo(destination)) ||
        (isBorneo(origin) && isPeninsular(destination));
  }

  static Future<RoadRoute?> _osrmRoute({
    required String endpoint,
    required GeoLocation origin,
    required GeoLocation destination,
    required Duration timeout,
  }) async {
    final uri = Uri.parse(
      '$endpoint/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final response = await http
          .get(uri, headers: const {'User-Agent': 'ChargeMY/1.0 mobile app'})
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? const [];
      final points =
          coordinates
              .whereType<List<dynamic>>()
              .where((point) => point.length >= 2)
              .map(
                (point) => LatLng(
                  (point[1] as num).toDouble(),
                  (point[0] as num).toDouble(),
                ),
              )
              .toList();
      if (points.length < 2) return null;
      return RoadRoute(
        points: points,
        distanceKm: ((route['distance'] as num?)?.toDouble() ?? 0) / 1000,
        durationMinutes:
            (((route['duration'] as num?)?.toDouble() ?? 0) / 60).round(),
        isRoadRoute: true,
        usesTraffic: false,
      );
    } catch (_) {
      return null;
    }
  }
}

class _CachedRoadRoute {
  const _CachedRoadRoute(this.route, this.expiresAt);

  final RoadRoute route;
  final DateTime expiresAt;
}
