import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai.dart';
import 'integrity.dart';
import 'domain.dart';

const productId = 'jale_pro';
const cacheKey = 'jale.pro.entitlement.v3';

bool entitlementBelongsToAccount(
  String? cachedAccountHash,
  String? currentAccountHash,
) =>
    currentAccountHash != null &&
    currentAccountHash.isNotEmpty &&
    cachedAccountHash == currentAccountHash;

class JalePlan {
  const JalePlan({
    required this.basePlanId,
    required this.price,
    required this.product,
  });
  final String basePlanId, price;
  final ProductDetails product;
}

class SubscriptionController extends ChangeNotifier {
  SubscriptionController() {
    _listenAuthChanges();
    _init();
  }

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool isPro = false, loading = true, connected = false;
  String? error;
  DateTime? verifiedAt, expiresAt;
  List<ProductDetails> products = [];
  String? _accountHash;

  List<JalePlan> get plans => products.map((product) {
    var basePlan = 'monthly';
    if (product is GooglePlayProductDetails &&
        product.subscriptionIndex != null) {
      basePlan = product
          .productDetails
          .subscriptionOfferDetails![product.subscriptionIndex!]
          .basePlanId;
    }
    return JalePlan(
      basePlanId: basePlan,
      price: product.price,
      product: product,
    );
  }).toList();

  bool get hasAccount {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  int get manualQuoteLimit {
    if (!hasAccount) return firstPeriodManualQuotes;
    final createdAt = DateTime.tryParse(
      Supabase.instance.client.auth.currentUser!.createdAt,
    );
    return createdAt != null && quotaPeriod(createdAt) == quotaPeriod()
        ? firstPeriodManualQuotes
        : freeManualQuotesPerMonth;
  }

  Future<String> _accountHashFor(User user) async {
    final digest = await Sha256().hash(utf8.encode(user.id));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<String?> _currentAccountHash() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user == null ? null : _accountHashFor(user);
    } catch (_) {
      return null;
    }
  }

  Future<String> _obfuscatedAccountId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw Exception('Registra tu correo para activar Jale Pro.');
    }
    return _accountHashFor(user);
  }

  void _listenAuthChanges() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) async {
            final nextHash = await _currentAccountHash();
            if (nextHash == _accountHash) return;
            _accountHash = nextHash;
            if (nextHash == null) {
              await _clearCachedEntitlement();
            } else {
              await _loadCache();
            }
            _notify();
          });
    } catch (_) {
      // Auth is optional for the offline/manual experience.
    }
  }

  void _notify() => notifyListeners();

  Future<void> _init() async {
    try {
      await _loadCache();
      connected = await _iap.isAvailable();
      if (connected) {
        _subscription = _iap.purchaseStream.listen(
          _onPurchases,
          onError: (_) {
            error = 'No pudimos consultar Google Play.';
            _notify();
          },
        );
        final response = await _iap.queryProductDetails({productId});
        products = response.productDetails;
        if (response.error != null) error = response.error!.message;
        if (hasAccount) {
          await _iap.restorePurchases(
            applicationUserName: await _obfuscatedAccountId(),
          );
        }
      }
    } catch (_) {
      connected = false;
      products = [];
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null) return;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final currentHash = await _currentAccountHash();
      _accountHash = currentHash;
      if (!entitlementBelongsToAccount(
        value['account_hash'] as String?,
        currentHash,
      )) {
        isPro = false;
        verifiedAt = null;
        expiresAt = null;
        await prefs.remove(cacheKey);
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
      isPro = false;
      verifiedAt = null;
      expiresAt = null;
      await prefs.remove(cacheKey);
    }
  }

  Future<void> _clearCachedEntitlement() async {
    isPro = false;
    verifiedAt = null;
    expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
  }

  Future<void> _grant({required bool active, DateTime? expiry}) async {
    final accountHash = await _currentAccountHash();
    if (accountHash == null) {
      await _clearCachedEntitlement();
      return;
    }
    isPro = active;
    verifiedAt = DateTime.now().toUtc();
    expiresAt = expiry;
    _accountHash = accountHash;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      cacheKey,
      jsonEncode({
        'active': active,
        'account_hash': _accountHash,
        'verified_at': verifiedAt!.toIso8601String(),
        'expires_at': expiry?.toIso8601String(),
      }),
    );
    _notify();
  }

  Future<({bool active, DateTime? expiry})> _verify(
    PurchaseDetails purchase,
  ) async {
    if (jaleApiUrl.isEmpty || !hasAccount) {
      throw Exception('Registra tu correo para activar Jale Pro.');
    }
    final accountHash = await _currentAccountHash();
    if (accountHash == null) {
      throw Exception('Vuelve a entrar a tu cuenta.');
    }
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Vuelve a entrar a tu cuenta.');
    final body = jsonEncode({
      'product_id': purchase.productID,
      'purchase_token': purchase.verificationData.serverVerificationData,
    });
    final proof = await PlayIntegrityService.instance.proofForBody(body);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if (proof != null) {
      headers['X-Play-Integrity'] = proof.token;
      headers['X-Request-Hash'] = proof.requestHash;
    }
    final response = await http
        .post(
          Uri.parse(
            '${jaleApiUrl.replaceFirst(RegExp(r'/$'), '')}/v1/billing/google-play/verify',
          ),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'No pudimos verificar la compra. Intenta restaurarla en un momento.',
      );
    }
    if (!entitlementBelongsToAccount(
      accountHash,
      await _currentAccountHash(),
    )) {
      throw Exception('La cuenta cambió durante la verificación.');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      active: value['active'] == true,
      expiry: DateTime.tryParse(value['expires_at'] as String? ?? ''),
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    var verifiedAny = false;
    var verificationFailed = false;
    ({bool active, DateTime? expiry})? best;
    for (final purchase in purchases.where(
      (item) => item.productID == productId,
    )) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final verified = await _verify(purchase);
          verifiedAny = true;
          final expiry = verified.expiry;
          final currentBest = best;
          if (verified.active &&
              (currentBest == null ||
                  (expiry != null &&
                      (currentBest.expiry == null ||
                          expiry.isAfter(currentBest.expiry!))))) {
            best = verified;
          }
          if (verified.active && purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        } catch (exception) {
          verificationFailed = true;
          error = exception.toString().replaceFirst('Exception: ', '');
          _notify();
        }
      }
      if (purchase.status == PurchaseStatus.error) {
        error = purchase.error?.message ?? 'No se completó la compra.';
        _notify();
      }
    }
    if (verifiedAny && connected && (!verificationFailed || best != null)) {
      await _grant(active: best?.active ?? false, expiry: best?.expiry);
    }
  }

  Future<void> buy(String basePlanId) async {
    if (!hasAccount) throw Exception('EMAIL_REQUIRED');
    final plan = plans
        .where((item) => item.basePlanId == basePlanId)
        .firstOrNull;
    if (!connected || plan == null) {
      throw Exception('Este plan todavía no está disponible en Google Play.');
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: plan.product,
        applicationUserName: await _obfuscatedAccountId(),
      ),
    );
  }

  Future<void> restore() async {
    if (!connected) {
      throw Exception('Conéctate a internet para restaurar la compra.');
    }
    if (!hasAccount) throw Exception('EMAIL_REQUIRED');
    await _iap.restorePurchases(
      applicationUserName: await _obfuscatedAccountId(),
    );
  }

  Future<void> manage() async {
    final uri = Uri.parse(
      'https://play.google.com/store/account/subscriptions?sku=$productId&package=mx.jale.app',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No pudimos abrir tus suscripciones de Google Play.');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
