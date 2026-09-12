import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

const playIntegrityCloudProjectNumber = int.fromEnvironment(
  'PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
  defaultValue: 0,
);

class IntegrityProof {
  const IntegrityProof({required this.token, required this.requestHash});

  final String token;
  final String requestHash;
}

class PlayIntegrityService {
  PlayIntegrityService._();

  static const _channel = MethodChannel('mx.jale.app/play_integrity');
  static final instance = PlayIntegrityService._();

  Future<IntegrityProof?> proofForBody(String body) async {
    if (!Platform.isAndroid || playIntegrityCloudProjectNumber <= 0) {
      return null;
    }
    final digest = await Sha256().hash(utf8.encode(body));
    final requestHash = base64UrlEncode(digest.bytes).replaceAll('=', '');
    await _channel.invokeMethod<bool>('prepare', {
      'projectNumber': playIntegrityCloudProjectNumber,
    });
    final token = await _channel.invokeMethod<String>('token', {
      'requestHash': requestHash,
    });
    if (token == null || token.isEmpty) {
      throw StateError('No se pudo comprobar la instalación de Jale.');
    }
    return IntegrityProof(token: token, requestHash: requestHash);
  }
}
