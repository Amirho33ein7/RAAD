import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raad/services/codm_profile_service.dart';

void main() {
  group('CodmProfileService', () {
    test('parses documented provider wrapper and filters unknown fields', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.pathSegments, ['user', 'Player One']);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'nickname': 'Player One',
                'level': 125,
                'rating': 5432,
                'country': 'US',
                'unlistedSecret': 'must not be returned',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final profile = await service.fetchProfile('  Player One  ');
      expect(profile['nickname'], 'Player One');
      expect(profile['level'], 125);
      expect(profile['rating'], 5432);
      expect(profile['country'], 'US');
      expect(profile.containsKey('unlistedSecret'), isFalse);
      expect(profile['data_source'], 'unofficial');
      expect(profile['retrieved_at_unix'], isA<int>());
      service.close();
    });

    test('normalizes a nested profile response without inventing fields', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'nickname': 'NestedPlayer',
              'level': {'current': 76},
              'rank': {
                'class': 8,
                'multiplayerRank': 'Master II',
                'rating': 6120,
              },
              'countryCode': 'CA',
              'avatarUrl': 'https://images.example/avatar.png',
              'privateKdr': 9.99,
            },
          }),
          200,
        )),
      );

      final profile = await service.fetchProfile('NestedPlayer');
      expect(profile['nickname'], 'NestedPlayer');
      expect(profile['level'], 76);
      expect(profile['rankClass'], 8);
      expect(profile['customReadableMpRank'], 'Master II');
      expect(profile['rating'], 6120);
      expect(profile['country'], 'CA');
      expect(profile['picUrl'], 'https://images.example/avatar.png');
      expect(profile.containsKey('privateKdr'), isFalse);
      service.close();
    });

    test('rejects an unsuccessful provider response', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response(
          jsonEncode({'success': false, 'message': 'not found'}),
          200,
        )),
      );
      await expectLater(
        service.fetchProfile('Missing'),
        throwsA(isA<ProfileApiException>().having((e) => e.message, 'message', 'not found')),
      );
      service.close();
    });

    test('rejects a valid JSON object with no documented profile fields', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response(
          jsonEncode({'success': true, 'data': {'internalId': 'x'}}),
          200,
        )),
      );
      await expectLater(service.fetchProfile('Player'), throwsA(isA<ProfileApiException>()));
      service.close();
    });

    test('maps 404 and rate limiting to typed errors', () async {
      final missing = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      await expectLater(
        missing.fetchProfile('Nobody'),
        throwsA(isA<ProfileApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      missing.close();

      final limited = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response('{}', 429)),
      );
      await expectLater(
        limited.fetchProfile('Player'),
        throwsA(isA<ProfileApiException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
      limited.close();
    });

    test('parses the RAAD backend envelope and keeps cache metadata', () async {
      final service = CodmProfileService(
        baseUrl: 'https://raad.example',
        useBackend: true,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/codm/profile');
          expect(request.url.queryParameters['q'], 'Exact Player');
          return http.Response(jsonEncode({
            'nickname': 'Exact Player',
            'level': 101,
            'rating': 4010,
            'cache': 'hit',
            'data_source': 'unofficial',
            'retrieved_at_unix': 123456,
            'extraField': 'ignored',
          }), 200);
        }),
      );

      final result = await service.fetchProfile('Exact Player');
      expect(result['nickname'], 'Exact Player');
      expect(result['level'], 101);
      expect(result['cache'], 'hit');
      expect(result['retrieved_at_unix'], 123456);
      expect(result.containsKey('extraField'), isFalse);
      service.close();
    });

    test('rejects empty, control-character and overlong input before network access', () async {
      var requests = 0;
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(service.fetchProfile('  '), throwsA(isA<ProfileApiException>()));
      await expectLater(service.fetchProfile('bad\nname'), throwsA(isA<ProfileApiException>()));
      await expectLater(service.fetchProfile(List<String>.filled(81, 'x').join()), throwsA(isA<ProfileApiException>()));
      expect(requests, 0);
      service.close();
    });

    test('rejects an invalid service base URL before issuing a request', () async {
      final service = CodmProfileService(baseUrl: 'not a URL', useBackend: false);
      await expectLater(service.fetchProfile('Player'), throwsA(isA<ProfileApiException>()));
      service.close();
    });

    test('turns invalid JSON into a clear error', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response('<html>bad gateway</html>', 200)),
      );
      await expectLater(
        service.fetchProfile('Player'),
        throwsA(isA<ProfileApiException>().having((e) => e.message, 'message', contains('JSON'))),
      );
      service.close();
    });


    test('reports server errors even when the body is not JSON', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response('<html>temporarily unavailable</html>', 503)),
      );
      await expectLater(
        service.fetchProfile('Player'),
        throwsA(isA<ProfileApiException>()
          .having((e) => e.statusCode, 'statusCode', 503)
          .having((e) => e.message, 'message', contains('503'))),
      );
      service.close();
    });

    test('accepts documented fields at the response root when no wrapper exists', () async {
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        client: MockClient((_) async => http.Response(
          jsonEncode({'success': true, 'nickname': 'TopLevelPlayer'}),
          200,
        )),
      );
      final result = await service.fetchProfile('Player');
      expect(result['nickname'], 'TopLevelPlayer');
      service.close();
    });

    test('applies timeout to a stalled response', () async {
      final neverCompletes = Completer<http.Response>();
      final service = CodmProfileService(
        baseUrl: 'https://provider.example',
        useBackend: false,
        timeout: const Duration(milliseconds: 5),
        client: MockClient((_) => neverCompletes.future),
      );
      await expectLater(
        service.fetchProfile('Player'),
        throwsA(isA<ProfileApiException>().having((e) => e.message, 'message', contains('طول کشید'))),
      );
      service.close();
    });
  });
}
