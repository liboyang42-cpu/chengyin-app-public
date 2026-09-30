import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/topic.dart';

/// 路线详情(按主题 id)。
final topicDetailProvider = FutureProvider.autoDispose.family<TopicDetail, int>(
  (ref, id) {
    return ref.watch(topicApiProvider).detail(id);
  },
);
