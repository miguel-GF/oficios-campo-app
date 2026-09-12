import 'package:test/test.dart';
import 'package:jale_app/subscription.dart';

void main() {
  test('el cache Pro solo pertenece a la cuenta que lo verificó', () {
    expect(entitlementBelongsToAccount('abc', 'abc'), isTrue);
    expect(entitlementBelongsToAccount('abc', 'otra'), isFalse);
    expect(entitlementBelongsToAccount('abc', null), isFalse);
    expect(entitlementBelongsToAccount(null, 'abc'), isFalse);
  });
}
