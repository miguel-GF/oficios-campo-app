import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'integrity.dart';
import 'session.dart';

class AiQuoteLine {
  const AiQuoteLine({
    required this.concept,
    required this.quantity,
    required this.unitPriceCents,
  });
  final String concept;
  final double quantity;
  final int unitPriceCents;
}

class AiQuoteDraft {
  const AiQuoteDraft({
    required this.clientName,
    required this.notes,
    required this.lines,
  });
  final String clientName, notes;
  final List<AiQuoteLine> lines;
}

class AiEmailRequired implements Exception {}

class AiApiException implements Exception {
  const AiApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiApi {
  AiApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _storage = FlutterSecureStorage();
  static const _installationKey = 'jale.installation.id.v1';
  static const _pendingKey = 'jale.ai.pending.v1';
  static const _responseKey = 'jale.ai.response.v1';

  static bool get isConfigured => jaleApiUrl.isNotEmpty;
  static bool get authConfigured => AuthService.instance.configured;

  static String _uuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<String> installationId() async {
    final current = await _storage.read(key: _installationKey);
    if (current != null && current.length >= 20) return current;
    final created = '${_uuid()}-${_uuid()}';
    await _storage.write(key: _installationKey, value: created);
    return created;
  }

  Future<AiQuoteDraft> interpret({
    required String transcript,
    required String trade,
    String clientHint = '',
  }) async {
    if (!isConfigured) {
      throw const AiApiException(
        'La IA aún no está conectada en esta compilación.',
      );
    }
    final installationId = await AiApi.installationId();
    final fingerprint = base64UrlEncode(
      utf8.encode('$transcript\u0000$trade\u0000$clientHint'),
    );
    final cachedRaw = await _storage.read(key: _responseKey);
    if (cachedRaw != null) {
      try {
        final cached = Map<String, dynamic>.from(jsonDecode(cachedRaw) as Map);
        if (cached['fingerprint'] == fingerprint) {
          await _storage.delete(key: _responseKey);
          return aiQuoteDraftFromJson(
            Map<String, dynamic>.from(cached['quote'] as Map),
          );
        }
      } catch (_) {
        await _storage.delete(key: _responseKey);
      }
    }
    var idempotencyKey = _uuid();
    final request = <String, dynamic>{
      'transcript': transcript,
      'trade': trade,
      'client_hint': clientHint,
      'installation_id': installationId,
      'request_id': idempotencyKey,
    };
    final pendingRaw = await _storage.read(key: _pendingKey);
    if (pendingRaw != null) {
      try {
        final pending = Map<String, dynamic>.from(
          jsonDecode(pendingRaw) as Map,
        );
        if (pending['fingerprint'] == fingerprint &&
            pending['request'] is Map) {
          request
            ..clear()
            ..addAll(Map<String, dynamic>.from(pending['request'] as Map));
          idempotencyKey = request['request_id'] as String;
        }
      } catch (_) {
        await _storage.delete(key: _pendingKey);
      }
    }
    await _storage.write(
      key: _pendingKey,
      value: jsonEncode({'fingerprint': fingerprint, 'request': request}),
    );
    final body = jsonEncode(request);
    final proof = await PlayIntegrityService.instance.proofForBody(body);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Installation-ID': installationId,
      'Idempotency-Key': idempotencyKey,
      'X-Jale-Distribution': jaleDistribution,
    };
    if (proof != null) {
      headers['X-Play-Integrity'] = proof.token;
      headers['X-Request-Hash'] = proof.requestHash;
    }
    headers.addAll(await AuthService.instance.authorizedHeaders());
    final response = await _client
        .post(
          Uri.parse(
            '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/quotes/interpret',
          ),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 25));
    Map<String, dynamic> payload = const {};
    try {
      payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      // A proxy can return an HTML/plain-text error; keep the user in manual mode.
    }
    final detail = payload['detail'];
    if (response.statusCode == 401 && detail == 'EMAIL_REQUIRED') {
      await _storage.delete(key: _pendingKey);
      throw AiEmailRequired();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (!(response.statusCode == 409 && detail == 'REQUEST_IN_PROGRESS')) {
        await _storage.delete(key: _pendingKey);
      }
      throw AiApiException(switch (detail) {
        'AI_LIMIT_REACHED' => 'Ya usaste tus cotizaciones con IA de este mes.',
        'RATE_LIMITED' =>
          'Espera un momento antes de volver a intentar la cotización.',
        'REQUEST_TOO_LARGE' =>
          'El dictado es demasiado largo. Intenta resumirlo un poco.',
        'INTEGRITY_REQUIRED' || 'INTEGRITY_INVALID' || 'DEVICE_UNTRUSTED' =>
          'No pudimos comprobar esta instalación. Instala la versión oficial de Jale.',
        'FAIR_USE_REVIEW' =>
          'Pausamos el uso para proteger tu cuenta. Escríbenos para revisarlo.',
        'AI_UNAVAILABLE' =>
          'La IA no pudo interpretar el dictado. Tu crédito no se gastó.',
        _ => 'No pudimos preparar la cotización. Intenta otra vez.',
      });
    }
    final rawQuote = payload['quote'];
    if (rawQuote is! Map) {
      throw const AiApiException(
        'La IA respondió algo incompleto. Puedes continuar de forma manual.',
      );
    }
    final quote = Map<String, dynamic>.from(rawQuote);
    await _storage.write(
      key: _responseKey,
      value: jsonEncode({'fingerprint': fingerprint, 'quote': quote}),
    );
    await _storage.delete(key: _pendingKey);
    await _storage.delete(key: _responseKey);
    return aiQuoteDraftFromJson(quote);
  }

  Future<void> syncAccount() async {
    if (!isConfigured || !AuthService.instance.signedIn) return;
    final token = await AuthService.instance.accessToken();
    if (token == null) return;
    await _client
        .get(
          Uri.parse('${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/account'),
          headers: {
            'X-Installation-ID': await installationId(),
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 10));
  }
}

AiQuoteDraft aiQuoteDraftFromJson(Map<String, dynamic> quote) {
  final rawLines = quote['lines'];
  if (rawLines is! List || rawLines.isEmpty || rawLines.length > 30) {
    throw const AiApiException('La IA no devolvió conceptos válidos.');
  }
  final lines = <AiQuoteLine>[];
  for (final raw in rawLines) {
    if (raw is! Map) {
      throw const AiApiException('La IA devolvió un concepto incompleto.');
    }
    final value = Map<String, dynamic>.from(raw);
    final concept = (value['concept'] as String? ?? '').trim();
    final quantity = (value['quantity'] as num?)?.toDouble();
    final unitPriceCents = (value['unit_price_cents'] as num?)?.toInt();
    if (concept.length < 2 ||
        concept.length > 160 ||
        quantity == null ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity > 100000 ||
        unitPriceCents == null ||
        unitPriceCents < 0 ||
        unitPriceCents > 1000000000) {
      throw const AiApiException('La IA devolvió un concepto incompleto.');
    }
    lines.add(
      AiQuoteLine(
        concept: concept,
        quantity: quantity,
        unitPriceCents: unitPriceCents,
      ),
    );
  }
  return AiQuoteDraft(
    clientName: (quote['client_name'] as String? ?? '').trim(),
    notes: (quote['notes'] as String? ?? '').trim(),
    lines: lines,
  );
}
