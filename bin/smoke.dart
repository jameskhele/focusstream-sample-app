import 'dart:async';
import 'dart:io';
import 'package:dartstream_client/dartstream_client.dart';

int _passes = 0;
int _fails = 0;

void main(List<String> args) async {
  final env = Platform.environment;
  
  final apiKey = env['FIREBASE_API_KEY'];
  final email = env['TEST_EMAIL'];
  final password = env['TEST_PASSWORD'];

  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('FATAL: FIREBASE_API_KEY not set. See .env.example.');
    exit(2);
  }
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    stderr.writeln('FATAL: TEST_EMAIL / TEST_PASSWORD not set. See .env.example.');
    exit(2);
  }

  final authHost = env['API_AUTH'] ?? 'https://dev-apiauth.dartstream.io';
  final platformHost = env['API_PLATFORM'] ?? 'https://dev-apiplatform.dartstream.io';
  final experienceHost = env['API_EXPERIENCE'] ?? 'https://dev-apiexperience.dartstream.io';
  final reactiveHost = env['API_REACTIVE'] ?? 'https://dev-apireactive.dartstream.io';
  final persistenceHost = env['API_PERSISTENCE'] ?? 'https://dev-apipersistence.dartstream.io';
  final billingHost = env['API_BILLING'] ?? 'https://dev-apibilling.dartstream.io';

  print('== FocusStream E2E SDK smoke ==');
  print('  auth        : $authHost');
  print('  platform    : $platformHost');
  print('  experience  : $experienceHost');
  print('  reactive    : $reactiveHost');
  print('  persistence : $persistenceHost');
  print('  user        : $email');
  print('');

  final config = DartStreamConfig(
    authBaseUrl: Uri.parse(authHost),
    platformBaseUrl: Uri.parse(platformHost),
    experienceBaseUrl: Uri.parse(experienceHost),
    reactiveBaseUrl: Uri.parse(reactiveHost),
    persistenceBaseUrl: Uri.parse(persistenceHost),
    billingBaseUrl: Uri.parse(billingHost),
    firebaseApiKey: apiKey,
  );

  final client = DartStreamClient(config: config);
  DartStreamSession? session;
  DartStreamClient? sdkClient;

  await _step('Firebase Authentication + Onboarding', () async {
    DartStreamFirebaseSession firebaseSession;
    try {
      firebaseSession = await client.signInWithEmailPassword(
        email: email,
        password: password,
      );
      print('   [PASS] Firebase sign-in successful');
    } catch (e) {
      print('   Sign-in failed ($e) — attempting to sign up');
      firebaseSession = await client.createEmailPasswordSession(
        email: email,
        password: password,
      );
      print('   [PASS] Firebase sign-up successful');
    }
    session = await client.onboardFirebaseSession(firebaseSession);
    sdkClient = client.withSession(session!);
    return {
      'userId': session!.userId,
      'tenantId': session!.tenantId,
      'email': session!.email,
    };
  });

  if (session == null || sdkClient == null) {
    print('   [FAIL] Could not establish session; aborting downstream calls.');
    _fails++;
    _summary();
    exit(1);
  }

  await _step('GET  /api/v1/auth/me', () async {
    return await sdkClient!.auth.me();
  });

  await _step('GET  /api/v1/platform/feature-flags', () async {
    return await sdkClient!.platform.featureFlags(session!);
  });

  const scope = DartStreamScope(
    projectId: 'focusstream',
    environmentId: 'development',
  );

  await _step('GET  /api/v1/experience/profiles/me', () async {
    return await sdkClient!.experience.profile(session!, scope: scope);
  });

  await _step('POST /api/v1/experience/cloud-save/snapshot', () async {
    return await sdkClient!.experience.saveCloudSave(
      session!,
      scope: scope,
      slotKey: 'focusstream',
      payload: {
        'tasks': [],
        'completedCount': 5,
        'focusSessions': 10,
        'lifetimeFocusMinutes': 250,
        'themeName': 'Default Blue',
      },
    );
  });

  await _step('GET  /api/v1/experience/cloud-save/snapshot', () async {
    return await sdkClient!.experience.loadCloudSave(
      session!,
      scope: scope,
      slotKey: 'focusstream',
    );
  });

  await _step('GET  /api/v1/experience/inventory/items', () async {
    return await sdkClient!.experience.inventory(session!, scope: scope);
  });

  await _step('POST /api/v1/reactive/events/log', () async {
    await sdkClient!.reactive.trackEvent(
      session!,
      eventType: 'focus.session.completed',
      payload: {'duration_minutes': 25, 'source': 'e2e-smoke'},
    );
    return {'status': 'logged'};
  });

  await _step('GET  /api/v1/reactive/streaming/channels', () async {
    return await sdkClient!.reactive.streamingChannels(session!);
  });

  await _step('GET  /api/v1/persistence/database', () async {
    return await sdkClient!.persistence.list('/database/', session: session!);
  });

  _summary();
  exit(_fails == 0 ? 0 : 1);
}

Future<void> _step(
  String label,
  Future<dynamic> Function() action, {
  void Function(dynamic result)? onResult,
}) async {
  print('-- $label --');
  try {
    final stopwatch = Stopwatch()..start();
    final result = await action().timeout(const Duration(seconds: 15));
    stopwatch.stop();
    _passes++;
    print('   [PASS] $label -> success in ${stopwatch.elapsedMilliseconds}ms');
    if (result != null) {
      final excerpt = _excerpt(result.toString());
      if (excerpt.isNotEmpty) print('   result: $excerpt');
    }
    onResult?.call(result);
  } catch (e) {
    _fails++;
    print('   [FAIL] $label -> exception: $e');
  }
}

String _excerpt(String body) {
  final trimmed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return '';
  return trimmed.length > 180 ? '${trimmed.substring(0, 180)}...' : trimmed;
}

void _summary() {
  print('');
  print('== Summary: $_passes pass, $_fails fail ==');
}
