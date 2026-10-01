/// Local response validation failures, distinct from server-owned messages.
enum AccountLocalFailureKind { playerCode, roamRevocation, merchantConsent }

class AccountLocalFailure implements Exception {
  const AccountLocalFailure(this.kind, this.message);
  final AccountLocalFailureKind kind;
  final String message;

  @override
  String toString() => 'Exception: $message';
}
