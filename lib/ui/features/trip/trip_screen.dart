import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../domain/models/charging_models.dart';
import '../../../domain/services/open_route_service.dart';
import '../../../domain/services/smart_stop_planner.dart';
import '../../core/app_state.dart';
import '../../core/map_tiles.dart';
import '../../core/widgets.dart';
import '../navigation/in_app_navigation_screen.dart';

class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key});

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  static const _defaultOrigin = GeoLocation(3.1390, 101.6869);
  static const _defaultDestination = GeoLocation(5.4141, 100.3288);
  int _currentSoc = 55;
  Future<RoadRoute>? _roadRoute;
  late final TextEditingController _destinationController;
  late final TextEditingController _originController;
  Timer? _destinationDebounce;
  Timer? _originDebounce;
  List<Map<String, dynamic>> _destinationSuggestions = const [];
  List<Map<String, dynamic>> _originSuggestions = const [];
  bool _searchingDestination = false;
  bool _searchingOrigin = false;
  bool _suppressDestinationListener = false;
  bool _suppressOriginListener = false;
  bool _usingCurrentLocation = false;
  GeoLocation _origin = _defaultOrigin;
  String _originLabel = 'Kuala Lumpur (default)';
  GeoLocation _destination = _defaultDestination;
  String _destinationLabel = 'George Town, Penang';
  static final Set<String> _completedStopIds = <String>{};
  static SmartStop? _pendingTripStop;
  static int? _pendingTripTargetSoc;
  SmartStop? _selectedStop;
  RoadRoute? _lastReadyRoadRoute;
  GeoLocation? _lastReadyOrigin;
  GeoLocation? _lastReadyDestination;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController(text: _destinationLabel);
    _originController = TextEditingController(text: _originLabel);
    _destinationController.addListener(_onDestinationChanged);
    _originController.addListener(_onOriginChanged);
    _roadRoute = _loadDestinationRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumePendingTripProgress();
    });
  }

  @override
  void dispose() {
    _destinationDebounce?.cancel();
    _originDebounce?.cancel();
    _destinationController.removeListener(_onDestinationChanged);
    _originController.removeListener(_onOriginChanged);
    _destinationController.dispose();
    _originController.dispose();
    super.dispose();
  }

  Future<RoadRoute> _loadDestinationRoute() => OpenRouteService.drivingRoute(
    origin: _origin,
    destination: _destination,
    includeElevation: true,
  );

  void _onDestinationChanged() {
    if (_suppressDestinationListener) return;
    final query = _destinationController.text.trim();
    _destinationDebounce?.cancel();
    final savedName = query.toLowerCase();
    if (savedName == 'home' || savedName == 'work') {
      final session = ref.read(sessionProvider);
      final saved = savedName == 'home' ? session.home : session.work;
      if (saved != null) {
        _selectSavedDestination(
          '${savedName == 'home' ? 'Home' : 'Work'} · ${saved.address ?? ''}',
          saved,
        );
      } else {
        setState(() => _destinationSuggestions = const []);
      }
      return;
    }
    if (query.length < 2) {
      setState(() => _destinationSuggestions = const []);
      return;
    }
    _destinationDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchDestinationSuggestions(query),
    );
  }

  void _onOriginChanged() {
    if (_suppressOriginListener) return;
    final query = _originController.text.trim();
    _originDebounce?.cancel();
    if (query.length < 2) {
      setState(() => _originSuggestions = const []);
      return;
    }
    _originDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchPlaceSuggestions(query, isOrigin: true),
    );
  }

  Future<void> _fetchDestinationSuggestions(String query) =>
      _fetchPlaceSuggestions(query, isOrigin: false);

  Future<void> _confirmTypedPlace({required bool isOrigin}) async {
    final controller = isOrigin ? _originController : _destinationController;
    final query = controller.text.trim();
    if (query.length < 2) return;
    await _fetchPlaceSuggestions(query, isOrigin: isOrigin);
    if (!mounted || controller.text.trim() != query) return;
    final suggestions = isOrigin ? _originSuggestions : _destinationSuggestions;
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching Malaysian location was found.'),
        ),
      );
      return;
    }
    if (isOrigin) {
      _selectOrigin(suggestions.first);
    } else {
      _selectDestination(suggestions.first);
    }
  }

  Future<void> _fetchPlaceSuggestions(
    String query, {
    required bool isOrigin,
  }) async {
    setState(() {
      if (isOrigin) {
        _searchingOrigin = true;
      } else {
        _searchingDestination = true;
      }
    });
    try {
      final response = await http.get(
        Uri.https('nominatim.openstreetmap.org', '/search', {
          'format': 'jsonv2',
          'q': query,
          'countrycodes': 'my',
          'limit': '5',
          'addressdetails': '1',
        }),
        headers: const {'User-Agent': 'ChargeMY/1.0 student prototype'},
      );
      if (response.statusCode != 200) {
        throw StateError('Location search failed.');
      }
      final results =
          (jsonDecode(response.body) as List)
              .whereType<Map>()
              .map(
                (item) => <String, dynamic>{
                  'label': item['display_name'] as String? ?? query,
                  'lat': double.tryParse('${item['lat']}'),
                  'lng': double.tryParse('${item['lon']}'),
                },
              )
              .where((item) => item['lat'] != null && item['lng'] != null)
              .toList();
      if (!mounted) return;
      setState(() {
        if (isOrigin) {
          _originSuggestions = results;
        } else {
          _destinationSuggestions = results;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isOrigin) {
            _originSuggestions = const [];
          } else {
            _destinationSuggestions = const [];
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isOrigin) {
            _searchingOrigin = false;
          } else {
            _searchingDestination = false;
          }
        });
      }
    }
  }

  void _selectOrigin(Map<String, dynamic> result) {
    final latitude = result['lat'] as double?;
    final longitude = result['lng'] as double?;
    if (latitude == null || longitude == null) return;
    final label = result['label'] as String? ?? 'Selected starting location';
    FocusScope.of(context).unfocus();
    _suppressOriginListener = true;
    _originController.text = label;
    _suppressOriginListener = false;
    setState(() {
      _usingCurrentLocation = false;
      _origin = GeoLocation(latitude, longitude, address: label);
      _originLabel = label;
      _originSuggestions = const [];
      _completedStopIds.clear();
      _selectedStop = null;
      _roadRoute = _loadDestinationRoute();
    });
  }

  Future<void> _useCurrentLocation({bool showFeedback = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services first.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final location = GeoLocation(position.latitude, position.longitude);
      if (!mounted) return;
      _suppressOriginListener = true;
      _originController.text = 'Current location';
      _suppressOriginListener = false;
      setState(() {
        _usingCurrentLocation = true;
        _origin = location;
        _originLabel = 'Current location';
        _originSuggestions = const [];
        _completedStopIds.clear();
        _selectedStop = null;
        _roadRoute = _loadDestinationRoute();
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Starting from your current location.')),
        );
      }
    } catch (error) {
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  void _retryRoadRoute() {
    setState(() {
      _roadRoute = _loadDestinationRoute();
    });
  }

  void _selectDestination(Map<String, dynamic> result) {
    final latitude = result['lat'] as double?;
    final longitude = result['lng'] as double?;
    if (latitude == null || longitude == null) return;
    FocusScope.of(context).unfocus();
    _suppressDestinationListener = true;
    _destinationController.text =
        result['label'] as String? ?? 'Selected destination';
    _suppressDestinationListener = false;
    setState(() {
      _destination = GeoLocation(
        latitude,
        longitude,
        address: result['label'] as String?,
      );
      _destinationLabel = result['label'] as String? ?? 'Selected destination';
      _destinationSuggestions = const [];
      _completedStopIds.clear();
      _selectedStop = null;
      _roadRoute = _loadDestinationRoute();
    });
  }

  void _selectSavedDestination(String label, GeoLocation location) {
    FocusScope.of(context).unfocus();
    _suppressDestinationListener = true;
    _destinationController.text = label;
    _suppressDestinationListener = false;
    setState(() {
      _destination = location;
      _destinationLabel = label;
      _destinationSuggestions = const [];
      _completedStopIds.clear();
      _selectedStop = null;
      _roadRoute = _loadDestinationRoute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isAuthenticated) return _signedOut(context);
    final stations = ref.watch(stationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Smart journey planner')),
      body: stations.when(
        loading:
            () => _planner(
              context,
              session.vehicle,
              const [],
              null,
              routeLoading: true,
              initialPlanning: true,
              routeError: null,
              displayedOrigin: _origin,
              displayedDestination: _destination,
              home: session.home,
              work: session.work,
            ),
        error:
            (error, _) => _journeyError(
              message:
                  'Charging stations could not be loaded. ${friendlyErrorMessage(error)}',
              onRetry: () => ref.invalidate(stationsProvider),
            ),
        data:
            (items) => FutureBuilder<RoadRoute>(
              future: _roadRoute,
              builder: (context, route) {
                final routeLoading =
                    route.connectionState != ConnectionState.done;
                if (routeLoading && _lastReadyRoadRoute == null) {
                  return _planner(
                    context,
                    session.vehicle,
                    items,
                    null,
                    routeLoading: true,
                    initialPlanning: true,
                    routeError: null,
                    displayedOrigin: _origin,
                    displayedDestination: _destination,
                    home: session.home,
                    work: session.work,
                  );
                }
                if (!routeLoading && route.hasData) {
                  _lastReadyRoadRoute = route.data;
                  _lastReadyOrigin = _origin;
                  _lastReadyDestination = _destination;
                }
                if (route.hasError && _lastReadyRoadRoute == null) {
                  return _journeyError(
                    message:
                        'The road route could not be calculated. ${friendlyErrorMessage(route.error!)}',
                    onRetry: _retryRoadRoute,
                  );
                }
                final displayedRoute =
                    !routeLoading && route.hasData
                        ? route.data!
                        : _lastReadyRoadRoute!;
                return _planner(
                  context,
                  session.vehicle,
                  items,
                  displayedRoute,
                  routeLoading: routeLoading,
                  initialPlanning: false,
                  routeError: route.hasError ? route.error : null,
                  displayedOrigin: _lastReadyOrigin ?? _origin,
                  displayedDestination: _lastReadyDestination ?? _destination,
                  home: session.home,
                  work: session.work,
                );
              },
            ),
      ),
    );
  }

  Widget _planningJourney() {
    return Card(
      child: SizedBox(
        height: 220,
        child: const Center(
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
                'Planning your journey...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Calculating the road route and charging stops from the default starting location.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _journeyError({
    required String message,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              'Journey planning unavailable',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signedOut(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart journey planner')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 54),
              const SizedBox(height: 16),
              const Text(
                'Sign in to calculate a battery-aware route.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/auth'),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planner(
    BuildContext context,
    VehicleProfile vehicle,
    List<ChargingStation> stations,
    RoadRoute? roadRoute, {
    required bool routeLoading,
    required bool initialPlanning,
    required Object? routeError,
    required GeoLocation displayedOrigin,
    required GeoLocation displayedDestination,
    GeoLocation? home,
    GeoLocation? work,
  }) {
    final geographicallyUnreachable =
        roadRoute?.isGeographicallyUnreachable == true;
    final plan = SmartStopPlanner.plan(
      origin: displayedOrigin,
      destination: displayedDestination,
      currentSoc: _currentSoc,
      vehicle: vehicle,
      stations: stations,
      excludedStationIds: _completedStopIds,
      routeDistanceKm:
          roadRoute?.isRoadRoute == true ? roadRoute!.distanceKm : null,
      elevationGainM: roadRoute?.elevationGainM,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_originLabel.split(',').first} → ${_destinationLabel.split(',').first}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _originController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _confirmTypedPlace(isOrigin: true),
                  decoration: InputDecoration(
                    labelText: 'Starting location',
                    hintText: 'Search a Malaysian place or use GPS',
                    prefixIcon: const Icon(Icons.trip_origin),
                    suffixIcon:
                        _searchingOrigin
                            ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : IconButton(
                              tooltip: 'Use current GPS location',
                              onPressed: _useCurrentLocation,
                              icon: Icon(
                                Icons.my_location,
                                color:
                                    _usingCurrentLocation
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                              ),
                            ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_originSuggestions.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children:
                          _originSuggestions
                              .map(
                                (result) => ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                  title: Text(
                                    result['label'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _selectOrigin(result),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _destinationController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _confirmTypedPlace(isOrigin: false),
                  decoration: InputDecoration(
                    labelText: 'Destination',
                    hintText: 'Search a Malaysian destination',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon:
                        _searchingDestination
                            ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (home != null || work != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (home != null)
                        ActionChip(
                          avatar: const Icon(Icons.home_outlined, size: 18),
                          label: const Text('Home'),
                          onPressed:
                              () => _selectSavedDestination(
                                'Home · ${home.address ?? ''}',
                                home,
                              ),
                        ),
                      if (work != null)
                        ActionChip(
                          avatar: const Icon(Icons.work_outline, size: 18),
                          label: const Text('Work'),
                          onPressed:
                              () => _selectSavedDestination(
                                'Work · ${work.address ?? ''}',
                                work,
                              ),
                        ),
                    ],
                  ),
                ],
                if (_destinationSuggestions.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children:
                          _destinationSuggestions
                              .map(
                                (result) => ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                  title: Text(
                                    result['label'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _selectDestination(result),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  initialPlanning
                      ? 'Planning the default route...'
                      : routeLoading
                      ? 'Updating road route...'
                      : geographicallyUnreachable
                      ? 'No continuous road route is available'
                      : roadRoute?.isRoadRoute == true
                      ? '${roadRoute!.distanceKm.toStringAsFixed(0)} km road route - about ${roadRoute.durationMinutes} min drive'
                      : '${plan.distanceKm.toStringAsFixed(0)} km estimated road distance',
                ),
                if (!geographicallyUnreachable && !initialPlanning) ...[
                  Text(
                    '${plan.estimatedEnergyKwh.toStringAsFixed(1)} kWh predicted battery use',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.battery_charging_full_outlined),
                      const SizedBox(width: 8),
                      Text('Current battery: $_currentSoc%'),
                      const Spacer(),
                      Text(
                        vehicle.displayName,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  Slider(
                    value: _currentSoc.toDouble(),
                    min: 20,
                    max: 100,
                    divisions: 16,
                    label: '$_currentSoc%',
                    onChanged:
                        (value) => setState(() => _currentSoc = value.round()),
                  ),
                  Text(
                    'Reserve protected: ${vehicle.reserveSoc}% - moving the slider recalculates whether a charging stop is needed.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose one recommended stop. After its charging session is completed, reopen Smart Journey to calculate the next stop without repeating the completed station.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Charging stops are suggested when the predicted arrival battery is 60% or lower. At 80–90%, the planner continues without an unnecessary stop.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (initialPlanning) ...[
          const SizedBox(height: 16),
          _planningJourney(),
        ] else if (geographicallyUnreachable) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.directions_boat_outlined,
                    size: 42,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Road journey unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    roadRoute?.unavailableMessage ??
                        'This destination cannot be reached entirely by road. Sea or air travel is required.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a destination on the same connected road network to calculate a driving route and charging stops.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          _TripMap(
            plan: plan,
            roadRoute: roadRoute,
            origin: displayedOrigin,
            destination: displayedDestination,
            updating: routeLoading,
            updateError:
                routeError == null ? null : friendlyErrorMessage(routeError),
            onRetry: _retryRoadRoute,
          ),
          const SizedBox(height: 12),
          _FastestPlanSummary(
            origin: displayedOrigin,
            destination: displayedDestination,
            plan: plan,
            directRoute: roadRoute,
          ),
          const SizedBox(height: 22),
          Text(
            plan.canReachDestination
                ? plan.stops.isEmpty
                    ? 'No charging stop needed'
                    : 'Recommended charging stops'
                : 'No safe stop is currently available',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (plan.stops.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          plan.canReachDestination
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          color:
                              plan.canReachDestination
                                  ? Colors.green
                                  : Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            plan.canReachDestination
                                ? 'Your current charge reaches the destination safely.'
                                : 'Increase charge or try again when a compatible pile is available.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The planner only selects available piles compatible with your saved vehicle.',
                    ),
                    if (plan.canReachDestination) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              () => _routeToDestination(context, _origin),
                          icon: const Icon(Icons.flag_outlined),
                          label: Text(
                            'Route to ${_destinationLabel.split(',').first}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else ...[
            for (final stop in plan.stops)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            child: Text('${plan.stops.indexOf(stop) + 1}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              cleanDisplayText(stop.station.name),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          StatusPill(status: stop.pile.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _StopRouteSummary(
                        origin:
                            plan.stops.indexOf(stop) == 0
                                ? _origin
                                : plan
                                    .stops[plan.stops.indexOf(stop) - 1]
                                    .station
                                    .location,
                        originLabel:
                            plan.stops.indexOf(stop) == 0
                                ? _originLabel
                                : cleanDisplayText(
                                  plan
                                      .stops[plan.stops.indexOf(stop) - 1]
                                      .station
                                      .name,
                                ),
                        stop: stop,
                        fallbackDistanceKm:
                            plan.stops.indexOf(stop) == 0
                                ? stop.distanceFromOriginKm
                                : stop.distanceFromOriginKm -
                                    plan
                                        .stops[plan.stops.indexOf(stop) - 1]
                                        .distanceFromOriginKm,
                        fallbackArrivalMinutes: null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Arrive with ${stop.arrivalSoc}% battery · charge about ${stop.chargeMinutes} min · leave at ${stop.recommendedDepartureSoc}%',
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed:
                            stop.station.id == plan.stops.first.station.id
                                ? () => setState(() => _selectedStop = stop)
                                : null,
                        icon: Icon(
                          _selectedStop?.station.id == stop.station.id
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          stop.station.id != plan.stops.first.station.id
                              ? 'Complete the previous stop first'
                              : _selectedStop?.station.id == stop.station.id
                              ? 'Selected stop'
                              : 'Select this stop',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_selectedStop != null)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route via ${cleanDisplayText(_selectedStop!.station.name)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'This is the next reachable stop. Complete charging here before the next stop or the final destination is unlocked.',
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _routeSelectedStop(context, plan),
                          icon: const Icon(Icons.navigation_outlined),
                          label: const Text('Route to selected stop'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Final destination'),
                subtitle: Text(
                  plan.stops.isEmpty
                      ? 'Ready to route after the last charging session.'
                      : 'Complete the listed charging stops first. The destination route will unlock after the final stop.',
                ),
                trailing:
                    plan.stops.isEmpty
                        ? FilledButton(
                          onPressed:
                              () => _routeToDestination(context, _origin),
                          child: const Text('Route'),
                        )
                        : null,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            roadRoute?.isRoadRoute == true
                ? 'The fastest-plan total uses the same OpenStreetMap/OSRM road legs opened by guided navigation. Charging time uses your vehicle model and the selected pile power.'
                : 'The road-routing service is temporarily unavailable, so the line is an estimate. Check the emulator internet connection and reopen this page to retry.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _routeSelectedStop(
    BuildContext context,
    JourneyPlan plan,
  ) async {
    final stop = _selectedStop;
    if (stop == null) return;
    if (plan.stops.isEmpty || plan.stops.first.station.id != stop.station.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete the next reachable stop before continuing.'),
        ),
      );
      return;
    }
    final arrived = await context.push<GeoLocation>(
      '/navigation',
      extra: NavigationRequest(origin: _origin, station: stop.station),
    );
    if (!mounted || !context.mounted || arrived == null) return;
    final endingSoc = await _chooseAndStartCharging(context, stop, arrived);
    if (!mounted || endingSoc == null) return;
    _pendingTripStop = null;
    _pendingTripTargetSoc = null;
    final nextOrigin = stop.station.location;
    final nextLabel = cleanDisplayText(stop.station.name);
    _suppressOriginListener = true;
    _originController.text = nextLabel;
    _suppressOriginListener = false;
    setState(() {
      _selectedStop = null;
      _completedStopIds.add(stop.station.id);
      _origin = nextOrigin;
      _originLabel = nextLabel;
      _usingCurrentLocation = false;
      _currentSoc = endingSoc;
      _roadRoute = _loadDestinationRoute();
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Stop completed. Smart Journey is ready for the next leg or final destination.',
          ),
        ),
      );
    }
  }

  Future<int?> _chooseAndStartCharging(
    BuildContext context,
    SmartStop stop,
    GeoLocation arrived,
  ) async {
    final session = ref.read(sessionProvider);
    if (session.activeSession != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the current charging session before starting another one.',
          ),
        ),
      );
      return null;
    }
    final vehicle = session.vehicle;
    final compatible =
        stop.station.piles
            .where(
              (pile) =>
                  pile.status == PileStatus.available &&
                  vehicle.connectorTypes.contains(pile.connectorType),
            )
            .toList();
    if (compatible.isEmpty) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('No compatible pile available'),
                content: const Text(
                  'The station status changed while you were travelling. Return to the planner and choose another safe route.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
      return null;
    }
    final pile = await showModalBottomSheet<ChargingPile>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                Text(
                  'Choose a charging pile',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                Text(cleanDisplayText(stop.station.name)),
                const SizedBox(height: 12),
                const Text(
                  'Select an available compatible pile to start the charging session.',
                ),
                const SizedBox(height: 8),
                ...compatible.map(
                  (candidate) => Card(
                    child: ListTile(
                      title: Text(
                        '${cleanDisplayText(candidate.label)} · ${candidate.connectorType}',
                      ),
                      subtitle: Text(
                        '${candidate.powerKw.toStringAsFixed(0)} kW · RM ${candidate.pricePerKwh.toStringAsFixed(2)}/kWh',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(sheetContext, candidate),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
    if (pile == null || !context.mounted) return null;
    final setup = await showDialog<_TripChargeSetup>(
      context: context,
      builder:
          (dialogContext) => _TripChargeSetupDialog(
            defaultStartSoc: stop.arrivalSoc,
            defaultTargetSoc: stop.recommendedDepartureSoc,
          ),
    );
    if (setup == null || !context.mounted) return null;
    try {
      final effectivePower =
          pile.powerKw < vehicle.maxChargePowerKw
              ? pile.powerKw
              : vehicle.maxChargePowerKw;
      final started = (await ref
          .read(stationRepositoryProvider)
          .startCharging(
            stationId: stop.station.id,
            pileId: pile.id,
            location: arrived,
            startSoc: setup.startSoc,
            targetSoc: setup.targetSoc,
          )).copyWith(
        stateOfCharge: setup.startSoc,
        startSoc: setup.startSoc,
        targetSoc: setup.targetSoc,
        chargePowerKw: effectivePower,
        batteryKwh: vehicle.batteryKwh,
        startedAt: DateTime.now(),
      );
      session.setActiveSession(started);
      _pendingTripStop = stop;
      _pendingTripTargetSoc = setup.targetSoc;
      if (!context.mounted) return null;
      final openDashboard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Charging started'),
              content: Text(
                '${cleanDisplayText(pile.label)} is charging from ${setup.startSoc}% to ${setup.targetSoc}%. Open the charging dashboard and complete the session before the next route unlocks.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Open charging dashboard'),
                ),
              ],
            ),
      );
      if (openDashboard == true && context.mounted) {
        await context.push('/home?view=user');
      }
      return ref.read(sessionProvider).activeSession == null
          ? setup.targetSoc
          : null;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start charging. Please try again.'),
          ),
        );
      }
      return null;
    }
  }

  void _resumePendingTripProgress() {
    final pending = _pendingTripStop;
    if (!mounted || pending == null) return;
    if (ref.read(sessionProvider).activeSession != null) return;
    final session = ref.read(sessionProvider);
    final endingSoc =
        session.lastCompletedSoc ??
        _pendingTripTargetSoc ??
        pending.recommendedDepartureSoc;
    _pendingTripStop = null;
    _pendingTripTargetSoc = null;
    final nextLabel = cleanDisplayText(pending.station.name);
    _suppressOriginListener = true;
    _originController.text = nextLabel;
    _suppressOriginListener = false;
    setState(() {
      _selectedStop = null;
      _completedStopIds.add(pending.station.id);
      _origin = pending.station.location;
      _originLabel = nextLabel;
      _usingCurrentLocation = false;
      _currentSoc = endingSoc;
      _roadRoute = _loadDestinationRoute();
    });
  }

  Future<void> _routeToDestination(
    BuildContext context,
    GeoLocation origin,
  ) async {
    final route = await OpenRouteService.drivingRoute(
      origin: origin,
      destination: _destination,
    );
    if (!route.isRoadRoute) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              route.unavailableMessage ??
                  'This destination cannot be reached by road.',
            ),
          ),
        );
      }
      return;
    }
    final destinationStation = ChargingStation(
      id: 'journey-destination',
      name: _destinationLabel.split(',').first,
      address: _destinationLabel,
      location: _destination,
      brand: 'Destination',
      indoorOutdoor: 'Unknown',
      localAuthority: 'Unknown',
      piles: const [],
    );
    if (context.mounted) {
      await context.push<GeoLocation>(
        '/navigation',
        extra: NavigationRequest(origin: origin, station: destinationStation),
      );
    }
  }
}

class _TripChargeSetup {
  const _TripChargeSetup({required this.startSoc, required this.targetSoc});

  final int startSoc;
  final int targetSoc;
}

class _TripChargeSetupDialog extends StatefulWidget {
  const _TripChargeSetupDialog({
    required this.defaultStartSoc,
    required this.defaultTargetSoc,
  });

  final int defaultStartSoc;
  final int defaultTargetSoc;

  @override
  State<_TripChargeSetupDialog> createState() => _TripChargeSetupDialogState();
}

class _TripChargeSetupDialogState extends State<_TripChargeSetupDialog> {
  late final TextEditingController _startController;
  late final TextEditingController _targetController;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: '${widget.defaultStartSoc}');
    _targetController = TextEditingController(
      text: '${widget.defaultTargetSoc}',
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _submit() {
    final start = int.tryParse(_startController.text.trim());
    final target = int.tryParse(_targetController.text.trim());
    if (start == null ||
        target == null ||
        start < 0 ||
        target > 100 ||
        target <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid target higher than the current battery percentage.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _TripChargeSetup(startSoc: start, targetSoc: target),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set charging target'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _startController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Current battery (%)'),
        ),
        TextField(
          controller: _targetController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Target battery (%)'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Start charging')),
    ],
  );
}

class _StopRouteSummary extends StatefulWidget {
  const _StopRouteSummary({
    required this.origin,
    required this.originLabel,
    required this.stop,
    required this.fallbackDistanceKm,
    this.fallbackArrivalMinutes,
  });

  final GeoLocation origin;
  final String originLabel;
  final SmartStop stop;
  final double fallbackDistanceKm;
  final int? fallbackArrivalMinutes;

  @override
  State<_StopRouteSummary> createState() => _StopRouteSummaryState();
}

class _FastestPlanSummary extends StatefulWidget {
  const _FastestPlanSummary({
    required this.origin,
    required this.destination,
    required this.plan,
    required this.directRoute,
  });

  final GeoLocation origin;
  final GeoLocation destination;
  final JourneyPlan plan;
  final RoadRoute? directRoute;

  @override
  State<_FastestPlanSummary> createState() => _FastestPlanSummaryState();
}

class _FastestPlanSummaryState extends State<_FastestPlanSummary> {
  late Future<int> _totalMinutes;

  @override
  void initState() {
    super.initState();
    _totalMinutes = _calculate();
  }

  @override
  void didUpdateWidget(covariant _FastestPlanSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final planChanged =
        oldWidget.plan.stops.length != widget.plan.stops.length ||
        oldWidget.plan.stops.any((oldStop) {
          SmartStop? next;
          for (final candidate in widget.plan.stops) {
            if (candidate.station.id == oldStop.station.id) {
              next = candidate;
              break;
            }
          }
          return next == null ||
              next.chargeMinutes != oldStop.chargeMinutes ||
              next.arrivalSoc != oldStop.arrivalSoc ||
              next.recommendedDepartureSoc != oldStop.recommendedDepartureSoc ||
              next.pile.powerKw != oldStop.pile.powerKw;
        });
    if (oldWidget.origin.latitude != widget.origin.latitude ||
        oldWidget.origin.longitude != widget.origin.longitude ||
        oldWidget.destination.latitude != widget.destination.latitude ||
        oldWidget.destination.longitude != widget.destination.longitude ||
        oldWidget.directRoute?.durationMinutes !=
            widget.directRoute?.durationMinutes ||
        oldWidget.directRoute?.distanceKm != widget.directRoute?.distanceKm ||
        planChanged) {
      _totalMinutes = _calculate();
    }
  }

  Future<int> _calculate() async {
    if (widget.plan.stops.isEmpty && widget.directRoute?.isRoadRoute == true) {
      return widget.directRoute!.durationMinutes;
    }
    var total = 0;
    var legOrigin = widget.origin;
    for (final stop in widget.plan.stops) {
      final route = await OpenRouteService.drivingRoute(
        origin: legOrigin,
        destination: stop.station.location,
      );
      if (route.isRoadRoute) total += route.durationMinutes;
      total += stop.chargeMinutes;
      legOrigin = stop.station.location;
    }
    final finalRoute = await OpenRouteService.drivingRoute(
      origin: legOrigin,
      destination: widget.destination,
    );
    if (finalRoute.isRoadRoute) total += finalRoute.durationMinutes;
    return total;
  }

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.speed_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<int>(
              future: _totalMinutes,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Text(
                    'Calculating fastest drive + charging time…',
                  );
                }
                final minutes = snapshot.data!;
                final hours = minutes ~/ 60;
                final remainder = minutes % 60;
                final duration =
                    hours > 0 ? '${hours}h ${remainder}m' : '${remainder}m';
                return Text(
                  'Fastest safe plan: $duration total (${widget.plan.stops.length} charging stop${widget.plan.stops.length == 1 ? '' : 's'})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _StopRouteSummaryState extends State<_StopRouteSummary> {
  late Future<RoadRoute> _route;

  @override
  void initState() {
    super.initState();
    _route = _loadRoute();
  }

  @override
  void didUpdateWidget(covariant _StopRouteSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origin.latitude != widget.origin.latitude ||
        oldWidget.origin.longitude != widget.origin.longitude ||
        oldWidget.stop.station.id != widget.stop.station.id) {
      _route = _loadRoute();
    }
  }

  Future<RoadRoute> _loadRoute() => OpenRouteService.drivingRoute(
    origin: widget.origin,
    destination: widget.stop.station.location,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<RoadRoute>(
    future: _route,
    builder: (context, snapshot) {
      final route = snapshot.data;
      final hasRoadRoute = route?.isRoadRoute == true;
      final distance =
          hasRoadRoute ? route!.distanceKm : widget.fallbackDistanceKm;
      final arrivalMinutes =
          hasRoadRoute ? route!.durationMinutes : widget.fallbackArrivalMinutes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${distance.toStringAsFixed(1)} km from ${widget.originLabel.split(',').first} · ${widget.stop.pile.connectorType} · ${widget.stop.pile.powerKw.toStringAsFixed(0)} kW',
          ),
          const SizedBox(height: 6),
          Text(
            arrivalMinutes == null
                ? 'Estimated arrival battery: ${widget.stop.arrivalSoc}%'
                : 'Estimated arrival: $arrivalMinutes min · battery ${widget.stop.arrivalSoc}%',
          ),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Loading the same road route used for navigation…',
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      );
    },
  );
}

class _TripMap extends StatefulWidget {
  const _TripMap({
    required this.plan,
    required this.roadRoute,
    required this.origin,
    required this.destination,
    required this.updating,
    required this.updateError,
    required this.onRetry,
  });

  final JourneyPlan plan;
  final RoadRoute? roadRoute;
  final GeoLocation origin;
  final GeoLocation destination;
  final bool updating;
  final String? updateError;
  final VoidCallback onRetry;

  @override
  State<_TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<_TripMap> {
  final MapController _mapController = MapController();
  List<LatLng>? _routePoints;
  bool _routePointsLoading = true;
  String? _routePointsError;
  int _routePointsRequest = 0;
  String? _lastFittedRoute;

  @override
  void initState() {
    super.initState();
    _requestRoutePoints();
  }

  @override
  void didUpdateWidget(covariant _TripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origin.latitude != widget.origin.latitude ||
        oldWidget.origin.longitude != widget.origin.longitude ||
        oldWidget.destination.latitude != widget.destination.latitude ||
        oldWidget.destination.longitude != widget.destination.longitude ||
        oldWidget.roadRoute?.distanceKm != widget.roadRoute?.distanceKm ||
        oldWidget.roadRoute?.points.length != widget.roadRoute?.points.length ||
        oldWidget.plan.stops.length != widget.plan.stops.length ||
        oldWidget.plan.stops.asMap().entries.any(
          (entry) =>
              entry.key >= widget.plan.stops.length ||
              entry.value.station.id != widget.plan.stops[entry.key].station.id,
        )) {
      _lastFittedRoute = null;
      _routePointsLoading = true;
      _routePointsError = null;
      _requestRoutePoints();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fitRoute(List<LatLng> points) {
    if (points.length < 2) return;
    final signature = [
      points.first.latitude.toStringAsFixed(5),
      points.first.longitude.toStringAsFixed(5),
      points.last.latitude.toStringAsFixed(5),
      points.last.longitude.toStringAsFixed(5),
      points.length,
    ].join(':');
    if (_lastFittedRoute == signature) return;
    _lastFittedRoute = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(32),
        ),
      );
    });
  }

  void _requestRoutePoints() {
    final request = ++_routePointsRequest;
    _loadRoutePoints().then(
      (points) {
        if (!mounted || request != _routePointsRequest) return;
        setState(() {
          _routePoints = points;
          _routePointsLoading = false;
          _routePointsError = null;
        });
      },
      onError: (Object error) {
        if (!mounted || request != _routePointsRequest) return;
        setState(() {
          _routePointsLoading = false;
          _routePointsError = friendlyErrorMessage(error);
        });
      },
    );
  }

  void _retryRoutePoints() {
    setState(() {
      _routePointsLoading = true;
      _routePointsError = null;
    });
    _requestRoutePoints();
  }

  Future<List<LatLng>> _loadRoutePoints() async {
    final originPoint = LatLng(widget.origin.latitude, widget.origin.longitude);
    final destinationPoint = LatLng(
      widget.destination.latitude,
      widget.destination.longitude,
    );
    if (widget.plan.stops.isEmpty && widget.roadRoute?.isRoadRoute == true) {
      return widget.roadRoute!.points;
    }
    final waypoints = <GeoLocation>[
      widget.origin,
      ...widget.plan.stops.map((stop) => stop.station.location),
      widget.destination,
    ];
    final points = <LatLng>[];
    for (var index = 0; index < waypoints.length - 1; index += 1) {
      final route = await OpenRouteService.drivingRoute(
        origin: waypoints[index],
        destination: waypoints[index + 1],
      );
      if (route.isRoadRoute && route.points.length > 1) {
        points.addAll(index == 0 ? route.points : route.points.skip(1));
      } else {
        if (points.isEmpty) points.add(originPoint);
        points.add(
          LatLng(waypoints[index + 1].latitude, waypoints[index + 1].longitude),
        );
      }
    }
    return points.isEmpty ? [originPoint, destinationPoint] : points;
  }

  @override
  Widget build(BuildContext context) {
    final originPoint = LatLng(widget.origin.latitude, widget.origin.longitude);
    final destinationPoint = LatLng(
      widget.destination.latitude,
      widget.destination.longitude,
    );
    final routePoints = _routePoints;
    if (routePoints == null) {
      return SizedBox(
        height: 220,
        child: Center(
          child:
              _routePointsError == null
                  ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Planning your journey...'),
                    ],
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'The map route could not be prepared. $_routePointsError',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _retryRoutePoints,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
        ),
      );
    }
    _fitRoute(routePoints);
    final errorMessage = widget.updateError ?? _routePointsError;
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: originPoint, initialZoom: 7.0),
              children: [
                chargeMyTileLayer(),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 4,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: originPoint,
                      width: 42,
                      height: 42,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF1677E8),
                        size: 40,
                        shadows: [
                          Shadow(color: Colors.white, blurRadius: 5),
                          Shadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                    ),
                    ...widget.plan.stops.map(
                      (stop) => Marker(
                        point: LatLng(
                          stop.station.location.latitude,
                          stop.station.location.longitude,
                        ),
                        width: 42,
                        height: 42,
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.green,
                          size: 34,
                        ),
                      ),
                    ),
                    Marker(
                      point: destinationPoint,
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.flag_rounded,
                        color: Colors.red,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Positioned(
              left: 8,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white70),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: 'Recenter on starting location',
                onPressed: () => _mapController.move(originPoint, 14.5),
                child: Icon(
                  Icons.my_location,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (widget.updating || _routePointsLoading)
              const Positioned(
                top: 8,
                left: 42,
                right: 42,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 9),
                        Expanded(child: Text('Updating route...')),
                      ],
                    ),
                  ),
                ),
              )
            else if (errorMessage != null)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Route update failed: $errorMessage',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed:
                              widget.updateError != null
                                  ? widget.onRetry
                                  : _retryRoutePoints,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
