import 'dart:async';

import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/data/api/config_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConfigApi implements ConfigApi {
  _FakeConfigApi(this._response, {this.error});

  final Map<String, dynamic> _response;
  final Object? error;

  @override
  Future<Map<String, dynamic>> fetchFeatures() async {
    if (error != null) throw error!;
    return _response;
  }
}

class _ControlledConfigApi implements ConfigApi {
  final Completer<Map<String, dynamic>> response =
      Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> fetchFeatures() => response.future;
}

class _QueuedConfigApi implements ConfigApi {
  final List<Completer<Map<String, dynamic>>> responses =
      <Completer<Map<String, dynamic>>>[];

  @override
  Future<Map<String, dynamic>> fetchFeatures() {
    final response = Completer<Map<String, dynamic>>();
    responses.add(response);
    return response.future;
  }
}

ProviderContainer _container(_FakeConfigApi api) {
  final container = ProviderContainer(
    overrides: [configApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('启动前所有开关默认关闭', () {
    final container = _container(_FakeConfigApi(<String, dynamic>{}));

    expect(container.read(featureFlagProvider('roamNpcEvent')), isFalse);
    expect(container.read(featureFlagProvider('unknownFlag')), isFalse);
  });

  test('仅 true（忽略大小写）或 1 开启，其余值全部关闭', () async {
    final container = _container(
      _FakeConfigApi(<String, dynamic>{
        'boolTrue': true,
        'lowerTrue': 'true',
        'upperTrue': 'TRUE',
        'intOne': 1,
        'stringOne': '1',
        'boolFalse': false,
        'paddedTrue': ' true ',
        'otherNumber': 2,
        'nullValue': null,
      }),
    );

    await container.read(featureFlagsProvider.notifier).load();

    for (final key in <String>[
      'boolTrue',
      'lowerTrue',
      'upperTrue',
      'intOne',
      'stringOne',
    ]) {
      expect(container.read(featureFlagProvider(key)), isTrue, reason: key);
    }
    for (final key in <String>[
      'boolFalse',
      'paddedTrue',
      'otherNumber',
      'nullValue',
    ]) {
      expect(container.read(featureFlagProvider(key)), isFalse, reason: key);
    }
  });

  test('网络或解析异常保持全关且不向启动流程抛错', () async {
    for (final error in <Object>[
      Exception('network'),
      const FormatException('bad response'),
    ]) {
      final container = _container(
        _FakeConfigApi(<String, dynamic>{}, error: error),
      );

      await expectLater(
        container.read(featureFlagsProvider.notifier).load(),
        completes,
      );
      expect(
        container.read(featureFlagProvider('roamNpcEvent')),
        isFalse,
        reason: error.runtimeType.toString(),
      );
    }
  });

  test('换号或登出立即清空上一身份的灰度快照', () async {
    final container = _container(
      _FakeConfigApi(<String, dynamic>{'communityPostWrite': true}),
    );
    await container.read(featureFlagsProvider.notifier).load();
    expect(container.read(featureFlagProvider('communityPostWrite')), isTrue);

    container.read(featureFlagsProvider.notifier).clear();
    expect(container.read(featureFlagProvider('communityPostWrite')), isFalse);
  });

  test('清空后忽略上一身份尚未返回的灰度请求', () async {
    final api = _ControlledConfigApi();
    final container = ProviderContainer(
      overrides: [configApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final pendingLoad = container.read(featureFlagsProvider.notifier).load();
    container.read(featureFlagsProvider.notifier).clear();

    api.response.complete(<String, dynamic>{'communityPostWrite': true});
    await pendingLoad;

    expect(container.read(featureFlagProvider('communityPostWrite')), isFalse);
  });

  test('两个并发刷新乱序返回时只采用最新结果', () async {
    final api = _QueuedConfigApi();
    final container = ProviderContainer(
      overrides: [configApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final olderLoad = container.read(featureFlagsProvider.notifier).load();
    final newerLoad = container.read(featureFlagsProvider.notifier).load();

    api.responses[1].complete(<String, dynamic>{'communityPostWrite': false});
    await newerLoad;
    api.responses[0].complete(<String, dynamic>{'communityPostWrite': true});
    await olderLoad;

    expect(container.read(featureFlagProvider('communityPostWrite')), isFalse);
  });

  test('后台刷新完成前容器销毁不会留下异步异常', () async {
    final api = _ControlledConfigApi();
    final container = ProviderContainer(
      overrides: [configApiProvider.overrideWithValue(api)],
    );

    final pendingLoad = container.read(featureFlagsProvider.notifier).load();
    container.dispose();
    api.response.complete(<String, dynamic>{'communityPostWrite': true});

    await expectLater(pendingLoad, completes);
  });
}
