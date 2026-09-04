import 'package:flutter_test/flutter_test.dart';
import 'package:chargemy/domain/models/charging_models.dart';
import 'package:chargemy/domain/services/open_route_service.dart';

void main() {
  test('rejects a Peninsular Malaysia to Borneo road journey', () async {
    final route = await OpenRouteService.drivingRoute(
      origin: const GeoLocation(1.4927, 103.7414),
      destination: const GeoLocation(1.5533, 110.3592),
    );

    expect(route.isRoadRoute, isFalse);
    expect(route.isGeographicallyUnreachable, isTrue);
    expect(route.points, isEmpty);
    expect(route.durationMinutes, 0);
    expect(route.unavailableMessage, contains('Sea or air travel is required'));
  });
}
