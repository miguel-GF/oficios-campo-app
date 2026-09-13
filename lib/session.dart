import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const jaleApiUrl = String.fromEnvironment('JALE_API_URL');
const jaleAuthPortalUrl = String.fromEnvironment('JALE_AUTH_PORTAL_URL');
const jaleDistribution = String.fromEnvironment(
  'JALE_DISTRIBUTION',
  defaultValue: 'direct',
);
const jaleAuthRedirectUri = 'jale://auth/callback';

class AuthService extends ChangeNotifier {
  AuthService._();

  static final instance = AuthService._();
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'jale.auth.access.v1';
  static const _refreshKey = 'jale.auth.refresh.v1';
  static const _expiryKey = 'jale.auth.expiry.v1';
  static const _userKey = 'jale.auth.user.v1';
  static const _emailKey = 'jale.auth.email.v1';
  static const _verifierKey = 'jale.auth.pkce.verifier.v1';
  static const _stateKey = 'jale.auth.pkce.state.v1';

  final AppLinks _links = AppLinks();
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? userId;
  String? email;
  bool initialized = false;
  bool _refreshing = false;

  bool get configured =>
      jaleApiUrl.isNotEmpty && jaleAuthPortalUrl.startsWith('https://');
  bool get signedIn => userId != null && _refreshToken != null;

  Future<void> initialize() async {
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    _expiresAt = DateTime.tryParse(await _storage.read(key: _expiryKey) ?? '');
    userId = await _storage.read(key: _userKey);
    email = await _storage.read(key: _emailKey);
    _links.uriLinkStream.listen(
      (uri) => handleCallback(uri).catchError((_) {}),
      onError: (_) {},
    );
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) await handleCallback(initial);
    } catch (_) {
      // A failed callback must leave manual/offline mode usable.
    }
    if (signedIn) {
      try {
        await accessToken();
      } catch (_) {
        await clearLocal();
      }
    }
    initialized = true;
    notifyListeners();
  }

  static String _randomToken(int length) {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(length, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  static Future<String> _challenge(String verifier) async {
    final digest = await Sha256().hash(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> beginLogin() async {
    if (!configured) {
      throw Exception('AUTH_NOT_CONFIGURED');
    }
    final verifier = _randomToken(48);
    final state = _randomToken(32);
    await _storage.write(key: _verifierKey, value: verifier);
    await _storage.write(key: _stateKey, value: state);
    var portalBase = Uri.parse(jaleAuthPortalUrl);
    if (portalBase.path.isEmpty || portalBase.path == '/') {
      portalBase = portalBase.replace(path: '/mobile');
    }
    final portal = portalBase.replace(
      queryParameters: {
        ...portalBase.queryParameters,
        'code_challenge': await _challenge(verifier),
        'code_challenge_method': 'S256',
        'redirect_uri': jaleAuthRedirectUri,
        'state': state,
      },
    );
    if (!await launchUrl(portal, mode: LaunchMode.externalApplication)) {
      throw Exception('No pudimos abrir el acceso seguro.');
    }
  }

  Future<void> handleCallback(Uri uri) async {
    if (uri.scheme != 'jale' || uri.host != 'auth' || uri.path != '/callback') {
      return;
    }
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final expectedState = await _storage.read(key: _stateKey);
    final verifier = await _storage.read(key: _verifierKey);
    if (code == null ||
        verifier == null ||
        expectedState == null ||
        state != expectedState) {
      return;
    }
    final response = await http
        .post(
          Uri.parse(
            '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/auth/exchange',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': jaleAuthRedirectUri,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('AUTH_CODE_INVALID');
    }
    await _saveSession(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
    await _storage.delete(key: _verifierKey);
    await _storage.delete(key: _stateKey);
  }

  Future<String?> accessToken() async {
    if (!signedIn) return null;
    final safeUntil = DateTime.now().toUtc().add(const Duration(minutes: 1));
    if (_accessToken != null &&
        _expiresAt != null &&
        _expiresAt!.isAfter(safeUntil)) {
      return _accessToken;
    }
    if (_refreshing) {
      while (_refreshing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _accessToken;
    }
    _refreshing = true;
    try {
      final response = await http
          .post(
            Uri.parse(
              '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/auth/refresh',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        await clearLocal();
        return null;
      }
      await _saveSession(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
      return _accessToken;
    } finally {
      _refreshing = false;
    }
  }

  Future<Map<String, String>> authorizedHeaders() async {
    final token = await accessToken();
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }

  Future<void> _saveSession(Map<String, dynamic> value) async {
    _accessToken = value['access_token'] as String;
    _refreshToken = value['refresh_token'] as String;
    userId = value['user_id'] as String;
    email = value['email'] as String? ?? '';
    _expiresAt = DateTime.now().toUtc().add(
      Duration(seconds: (value['expires_in'] as num?)?.toInt() ?? 900),
    );
    await Future.wait([
      _storage.write(key: _accessKey, value: _accessToken),
      _storage.write(key: _refreshKey, value: _refreshToken),
      _storage.write(key: _expiryKey, value: _expiresAt!.toIso8601String()),
      _storage.write(key: _userKey, value: userId),
      _storage.write(key: _emailKey, value: email),
    ]);
    notifyListeners();
  }

  Future<void> logout() async {
    final refresh = _refreshToken;
    if (refresh != null && jaleApiUrl.isNotEmpty) {
      try {
        await http.post(
          Uri.parse(
            '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/auth/logout',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refresh}),
        );
      } catch (_) {
        // Local logout must still work without connectivity.
      }
    }
    await clearLocal();
  }

  Future<void> clearLocal() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    userId = null;
    email = null;
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _expiryKey),
      _storage.delete(key: _userKey),
      _storage.delete(key: _emailKey),
    ]);
    notifyListeners();
  }
}
