import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_options.dart';

class SupabaseBootstrap {
  static Future<void> initialize() => Supabase.initialize(
    url: SupabaseOptions.url,
    publishableKey: SupabaseOptions.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}
