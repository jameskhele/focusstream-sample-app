import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dartstream_client/dartstream_client.dart';

void main() {
  group('DartStreamClient Tests', () {
    const idToken = 'mock-id-token';

    test('onboardFirebaseIdToken success (200)', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/signup');
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'test-user-123',
              'tenant_id': 'test-tenant-456',
            }
          }),
          200,
        );
      });

      final client = DartStreamClient(
        config: DartStreamConfig.dev(firebaseApiKey: 'mock-firebase-key'),
        httpClient: mockClient,
      );
      final session = await client.auth.onboardFirebaseIdToken(idToken);
      expect(session.userId, 'test-user-123');
      expect(session.tenantId, 'test-tenant-456');
    });

    test('onboardFirebaseIdToken 409 conflict fallback to login', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          expect(request.url.path, '/api/v1/auth/signup');
          return http.Response('Conflict', 409);
        } else {
          expect(request.url.path, '/api/v1/auth/login');
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'test-user-123',
                'tenant_id': 'test-tenant-456',
              }
            }),
            200,
          );
        }
      });

      final client = DartStreamClient(
        config: DartStreamConfig.dev(firebaseApiKey: 'mock-firebase-key'),
        httpClient: mockClient,
      );
      final session = await client.auth.onboardFirebaseIdToken(idToken);
      expect(session.userId, 'test-user-123');
      expect(session.tenantId, 'test-tenant-456');
      expect(callCount, 2);
    });

    test('loadCloudSave returns null on 404', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/experience/cloud-save/snapshot');
        expect(request.method, 'GET');
        return http.Response('Not Found', 404);
      });

      final client = DartStreamClient(
        config: DartStreamConfig.dev(firebaseApiKey: 'mock-firebase-key'),
        httpClient: mockClient,
      );
      final session = const DartStreamSession(
        idToken: idToken,
        userId: 'user',
        tenantId: 'tenant',
        raw: {},
      );
      final result = await client.experience.loadCloudSave(
        session,
        scope: const DartStreamScope(
          projectId: 'project',
          environmentId: 'development',
        ),
        slotKey: 'slot',
      );
      expect(result, isNull);
    });
  });
}
