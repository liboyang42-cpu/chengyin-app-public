import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/api/official_api.dart';
import '../../data/models/official_event.dart';

/// official 域读失败的副文案(口径同 play 域 `my_plays_page._errorSub`,
/// 判据同 `activity_detail_page` / `topic_detail_page`):
/// 后端给了中文原话就用原话,只有 dio 自己的英文栈
/// (`DioException [bad response] ... developer.mozilla.org`)才换成人话。
/// 游客 401 不走这里 —— 那是登录态问题,页面要分流成登录引导。
String officialErrorSub(Object e) {
  if (e is! DioException) {
    return e.toString().replaceFirst('Exception: ', '');
  }
  final Object? data = e.response?.data;
  final String msg = data is Map ? (data['msg']?.toString().trim() ?? '') : '';
  return msg.isEmpty ? '网络开了点小差' : msg;
}

/// 官方活动详情。报名/完成任务后 invalidate 刷新 ——
/// ★ 不在本地把 signed 改成 true 了事:V2 契约明说「只接受服务端验证的事实,
///   不使用旧进度加一」,本地乐观更新会让界面和后端账对不上。
final officialEventProvider =
    FutureProvider.autoDispose.family<OfficialEvent, int>((ref, id) {
  return ref.watch(officialApiProvider).detail(id);
});

/// 我报名的官方活动。
final myOfficialEventsProvider =
    FutureProvider.autoDispose<List<OfficialEvent>>((ref) {
  return ref.watch(officialApiProvider).myEvents();
});

/// 承接邀约收件箱。
final partyInboxProvider =
    FutureProvider.autoDispose<List<PartyInviteItem>>((ref) {
  return ref.watch(officialApiProvider).partyInbox();
});

/// 我发布的活动 + 通知。
///
/// ⚠️ 无权限时后端返回「无官方发布权限」,这里**不吞异常** ——
///   页面要按 [OfficialApiException.isNoPermission] 分流成权限态而非错误态。
final myPublishedProvider = FutureProvider.autoDispose<MyPublished>((ref) {
  return ref.watch(officialApiProvider).myPublished();
});
