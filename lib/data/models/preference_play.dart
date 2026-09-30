import 'checkin_models.dart';

enum PreferenceStepType { single, discard }

class PreferenceOption {
  const PreferenceOption({required this.key, required this.text});

  final String key;
  final String text;

  static PreferenceOption? fromJson(Object? value) {
    final Map<String, dynamic>? json = _map(value);
    if (json == null) return null;
    final String key = _text(json['key']);
    final String text = _text(json['text']);
    if (key.isEmpty || text.isEmpty) return null;
    return PreferenceOption(key: key, text: text);
  }
}

class PreferenceStep {
  const PreferenceStep({
    required this.key,
    required this.type,
    required this.title,
    required this.options,
  });

  final String key;
  final PreferenceStepType type;
  final String title;
  final List<PreferenceOption> options;

  static PreferenceStep? fromJson(Object? value) {
    final Map<String, dynamic>? json = _map(value);
    if (json == null) return null;
    final String key = _text(json['key']);
    final String title = _text(json['title']);
    final PreferenceStepType? type = switch (_text(json['type'])) {
      'single' => PreferenceStepType.single,
      'discard' => PreferenceStepType.discard,
      _ => null,
    };
    final List<PreferenceOption> options = _list(json['options'])
        .map(PreferenceOption.fromJson)
        .whereType<PreferenceOption>()
        .toList(growable: false);
    if (key.isEmpty || title.isEmpty || type == null || options.length < 2) {
      return null;
    }
    return PreferenceStep(key: key, type: type, title: title, options: options);
  }
}

class PreferenceInheritedTag {
  const PreferenceInheritedTag({
    required this.id,
    required this.tagCode,
    required this.tagValue,
    this.status,
  });

  final int id;
  final String tagCode;
  final String tagValue;
  final int? status;

  static PreferenceInheritedTag? fromJson(Object? value) {
    final Map<String, dynamic>? json = _map(value);
    if (json == null) return null;
    final int? id = _int(json['id']);
    final String tagCode = _text(json['tagCode']);
    final String tagValue = _text(json['tagValue']);
    if (id == null || id <= 0 || tagCode.isEmpty || tagValue.isEmpty) {
      return null;
    }
    return PreferenceInheritedTag(
      id: id,
      tagCode: tagCode,
      tagValue: tagValue,
      status: _int(json['status']),
    );
  }
}

class PreferenceTagDisclosure {
  const PreferenceTagDisclosure({
    required this.purpose,
    required this.recipientLabel,
    required this.revocable,
  });

  final String purpose;
  final String recipientLabel;
  final bool revocable;

  static PreferenceTagDisclosure? fromJson(Object? value) {
    final Map<String, dynamic>? json = _map(value);
    if (json == null) return null;
    final String purpose = _text(json['purpose']);
    final String recipientLabel = _text(json['recipientLabel']);
    if (purpose.isEmpty || recipientLabel.isEmpty) return null;
    return PreferenceTagDisclosure(
      purpose: purpose,
      recipientLabel: recipientLabel,
      revocable: _bool(json['revocable']),
    );
  }
}

class PreferenceQuestionnaire {
  const PreferenceQuestionnaire({
    required this.nodeId,
    required this.steps,
    required this.inheritedTags,
    this.tiebreak,
  });

  final int nodeId;
  final List<PreferenceStep> steps;
  final PreferenceStep? tiebreak;
  final List<PreferenceInheritedTag> inheritedTags;

  factory PreferenceQuestionnaire.fromJson(Map<String, dynamic> json) {
    return PreferenceQuestionnaire(
      nodeId: _int(json['nodeId']) ?? 0,
      steps: _list(json['steps'])
          .map(PreferenceStep.fromJson)
          .whereType<PreferenceStep>()
          .toList(growable: false),
      tiebreak: PreferenceStep.fromJson(json['tiebreak']),
      inheritedTags: _list(json['inheritedTags'])
          .map(PreferenceInheritedTag.fromJson)
          .whereType<PreferenceInheritedTag>()
          .toList(growable: false),
    );
  }
}

class PreferenceEvaluation {
  const PreferenceEvaluation({
    required this.resultCode,
    required this.title,
    required this.body,
    required this.nextStep,
    required this.nextStepDays,
    required this.choices,
  });

  final String resultCode;
  final String title;
  final String body;
  final String nextStep;
  final int nextStepDays;
  final List<String> choices;

  static PreferenceEvaluation? fromJson(Object? value) {
    final Map<String, dynamic>? json = _map(value);
    if (json == null) return null;
    final String resultCode = _text(json['resultCode']);
    final String title = _text(json['title']);
    final String body = _text(json['body']);
    final String nextStep = _text(json['nextStep']);
    if (resultCode.isEmpty || title.isEmpty || body.isEmpty) return null;
    return PreferenceEvaluation(
      resultCode: resultCode,
      title: title,
      body: body,
      nextStep: nextStep,
      nextStepDays: _int(json['nextStepDays']) ?? 0,
      choices: _list(json['choices'])
          .map(_text)
          .where((String choice) => choice.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class PreferenceSubmission {
  const PreferenceSubmission({
    required this.needsTiebreak,
    this.tiebreak,
    this.evaluation,
    this.progress,
    this.pendingTag,
    this.tagDisclosure,
    this.availableTagValues = const <String>[],
  });

  final bool needsTiebreak;
  final PreferenceStep? tiebreak;
  final PreferenceEvaluation? evaluation;
  final CheckinReward? progress;
  final PreferenceInheritedTag? pendingTag;
  final PreferenceTagDisclosure? tagDisclosure;
  final List<String> availableTagValues;

  factory PreferenceSubmission.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? progress = _map(json['progress']);
    return PreferenceSubmission(
      needsTiebreak: _bool(json['needsTiebreak']),
      tiebreak: PreferenceStep.fromJson(json['tiebreak']),
      evaluation: PreferenceEvaluation.fromJson(json['evaluation']),
      progress: progress == null ? null : CheckinReward.fromJson(progress),
      pendingTag: PreferenceInheritedTag.fromJson(json['pendingTag']),
      tagDisclosure: PreferenceTagDisclosure.fromJson(json['tagDisclosure']),
      availableTagValues: _list(json['availableTagValues'])
          .map(_text)
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }
}

Map<String, dynamic>? _map(Object? value) {
  if (value is! Map) return null;
  return <String, dynamic>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      entry.key.toString(): entry.value,
  };
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

String _text(Object? value) => value?.toString().trim() ?? '';

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value));

bool _bool(Object? value) =>
    value == true || value == 1 || value == '1' || value == 'true';
