import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:focusstream_app/api/dartstream.dart';

void main() {
  group('DartstreamApi Client Tests', () {
    const idToken = 'mock-id-token';

    test('signup success (200)', () async {
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

      await http.runWithClient(() async {
        final api = DartstreamApi(idToken: idToken);
        final result = await api.signup();
        expect(result.userId, 'test-user-123');
        expect(result.tenantId, 'test-tenant-456');
      }, () => mockClient);
    });

    test('signup 409 conflict fallback to login', () async {
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

      await http.runWithClient(() async {
        final api = DartstreamApi(idToken: idToken);
        final result = await api.signup();
        expect(result.userId, 'test-user-123');
        expect(result.tenantId, 'test-tenant-456');
        expect(callCount, 2);
      }, () => mockClient);
    });

    test('loadSnapshot returns null on 404', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/experience/cloud-save/snapshot');
        expect(request.method, 'GET');
        return http.Response('Not Found', 404);
      });

      await http.runWithClient(() async {
        final api = DartstreamApi(idToken: idToken);
        final result = await api.loadSnapshot(
          userId: 'user',
          tenantId: 'tenant',
          slotKey: 'slot',
          projectId: 'project',
          environmentId: 'development',
        );
        expect(result, isNull);
      }, () => mockClient);
    });
  });
}
