import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/play_route_api.dart';
import '../../data/models/play_route_state.dart';

typedef PlayRouteKey = ({int? activityId, int? topicId});

final playRouteStateProvider = FutureProvider.autoDispose
    .family<PlayRouteState, PlayRouteKey>((ref, PlayRouteKey key) {
      return ref
          .watch(playRouteApiProvider)
          .fetch(activityId: key.activityId, topicId: key.topicId);
    });
