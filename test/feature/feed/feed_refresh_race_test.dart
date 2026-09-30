import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/feed/feed_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedTopics implements TopicApi {
  final requests = <({int page, Completer<List<Topic>> result})>[];

  @override
  Future<List<Topic>> list({
    int isMy = 0,
    String? keyword,
    String? categoryId,
    bool recommend = false,
    int pageNum = 1,
    int pageSize = 10,
  }) {
    final result = Completer<List<Topic>>();
    requests.add((page: pageNum, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Topic> _page(int start) => List.generate(
  10,
  (index) => Topic(id: start + index, name: 'Topic ${start + index}'),
);

void main() {
  for (final oldRequestFails in <bool>[false, true]) {
    test('refresh discards old pagination ${oldRequestFails ? 'failure' : 'success'}', () async {
      final api = _DelayedTopics();
      final container = ProviderContainer(overrides: [
        topicApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      final subscription = container.listen(feedProvider, (_, _) {});
      addTearDown(subscription.close);
      final initial = container.read(feedProvider.future);
      api.requests[0].result.complete(_page(0));
      await initial;
      final notifier = container.read(feedProvider.notifier);
      final oldPage = notifier.loadMore();
      expect(api.requests[1].page, 2);

      container.invalidate(feedProvider);
      final refreshed = container.read(feedProvider.future);
      api.requests[2].result.complete(_page(100));
      await refreshed;
      final newPage = notifier.loadMore();
      expect(api.requests[3].page, 2);
      if (oldRequestFails) {
        api.requests[1].result.completeError(StateError('old request'));
      } else {
        api.requests[1].result.complete(_page(10));
      }
      await oldPage;
      expect(container.read(feedProvider).requireValue.map((row) => row.id),
          _page(100).map((row) => row.id));
      expect(notifier.loadMoreFailed, isFalse);
      await notifier.loadMore();
      expect(api.requests, hasLength(4), reason: 'old finally must not unlock new request');
      api.requests[3].result.complete(_page(110));
      await newPage;
      expect(container.read(feedProvider).requireValue.map((row) => row.id),
          List.generate(20, (index) => 100 + index));
    });
  }
}
