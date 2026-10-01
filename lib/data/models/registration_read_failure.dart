/// Origin of player registration/ticket read errors. A supplied server message
/// remains server-owned even when its text equals an app fallback.
enum RegistrationReadKind { activityTickets, routeTickets, orders, detail, dynamicCode, quote, paymentReadiness, paymentParameters, completion, cancellation }

class RegistrationReadFailure implements Exception {
  const RegistrationReadFailure(this.kind, this.message, {required this.hasServerMessage});
  final RegistrationReadKind kind;
  final String message;
  final bool hasServerMessage;

  factory RegistrationReadFailure.fromResponse(
    RegistrationReadKind kind,
    Map<String, dynamic> body,
    String fallback,
  ) => RegistrationReadFailure(kind,
    body['msg'] is String ? body['msg'] as String : fallback,
    hasServerMessage: body['msg'] is String,
  );

  @override
  String toString() => 'Exception: $message';
}
