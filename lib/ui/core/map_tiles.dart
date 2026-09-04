import 'package:flutter_map/flutter_map.dart';

TileLayer chargeMyTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.chargemy.app',
  tileProvider: NetworkTileProvider(
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 250 * 1024 * 1024,
    ),
  ),
);
