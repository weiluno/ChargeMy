import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/models/charging_models.dart';
import '../../../domain/services/open_route_service.dart';
import '../../core/map_tiles.dart';
import '../../core/widgets.dart';

const _navigationArrivalRadiusMeters = 50.0;

class NavigationRequest {
  const NavigationRequest({required this.origin, required this.station});

  final GeoLocation origin;
  final ChargingStation station;
}

class InAppNavigationScreen extends StatefulWidget {
  const InAppNavigationScreen({super.key, required this.request});

  final NavigationRequest request;

  @override
  State<InAppNavigationScreen> createState() => _InAppNavigationScreenState();
}

class _InAppNavigationScreenState extends State<InAppNavigationScreen> {
  late Future<RoadRoute> _route;
  late GeoLocation _routeOrigin;
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  GeoLocation? _currentLocation;
  String? _locationError;
  DateTime? _lastLocationUpdate;
  bool _autoFollow = true;
  bool _mapReady = false;
  bool _rerouting = false;
  Timer? _demoTimer;
  bool _demoRunning = false;

  @override
  void initState() {
    super.initState();
    _routeOrigin = widget.request.origin;
    _route = _loadRoute(_routeOrigin);
    _startTracking();
  }

  Future<void> _startTracking() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission is required for navigation.');
      }
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (position) {
          if (!mounted) return;
          final location = GeoLocation(position.latitude, position.longitude);
          setState(() {
            _currentLocation = location;
            _lastLocationUpdate = DateTime.now();
          });
          if (_autoFollow && _mapReady) {
            _mapController.move(
              LatLng(location.latitude, location.longitude),
              16.5,
            );
          }
          if (!_demoRunning) _rerouteFrom(location);
        },
        onError: (Object error) {
          if (mounted) {
            setState(() => _locationError = friendlyErrorMessage(error));
          }
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() => _locationError = friendlyErrorMessage(error));
      }
    }
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _toggleDemo(RoadRoute route) {
    if (_demoRunning) {
      _demoTimer?.cancel();
      if (mounted) setState(() => _demoRunning = false);
      return;
    }
    if (route.points.length < 2) return;
    _demoTimer?.cancel();
    var progress = 0.0;
    setState(() {
      _demoRunning = true;
      _autoFollow = true;
    });
    _demoTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      progress = (progress + 0.02).clamp(0.0, 1.0).toDouble();
      final location = _demoLocation(route, progress);
      setState(() {
        _currentLocation = location;
        _lastLocationUpdate = DateTime.now();
      });
      if (_autoFollow && _mapReady) {
        _mapController.move(
          LatLng(location.latitude, location.longitude),
          16.5,
        );
      }
      if (progress >= 1.0) {
        timer.cancel();
        setState(() => _demoRunning = false);
      }
    });
  }

  GeoLocation _demoLocation(RoadRoute route, double progress) {
    if (progress >= 1.0) {
      return widget.request.station.location;
    }
    final scaled = progress * (route.points.length - 1);
    final index = scaled.floor().clamp(0, route.points.length - 2).toInt();
    final fraction = scaled - index;
    final from = route.points[index];
    final to = route.points[index + 1];
    return GeoLocation(
      from.latitude + (to.latitude - from.latitude) * fraction,
      from.longitude + (to.longitude - from.longitude) * fraction,
    );
  }

  Future<RoadRoute> _loadRoute(GeoLocation origin) async {
    return OpenRouteService.drivingRoute(
      origin: origin,
      destination: widget.request.station.location,
    );
  }

  void _rerouteFrom(GeoLocation location) {
    final movedMeters = Geolocator.distanceBetween(
      _routeOrigin.latitude,
      _routeOrigin.longitude,
      location.latitude,
      location.longitude,
    );
    if (_rerouting || movedMeters < 120) {
      return;
    }
    _routeOrigin = location;
    final nextRoute = _loadRoute(location);
    setState(() {
      _route = nextRoute;
      _rerouting = true;
    });
    nextRoute.whenComplete(() {
      if (mounted && identical(_route, nextRoute)) {
        setState(() => _rerouting = false);
      }
    });
  }

  Widget _routeLoadingScreen() {
    return Stack(
      children: [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 18),
                Text(
                  'Preparing navigation...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  'Finding the fastest accurate road route to this station.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: _RoundMapButton(
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<RoadRoute>(
      future: _route,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          _mapReady = false;
          return _routeLoadingScreen();
        }
        final route = snapshot.data!;
        if (!route.isRoadRoute) {
          _mapReady = false;
          return _RouteUnavailable(
            onBack: () => Navigator.of(context).pop(),
            onRetry: _retryRoute,
            message: route.unavailableMessage,
          );
        }
        final current = _currentLocation ?? widget.request.origin;
        final progress = _routeProgress(route, current);
        final distanceToStation = Geolocator.distanceBetween(
          current.latitude,
          current.longitude,
          widget.request.station.location.latitude,
          widget.request.station.location.longitude,
        );
        final arrived = distanceToStation <= _navigationArrivalRadiusMeters;
        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(current.latitude, current.longitude),
                initialZoom: 16.5,
                onMapReady: () {
                  _mapReady = true;
                  if (_autoFollow) {
                    _mapController.move(
                      LatLng(current.latitude, current.longitude),
                      16.5,
                    );
                  }
                },
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && _autoFollow) {
                    setState(() => _autoFollow = false);
                  }
                },
              ),
              children: [
                chargeMyTileLayer(),
                if (!arrived)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _remainingRoutePoints(route, current),
                        strokeWidth: 6,
                        color: const Color(0xFF1677E8),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(current.latitude, current.longitude),
                      width: 52,
                      height: 52,
                      child: Transform.rotate(
                        angle: _headingRadians(route, current),
                        child: const Icon(
                          Icons.navigation,
                          color: Color(0xFF1677E8),
                          size: 42,
                        ),
                      ),
                    ),
                    Marker(
                      point: LatLng(
                        widget.request.station.location.latitude,
                        widget.request.station.location.longitude,
                      ),
                      width: 52,
                      height: 52,
                      child: const Icon(
                        Icons.ev_station,
                        color: Colors.green,
                        size: 42,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    _RoundMapButton(
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _RoundMapButton(
                      icon: Icons.my_location,
                      highlighted: _autoFollow,
                      onPressed: () {
                        setState(() => _autoFollow = true);
                        _mapController.move(
                          LatLng(current.latitude, current.longitude),
                          16.5,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 184,
              child: _ZoomControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: _NavigationPanel(
                  station: widget.request.station,
                  progress: progress,
                  arrived: arrived,
                  rerouting: _rerouting,
                  lastLocationUpdate: _lastLocationUpdate,
                  locationError: _locationError,
                  onEnd: () => Navigator.of(context).pop(),
                  onStartDemo: () => _toggleDemo(route),
                  demoRunning: _demoRunning,
                  onChoosePile:
                      arrived
                          ? () => Navigator.of(
                            context,
                          ).pop(_currentLocation ?? widget.request.origin)
                          : null,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  _RouteProgress _routeProgress(RoadRoute route, GeoLocation current) {
    final directMeters = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      widget.request.station.location.latitude,
      widget.request.station.location.longitude,
    );
    if (directMeters <= _navigationArrivalRadiusMeters) {
      return const _RouteProgress(remainingKm: 0, etaMinutes: 0);
    }
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var index = 0; index < route.points.length; index += 1) {
      final point = route.points[index];
      final meters = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = index;
      }
    }
    var remainingMeters = nearestMeters;
    for (
      var index = nearestIndex;
      index < route.points.length - 1;
      index += 1
    ) {
      final from = route.points[index];
      final to = route.points[index + 1];
      remainingMeters += Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );
    }
    final remainingKm = remainingMeters / 1000;
    final eta =
        route.distanceKm == 0
            ? 0
            : (route.durationMinutes * remainingKm / route.distanceKm).ceil();
    return _RouteProgress(remainingKm: remainingKm, etaMinutes: eta);
  }

  List<LatLng> _remainingRoutePoints(RoadRoute route, GeoLocation current) {
    if (route.points.isEmpty) return const [];
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var index = 0; index < route.points.length; index += 1) {
      final point = route.points[index];
      final meters = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = index;
      }
    }
    return [
      LatLng(current.latitude, current.longitude),
      ...route.points
          .skip(nearestIndex)
          .map((point) => LatLng(point.latitude, point.longitude)),
    ];
  }

  static double _headingRadians(RoadRoute route, GeoLocation current) {
    if (route.points.length < 2) return 0;
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var index = 0; index < route.points.length; index += 1) {
      final point = route.points[index];
      final meters = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = index;
      }
    }
    final target =
        route.points[math.min(nearestIndex + 1, route.points.length - 1)];
    final deltaLatitude = target.latitude - current.latitude;
    final deltaLongitude = target.longitude - current.longitude;
    if (deltaLatitude == 0 && deltaLongitude == 0) return 0;
    return math.atan2(deltaLongitude, deltaLatitude);
  }

  void _zoomBy(double change) {
    final camera = _mapController.camera;
    final targetZoom = (camera.zoom + change).clamp(4.0, 19.0).toDouble();
    _mapController.move(camera.center, targetZoom);
    setState(() => _autoFollow = false);
  }

  void _retryRoute() {
    if (!mounted) return;
    setState(() {
      _route = _loadRoute(_routeOrigin);
      _rerouting = true;
    });
    _route.whenComplete(() {
      if (mounted) setState(() => _rerouting = false);
    });
  }
}

