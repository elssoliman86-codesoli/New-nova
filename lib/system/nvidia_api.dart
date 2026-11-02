import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lists the chat models of the NVIDIA API catalog (OpenAI compatible).
class NvidiaApi {
  static Future<List<String>> listModels({
    required String baseUrl,
    required String key,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final request = await client.getUrl(Uri.parse('$base/models'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (key.trim().isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${key.trim()}');
      }
      final response = await request.close().timeout(const Duration(seconds: 25));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}: ${_short(body)}');
      }
      final decoded = jsonDecode(body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) throw const FormatException('Unexpected response');
      final ids = data
          .map((e) => e is Map ? e['id'] : null)
          .whereType<String>()
          .toList()
        ..sort();
      return ids;
    } finally {
      client.close(force: true);
    }
  }

  static String _short(String text) =>
      text.length > 140 ? '${text.substring(0, 140)}…' : text;

  /// Models that are clearly not chat models are hidden from the picker.
  static bool looksLikeChatModel(String id) {
    final lower = id.toLowerCase();
    const skip = ['embed', 'rerank', 'reward', 'guard', 'parse', 'clip', 'nvclip', 'vila', 'whisper', 'tts'];
    return !skip.any(lower.contains);
  }
}
