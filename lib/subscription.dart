import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai.dart';
import 'session.dart';

const cacheKey = 'jale.pro.entitlement.v4';

bool entitlementBelongsToAccount(
  String? cachedAccountHash,
  String? currentAccountHash,
) =>
    currentAccountHash != null &&
    currentAccountHash.isNotEmpty &&
    cachedAccountHash == currentAccountHash;

class JalePlan {
  const JalePlan({required this.basePlanId, required this.price});

  final String basePlanId;
  final String price;
}

class SubscriptionController extends ChangeNotifier {
  SubscriptionController() {
    AuthService.instance.addListener(_authChanged);
    _init();
  }

  bool isPro = false;
  bool loading = true;
  bool connected = false;
  String? error;
  DateTime? verifiedAt;
  DateTime? expiresAt;
  List<JalePlan> plans = [];

  bool get hasAccount => AuthService.instance.signedIn;
  bool get canPurchase => jaleDistribution == 'direct';

  Future<String?> _currentAccountHash() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return null;
    final digest = await Sha256().hash(utf8.encode(userId));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _authChanged() async {
    if (!hasAccount) {
      await _clearCachedEntitlement();
    }
    await refresh();
  }

  Future<void> _init() async {
    await _loadCache();
    await refresh();
    loading = false;
    notifyListeners();
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null) return;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final currentHash = await _currentAccountHash();
      if (!entitlementBelongsToAccount(
        value['account_hash'] as String?,
        currentHash,
      )) {
        await _clearCachedEntitlement();
        return;
      }
      verifiedAt = DateTime.tryParse(value['verified_at'] as String? ?? '');
      expiresAt = DateTime.tryParse(value['expires_at'] as String? ?? '');
      final withinOfflineGrace =
          verifiedAt != null &&
          DateTime.now().toUtc().difference(verifiedAt!.toUtc()) <
              const Duration(days: 3);
      isPro =
          value['active'] == true &&
          withinOfflineGrace &&
          (expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc()));
    } catch (_) {
      await _clearCachedEntitlement();
    }
  }

  Future<void> _clearCachedEntitlement() async {
    isPro = false;
    verifiedAt = null;
    expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
    notifyListeners();
  }

  Future<void> _saveEntitlement(bool active, DateTime? expiry) async {
    final accountHash = await _currentAccountHash();
    if (accountHash == null) {
      await _clearCachedEntitlement();
      return;
    }
    isPro = active;
    verifiedAt = DateTime.now().toUtc();
    expiresAt = expiry;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      cacheKey,
      jsonEncode({
        'active': active,
        'account_hash': accountHash,
        'verified_at': verifiedAt!.toIso8601String(),
        'expires_at': expiry?.toIso8601String(),
      }),
    );
    notifyListeners();
  }

  Future<void> refresh() async {
    if (jaleApiUrl.isEmpty) {
      connected = false;
      notifyListeners();
      return;
    }
    try {
      if (canPurchase) {
        final plansResponse = await http
            .get(
              Uri.parse(
                '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/billing/plans',
              ),
            )
            .timeout(const Duration(seconds: 12));
        if (plansResponse.statusCode == 200) {
          final values = jsonDecode(plansResponse.body) as List;
          plans = values.map((raw) {
            final value = Map<String, dynamic>.from(raw as Map);
            final cents = (value['unit_amount'] as num).toInt();
            final currency = value['currency'] as String? ?? 'MXN';
            return JalePlan(
              basePlanId: value['id'] as String,
              // A raw dollar avoids treating the currency sign as interpolation.
              // ignore: prefer_interpolation_to_compose_strings
              price: r'$' + (cents / 100).toStringAsFixed(2) + ' ' + currency,
            );
          }).toList();
        }
      }
      if (hasAccount) {
        final headers = await AuthService.instance.authorizedHeaders();
        headers['X-Installation-ID'] = await AiApi.installationId();
        final accountResponse = await http
            .get(
              Uri.parse(
                '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/account',
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 12));
        if (accountResponse.statusCode == 200) {
          final value = Map<String, dynamic>.from(
            jsonDecode(accountResponse.body) as Map,
          );
          await _saveEntitlement(value['is_pro'] == true, null);
        }
      } else {
        await _clearCachedEntitlement();
      }
      connected = true;
      error = null;
    } catch (_) {
      connected = false;
    }
    notifyListeners();
  }

  Future<void> buy(String basePlanId) async {
    if (!canPurchase) throw Exception('STRIPE_NOT_AVAILABLE_IN_BUILD');
    if (!hasAccount) throw Exception('EMAIL_REQUIRED');
    final headers = await AuthService.instance.authorizedHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await http
        .post(
          Uri.parse(
            '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/billing/checkout',
          ),
          headers: headers,
          body: jsonEncode({'plan': basePlanId}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('No pudimos abrir el pago seguro.');
    }
    final value = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final uri = Uri.parse(value['url'] as String);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No pudimos abrir el pago seguro.');
    }
  }

  Future<void> restore() => refresh();

  Future<void> manage() async {
    if (!canPurchase) throw Exception('STRIPE_NOT_AVAILABLE_IN_BUILD');
    if (!hasAccount) throw Exception('EMAIL_REQUIRED');
    final headers = await AuthService.instance.authorizedHeaders();
    final response = await http
        .post(
          Uri.parse(
            '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/billing/portal',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('No pudimos abrir la administración del plan.');
    }
    final value = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (!await launchUrl(
      Uri.parse(value['url'] as String),
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('No pudimos abrir la administración del plan.');
    }
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_authChanged);
    super.dispose();
  }
}
