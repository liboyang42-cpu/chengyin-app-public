/// 工时与证据自报的纯校验函数。对齐小程序 `pages/club/edition-report/index.js`。
///
/// 拆成纯函数便于单测做负控:校验判据一旦被改松(如放过负数、放过非 64 位哈希),
/// 对应测试会先红,而不是等真机提交被后端拒。
library;

/// 校验工时输入。返回错误文案;通过返回 null。
String? hoursInputError(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '请填写非负的实际工时';
  final value = double.tryParse(trimmed);
  if (value == null || value < 0) return '请填写非负的实际工时';
  return null;
}

/// 校验证据哈希。返回错误文案;通过返回 null。
String? evidenceHashError(String raw) {
  final hash = raw.trim().toLowerCase();
  if (hash.isEmpty) return '请填写证据哈希';
  final RegExp sha256 = RegExp(r'^[0-9a-f]{64}$');
  if (!sha256.hasMatch(hash)) return '请填写 64 位 SHA-256 哈希';
  return null;
}

/// 未选期次时的提示(可恢复:选期控件就在本页顶部)。
const String kPickEditionFirst = '请先在顶部选择要报的期次';
