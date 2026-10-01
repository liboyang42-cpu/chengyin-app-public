/// Origin for local failures in the journey/leader root screens only.
/// A supplied server value is preserved even when identical to the fallback.
enum PlayRootOperation { ending, completedJourneys, teamProgress, teamAction }

class PlayRootFailure implements Exception {
  const PlayRootFailure(this.operation, this.message, {required this.hasServerMessage});
  final PlayRootOperation operation;
  final String message;
  final bool hasServerMessage;

  factory PlayRootFailure.response(
    PlayRootOperation operation,
    Object? message,
    String fallback,
  ) => PlayRootFailure(operation, message?.toString() ?? fallback,
      hasServerMessage: message != null);

  @override
  String toString() => 'Exception: $message';
}
