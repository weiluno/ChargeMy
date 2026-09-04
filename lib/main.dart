import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/local_notification_service.dart';
import 'supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StartupGate());
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<Object?> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _initializeServices();
  }

  Future<Object?> _initializeServices() async {
    try {
      await SupabaseBootstrap.initialize().timeout(const Duration(seconds: 12));
    } catch (error) {
      return error;
    }
    try {
      await LocalNotificationService.instance.initialize().timeout(
        const Duration(seconds: 4),
      );
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Object?>(
    future: _startup,
    builder: (context, snapshot) {
      if (!snapshot.hasData &&
          snapshot.connectionState != ConnectionState.done) {
        return const _StartupLoadingApp();
      }
      final error = snapshot.data;
      if (error != null) {
        return StartupErrorApp(
          error: error,
          onRetry: () => setState(() => _startup = _initializeServices()),
        );
      }
      return const ProviderScope(child: ChargeMyApp());
    },
  );
}

class _StartupLoadingApp extends StatelessWidget {
  const _StartupLoadingApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 64, color: Colors.teal.shade700),
            const SizedBox(height: 14),
            const Text(
              'ChargeMY',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Connecting to ChargeMY services...'),
          ],
        ),
      ),
    ),
  );
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, this.onRetry, super.key});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 16),
              const Text(
                'ChargeMY could not connect to Supabase.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
