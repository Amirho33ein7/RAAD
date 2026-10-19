import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ProfileApiException implements Exception {
  const ProfileApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Typed, testable boundary around the unofficial profile provider.
class CodmProfileService {
  CodmProfileService({
    required this.baseUrl,
    required this.useBackend,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final bool useBackend;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  // Only keep documented public fields. Providers may return either the older
  // flat schema or the newer nested { level: { current }, rank: {...} } shape.
  static const allowedFields = <String>{
    'nickname',
    'level',
    'picUrl',
    'avatarUrl',
    'rankClass',
    'customReadableMpRank',
    'customMpRankImageUrl',
    'rating',
    'shortId',
    'country',
    'countryCode',
    'countryId',
    'customLevelImageUrl',
    'type',
    'result',
  };

  Future<Map<String, dynamic>> fetchProfile(String input) async {
    final query = input.trim();
    if (query.isEmpty) {
      throw const ProfileApiException('نام یا شناسهٔ بازیکن را وارد کن.');
    }
    if (query.length > 80 || query.runes.any((rune) => rune < 32 || rune == 127)) {
      throw const ProfileApiException('نام یا شناسه معتبر نیست.');
    }

    final uri = _buildUri(query);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw const ProfileApiException('پاسخ سرویس بیش از حد طول کشید. دوباره تلاش کن.');
    } on http.ClientException {
      throw const ProfileApiException('ارتباط با سرویس پروفایل برقرار نشد.');
    }

    if (response.statusCode == 404) {
      throw const ProfileApiException(
        'پروفایلی پیدا نشد یا سرویس آن را ارائه نمی‌کند.',
        statusCode: 404,
      );
    }
    if (response.statusCode == 429) {
      throw const ProfileApiException(
        'سرویس درخواست‌های زیادی دریافت کرده؛ کمی بعد دوباره تلاش کن.',
        statusCode: 429,
      );
    }
    if (response.statusCode >= 500) {
      throw ProfileApiException(
        'سرویس پروفایل موقتاً در دسترس نیست (HTTP ' + response.statusCode.toString() + ').',
        statusCode: response.statusCode,
      );
    }

    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode != 200) {
        throw ProfileApiException(
          'سرویس پروفایل پاسخ خطا داد (HTTP ' + response.statusCode.toString() + ').',
          statusCode: response.statusCode,
        );
      }
      throw const ProfileApiException('پاسخ سرویس JSON معتبر نیست.');
    }

    if (response.statusCode != 200) {
      final detail = body is Map ? (body['detail'] ?? body['message']) : null;
      throw ProfileApiException(
        detail?.toString() ?? 'سرویس پروفایل پاسخ خطا داد (HTTP ' + response.statusCode.toString() + ').',
        statusCode: response.statusCode,
      );
    }
    if (body is! Map) {
      throw const ProfileApiException('ساختار پاسخ سرویس معتبر نیست.');
    }

    if (!useBackend && body['success'] == false) {
      throw ProfileApiException(
        body['message']?.toString() ?? 'سرویس نتوانست این پروفایل را پیدا کند.',
      );
    }

    final dynamic candidate = useBackend
        ? body
        : (body['data'] ?? body['user'] ?? body['profile'] ?? body);
    if (candidate is! Map) {
      throw const ProfileApiException('دادهٔ پروفایل در پاسخ سرویس وجود ندارد.');
    }

    final candidateMap = Map<String, dynamic>.from(candidate);
    final result = <String, dynamic>{};
    for (final key in allowedFields) {
      final value = candidateMap[key];
      if (value != null && value is! Map && value is! List) {
        result[key] = value;
      }
    }

    // Normalize only fields that are explicitly present; never invent stats.
    final levelValue = candidateMap['level'];
    if (levelValue is Map && levelValue['current'] != null) {
      result['level'] = levelValue['current'];
    }
    final rankValue = candidateMap['rank'];
    if (rankValue is Map) {
      if (result['customReadableMpRank'] == null &&
          rankValue['multiplayerRank'] != null) {
        result['customReadableMpRank'] = rankValue['multiplayerRank'];
      }
      if (result['rankClass'] == null && rankValue['class'] != null) {
        result['rankClass'] = rankValue['class'];
      }
      if (result['rating'] == null && rankValue['rating'] != null) {
        result['rating'] = rankValue['rating'];
      }
    }
    if (result['country'] == null && result['countryCode'] != null) {
      result['country'] = result['countryCode'];
    }
    if (result['picUrl'] == null && result['avatarUrl'] != null) {
      result['picUrl'] = result['avatarUrl'];
    }
    result.remove('countryCode');
    result.remove('avatarUrl');
    result.remove('type');
    result.remove('result');

    if (result.isEmpty) {
      throw const ProfileApiException('هیچ فیلد قابل‌نمایشی در پاسخ وجود ندارد.');
    }

    result['data_source'] = 'unofficial';
    final timestamp = body['retrieved_at_unix'];
    result['retrieved_at_unix'] =
        timestamp is num ? timestamp : DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (useBackend && body['cache'] != null) result['cache'] = body['cache'];
    return result;
  }

  Uri _buildUri(String query) {
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !const {'http', 'https'}.contains(base.scheme)) {
      throw const ProfileApiException('آدرس سرویس پروفایل معتبر نیست.');
    }
    if (useBackend) {
      return base.resolve('/api/v1/codm/profile').replace(
        queryParameters: {'q': query},
      );
    }
    return base.resolve('/user/' + Uri.encodeComponent(query));
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
