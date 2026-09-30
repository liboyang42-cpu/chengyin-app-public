import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/growth.dart';
import '../../data/models/profile_detail.dart';
import '../../data/models/square_post.dart';
import '../../data/models/user.dart';

/// 当前用户信息:`POST /api/userInfo`(需带 token)。
/// 后端结构:AjaxResult{code, appUser:AppUser};非 200 抛错进入 error 态,
/// 不把空/错误体兜底成 id=0 的假用户。
final userInfoProvider = FutureProvider.autoDispose<User>((ref) async {
  final body = await ref.watch(authApiProvider).userInfo();
  if ((body['code'] as num?)?.toInt() != 200) {
    throw Exception((body['msg'] ?? '未登录或会话已过期').toString());
  }
  final data = body['appUser'] as Map<String, dynamic>?;
  if (data == null) {
    throw Exception('用户信息为空');
  }
  return User.fromJson(data);
});

/// 完整资料卡:`POST /api/user/info`(本人)。含关注/粉丝/赞/简介/等级。
/// `/api/userInfo`(AppUser)不含这些字段,所以单独拉一次;未登录走 error 态。
final profileDetailProvider = FutureProvider.autoDispose<ProfileDetail>((ref) {
  return ref.watch(registrationApiProvider).userDetail();
});

/// 本人是否有进行中的报名。小程序个人主页用它决定“开始探索”落到票夹还是首页。
/// 无进行中报名时后端返回非 200；这里按源行为收敛为 false，不把它显示成页面故障。
final hasActiveRegistrationProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final Map<String, dynamic>? row = await ref
      .watch(registrationApiProvider)
      .joinInfo();
  return row != null;
});

/// 成长中心:等级/经验/积分/徽章/任务。
final growthCenterProvider = FutureProvider.autoDispose<GrowthCenter>((ref) {
  return ref.watch(growthApiProvider).center();
});

/// 我的成长进度:`POST /api/play/growth`(需登录)。
/// 本人主页那一行「连续探索：N 天」用它(小程序 cy-profile index.js:868
/// 就是从 `play.streakDays` 取的),`/api/growth/center` 没有 streakDays。
final playGrowthProvider = FutureProvider.autoDispose<PlayGrowth>((ref) {
  return ref.watch(growthApiProvider).playGrowth();
});

/// 我的发布/动态流:`POST /api/creativesquare/list`(is_my=1)。
/// 后端 startPage 读取请求里的 pageNum/pageSize 分页;复用 SquarePost 模型。
/// 已注册的 SquareApi.list 不透传分页参,故这里经 dioClientProvider 直接发请求
/// 以支持触底加载(解析逻辑与 SquareApi 保持一致:data.rows)。
final myCreativesProvider =
    AsyncNotifierProvider.autoDispose<MyCreativesController, List<SquarePost>>(
      MyCreativesController.new,
    );

class MyCreativesController extends AsyncNotifier<List<SquarePost>> {
  int _pageNum = 1;
  static const int _pageSize = 10;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;

  Future<List<SquarePost>> _fetch(int pageNum) async {
    final client = ref.read(dioClientProvider);
    final resp = await client.dio.post<Map<String, dynamic>>(
      '/api/creativesquare/list',
      data: FormData.fromMap(<String, dynamic>{
        'is_my': '1',
        'pageNum': pageNum.toString(),
        'pageSize': _pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '动态加载失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rows = (data['rows'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => SquarePost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SquarePost>> build() async {
    _pageNum = 1;
    _hasMore = true;
    final page = await _fetch(_pageNum);
    _hasMore = page.length >= _pageSize;
    return page;
  }

  /// 触底加载下一页;追加到现有列表。失败静默(保留已加载内容)。
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.value;
    if (current == null) return;
    _loadingMore = true;
    try {
      final next = await _fetch(_pageNum + 1);
      _pageNum += 1;
      _hasMore = next.length >= _pageSize;
      state = AsyncData<List<SquarePost>>(<SquarePost>[...current, ...next]);
    } finally {
      _loadingMore = false;
    }
  }
}

/// IM 未读总数:`POST /api/im/unread-total`。失败/未登录 → 0(不显红点)。
final unreadTotalProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await ref.watch(imApiProvider).unreadTotal();
  } catch (_) {
    return 0;
  }
});
