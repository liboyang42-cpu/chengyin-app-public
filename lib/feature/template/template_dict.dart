import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 字典项(`/api/common/dict`)。
///
/// ★★ 小程序在这条上栽过一次,注释原话:
///   「之前只回填了 listName(纯标签数组),**漏了 listName+'Data'**,
///    导致玩法难度接口失败时选择器 options 空数组、**点开没有可选项**」。
///   ⇒ 兜底必须给出**能用的完整选项**,不是一个空壳。
///
/// ⚠️ 后端注释:先读缓存、缓存没有再查库,**两条路都可能返回空列表** ——
///   那是「这个字典没有配项」,不是错误,别渲染成加载失败。
///   但**空列表也不能让选择器变空** —— 那时同样用兜底。
class DictOption {
  const DictOption({required this.value, required this.label});

  final String value;
  final String label;

  factory DictOption.fromJson(Map<String, dynamic> json) => DictOption(
        value: (json['dictValue'] ?? '').toString(),
        label: (json['dictLabel'] ?? '').toString(),
      );
}

/// 各字典的兜底选项。★ 与小程序 `toDictOptions` 的兜底同一份 ——
/// 接口挂了/没配项时照样能选,而不是点开一片空白。
const Map<String, List<String>> kDictFallback = <String, List<String>>{
  'app_template_difficulty': <String>['简易', '一般', '困难'],
  'app_template_duration': <String>['10min', '16min', '20min', '23min'],
  'app_template_players': <String>['1-2 人', '3-5 人', '6 人以上'],
};

List<DictOption> _fallbackFor(String dictType) {
  final List<String> labels = kDictFallback[dictType] ?? const <String>[];
  return <DictOption>[
    for (int i = 0; i < labels.length; i++)
      DictOption(value: '$i', label: labels[i]),
  ];
}

/// 取一个字典。**永不返回空列表**:接口失败或后端没配项时落到兜底。
///
/// ★ 这里刻意**不抛异常** —— 一个选项列表拉不到不该让整页变成错误页,
///   但也不能变成空选择器(那是"点开没有可选项"那个 bug)。
final dictProvider = FutureProvider.autoDispose
    .family<List<DictOption>, String>((Ref ref, String dictType) async {
  try {
    final rows = await ref.watch(registrationApiProvider).dict(dictType);
    final List<DictOption> opts = rows
        .map(DictOption.fromJson)
        .where((DictOption o) => o.label.trim().isNotEmpty)
        .toList();
    return opts.isEmpty ? _fallbackFor(dictType) : opts;
  } catch (_) {
    return _fallbackFor(dictType);
  }
});
