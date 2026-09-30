import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/config_api.dart';
import 'providers.dart';

final configApiProvider = Provider<ConfigApi>((ref) {
  return ConfigApi(ref.watch(dioClientProvider));
});

final featureFlagsProvider =
    NotifierProvider<FeatureFlagsNotifier, Map<String, bool>>(
      FeatureFlagsNotifier.new,
    );

/// 后续功能块统一用 `ref.watch(featureFlagProvider('flagName'))` 读取。
final featureFlagProvider = Provider.family<bool, String>((ref, name) {
  return ref.watch(
    featureFlagsProvider.select((flags) => flags[name] ?? false),
  );
});

class FeatureFlagsNotifier extends Notifier<Map<String, bool>> {
  int _generation = 0;

  @override
  Map<String, bool> build() => const <String, bool>{};

  /// 启动拉取一次；任何请求或解析异常都回到默认全关。
  Future<void> load() async {
    final generation = ++_generation;
    state = const <String, bool>{};
    try {
      final raw = await ref.read(configApiProvider).fetchFeatures();
      if (!ref.mounted || generation != _generation) return;
      state = <String, bool>{
        for (final entry in raw.entries) entry.key: _flagOn(entry.value),
      };
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      state = const <String, bool>{};
    }
  }

  /// 登出或身份失效时立即失败关闭，防止下一账号沿用上一账号的灰度快照。
  void clear() {
    _generation += 1;
    state = const <String, bool>{};
  }
}

/// 与后端 `NpcFeatureFlags.flagOn` 同口径：true（忽略大小写）或 1 才开启。
bool _flagOn(Object? value) {
  final text = value?.toString();
  return text?.toLowerCase() == 'true' || text == '1';
}