class _RouteProgress {
  const _RouteProgress({required this.remainingKm, required this.etaMinutes});

  final double remainingKm;
  final int etaMinutes;
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({
    required this.icon,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    shape: const CircleBorder(),
    color: highlighted ? const Color(0xFF1677E8) : Colors.white,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: highlighted ? Colors.white : Colors.black87),
    ),
  );
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 5,
    borderRadius: BorderRadius.circular(14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
          icon: const Icon(Icons.add),
        ),
        const SizedBox(width: 34, child: Divider(height: 1)),
        IconButton(
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove),
        ),
      ],
    ),
  );
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.station,
    required this.progress,
    required this.arrived,
    required this.rerouting,
    required this.lastLocationUpdate,
    required this.locationError,
    required this.onEnd,
    required this.onStartDemo,
    required this.demoRunning,
    required this.onChoosePile,
  });

  final ChargingStation station;
  final _RouteProgress progress;
  final bool arrived;
  final bool rerouting;
  final DateTime? lastLocationUpdate;
  final String? locationError;
  final VoidCallback onEnd;
  final VoidCallback onStartDemo;
  final bool demoRunning;
  final VoidCallback? onChoosePile;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 10,
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: arrived ? Colors.green.shade700 : const Color(0xFF1677E8),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.navigation, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  arrived ? 'You have arrived' : 'Continue to charging station',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      arrived
                          ? cleanDisplayText(station.name)
                          : '${progress.remainingKm.toStringAsFixed(1)} km · ${progress.etaMinutes} min',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      arrived
                          ? 'Choose an available pile from the station screen to start charging.'
                          : cleanDisplayText(station.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (rerouting)
                      const Text(
                        'Updating route from current GPS location…',
                        style: TextStyle(
                          color: Color(0xFF1677E8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (lastLocationUpdate != null)
                      Text(
                        'GPS updated ${TimeOfDay.fromDateTime(lastLocationUpdate!).format(context)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (locationError != null)
                      Text(
                        'GPS: $locationError',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (arrived)
                FilledButton.icon(
                  onPressed: onChoosePile,
                  icon: const Icon(Icons.ev_station_outlined),
                  label: const Text('Choose a pile'),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onStartDemo,
                      icon: Icon(
                        demoRunning ? Icons.pause : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(demoRunning ? 'Pause' : 'Start'),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: onEnd,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('End'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RouteUnavailable extends StatelessWidget {
  const _RouteUnavailable({
    required this.onBack,
    required this.onRetry,
    this.message,
  });

  final VoidCallback onBack;
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route_outlined, size: 52),
          const SizedBox(height: 12),
          Text(
            message ??
                'We could not load a road route right now. Please retry.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: onBack, child: const Text('Back')),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry route'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
