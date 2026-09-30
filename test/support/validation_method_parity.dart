/// 跨端核验方式码表的解析/对账纯函数。
///
/// ★ 与「读哪个仓的哪一份」解耦:这里只做字符串解析与逐码比较,不碰文件系统。
///   真正的跨仓读取在 `backend_repo.dart`,对账用例在
///   `validation_method_parity_test.dart`(needs-local-env)。
///   这样即便 CI 上没有兄弟仓,这些纯逻辑仍能在 CI 里被单测覆盖。
library;

/// 小程序真源文件(相对后端仓根)。
const String kXcxSourcePath =
    'chengyinhub-xcx/utils/validation-method-labels.js';

/// 从小程序真源里抠出 `VALIDATION_METHOD_LABELS = { ... }` 这张表。
/// 只认 `数字: '中文'` 字面量,不 eval —— 解析失败要显式报错,不能静默空表。
Map<int, String> parseXcxLabels(String source) {
  final RegExpMatch? block = RegExp(
    r'VALIDATION_METHOD_LABELS\s*=\s*\{([\s\S]*?)\};',
  ).firstMatch(source);
  if (block == null) {
    throw const FormatException('小程序真源结构变了,解析不到码表');
  }
  final Map<int, String> out = <int, String>{};
  for (final RegExpMatch m in RegExp(
    r"(\d+)\s*:\s*'([^']*)'",
  ).allMatches(block.group(1)!)) {
    out[int.parse(m.group(1)!)] = m.group(2)!;
  }
  if (out.isEmpty) {
    throw const FormatException('解析到空码表,别让对账悄悄通过');
  }
  return out;
}

/// 逐码对账,返回不一致项(空表 = 完全一致)。抽成纯函数才好做负控。
List<String> validationLabelDrift(Map<int, String> app, Map<int, String> xcx) {
  final List<int> codes = <int>{...app.keys, ...xcx.keys}.toList()..sort();
  return <String>[
    for (final int code in codes)
      if (app[code] != xcx[code]) '$code: app=${app[code]} xcx=${xcx[code]}',
  ];
}
