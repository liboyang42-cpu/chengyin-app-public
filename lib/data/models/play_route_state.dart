const Set<String> playRouteNodeStates = <String>{
  'HIDDEN',
  'DISCOVERED_LOCKED',
  'PLAYABLE',
  'COMPLETED',
};

final class PlayRouteState {
  const PlayRouteState({
    required this.routeMode,
    required this.sessionId,
    required this.status,
    required this.version,
    required this.nodeStates,
    required this.decisionLog,
    required this.lockReasons,
    this.currentNodeId,
    this.recommendedNodeId,
  });

  final String routeMode;
  final int sessionId;
  final String status;
  final int version;
  final int? currentNodeId;
  final int? recommendedNodeId;
  final Map<int, String> nodeStates;
  final List<Map<String, dynamic>> decisionLog;
  final Map<int, String> lockReasons;

  bool get isBranchGraph => routeMode == 'BRANCH_GRAPH';
  bool get active => !isBranchGraph || status == 'ACTIVE';

  String? nodeState(int nodeId) => nodeStates[nodeId];
  String? lockReason(int nodeId) => lockReasons[nodeId];
  bool nodeIsHidden(int nodeId) => nodeState(nodeId) == 'HIDDEN';
  bool nodeIsPlayable(int nodeId) => nodeState(nodeId) == 'PLAYABLE';
  bool nodeIsCompleted(int nodeId) => nodeState(nodeId) == 'COMPLETED';

  factory PlayRouteState.fromJson(Map<String, dynamic> json) {
    final String mode = '${json['routeMode'] ?? 'LINEAR'}'.trim();
    final Map<int, String> states = _stringMap(json['nodeStates']);
    final Map<int, String> reasons = _stringMap(json['lockReasons']);
    final List<Map<String, dynamic>> log = json['decisionLog'] is List
        ? (json['decisionLog'] as List<dynamic>)
              .whereType<Map>()
              .map(
                (Map<dynamic, dynamic> row) => Map<String, dynamic>.from(row),
              )
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final PlayRouteState state = PlayRouteState(
      routeMode: mode.isEmpty ? 'LINEAR' : mode,
      sessionId: _int(json['sessionId']),
      status: '${json['status'] ?? ''}'.trim(),
      version: _int(json['version']),
      currentNodeId: _nullablePositiveInt(json['currentNodeId']),
      recommendedNodeId: _nullablePositiveInt(json['recommendedNodeId']),
      nodeStates: states,
      decisionLog: log,
      lockReasons: reasons,
    );
    if (state.isBranchGraph &&
        (state.sessionId <= 0 ||
            state.status.isEmpty ||
            state.version < 0 ||
            states.isEmpty ||
            states.values.any(
              (String value) => !playRouteNodeStates.contains(value),
            ))) {
      throw const FormatException('incomplete branch route state');
    }
    return state;
  }
}

Map<int, String> _stringMap(Object? raw) {
  if (raw is! Map) return const <int, String>{};
  final Map<int, String> result = <int, String>{};
  for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
    final int? key = int.tryParse('${entry.key}');
    final String value = '${entry.value ?? ''}'.trim();
    if (key != null && key > 0 && value.isNotEmpty) result[key] = value;
  }
  return Map<int, String>.unmodifiable(result);
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

int? _nullablePositiveInt(Object? value) {
  final int parsed = _int(value);
  return parsed > 0 ? parsed : null;
}
