import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chargemy/app.dart';
import 'package:chargemy/app_dependencies.dart';
import 'package:chargemy/data/repositories/demo_station_repository.dart';
import 'package:chargemy/ui/core/app_state.dart';
import 'package:chargemy/supabase_options.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseOptions.url,
      publishableKey: SupabaseOptions.anonKey,
    );
  });

  testWidgets('shows ChargeMY station discovery', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dependenciesProvider.overrideWithValue(
            AppDependencies(stationRepository: DemoStationRepository()),
          ),
          sessionProvider.overrideWith((ref) => SessionController()),
        ],
        child: const ChargeMyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('ChargeMY'), findsOneWidget);
    expect(find.textContaining('stations'), findsOneWidget);
  });
}
