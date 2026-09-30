/// 活动状态表 —— 逐条对齐小程序 `utils/activity-status.js:11-18`。
///
/// ★ 为什么单独一份而不是散在页面里:小程序把它抽成 utils 是有原因的 ——
///   「哪些状态算 live」这件事在列表筛选、状态文案、空态文案三处都要用,
///   散开写必然漂移。这里照搬同一份表。
///
/// ⚠️ 文案分公开视角与发布者视角:status=1 公开叫「即将开始」、发布者叫「待发布」。
///    App 只做玩家侧,取公开视角。
class ActivityStatusMeta {
  const ActivityStatusMeta(this.text, {required this.live});

  final String text;

  /// 是否算「进行中」档 —— 小程序 `live` 字段。只有 2 报名中 / 3 进行中为真。
  final bool live;
}

const Map<int, ActivityStatusMeta> kActivityStatus = <int, ActivityStatusMeta>{
  0: ActivityStatusMeta('', live: false), // 草稿(公开视角无文案)
  1: ActivityStatusMeta('即将开始', live: false),
  2: ActivityStatusMeta('报名中', live: true),
  3: ActivityStatusMeta('进行中', live: true),
  4: ActivityStatusMeta('结算中', live: false),
  5: ActivityStatusMeta('已结束', live: false),
  6: ActivityStatusMeta('已结束', live: false),
  9: ActivityStatusMeta('已下线', live: false),
};

ActivityStatusMeta activityStatusMeta(int? status) =>
    kActivityStatus[status ?? -1] ?? const ActivityStatusMeta('', live: false);

/// 列表的三个时间档,与小程序 `applyFilter`(index.js:205-207)同结构。
///
/// ⚠️ 判据**不是一个,是两个**(同名不同依据,别再合并):
///   · 官方活动(`pages/activity/list` ↔ App `/official-events`,端点
///     `/api/official/events`)**下发 status** → 用 [activityInBucket];
///   · 活动目录(App 独有 `/activities`,端点 `/api/activity/list`)**不下发 status**
///     → 只能用时间字段,用 [activityInTimeBucket]。
enum ActivityBucket {
  /// tab 0:进行中
  live,

  /// tab 1:即将
  upcoming,

  /// tab 2:已结束
  ended,
}

/// 按 `status` 分档 —— 判据逐条来自小程序 `applyFilter`(index.js:205-207)。
/// ⚠️ 只对**下发 status 的端点**成立(官方活动 /api/official/events);
/// 活动目录的端点是另一回事,用 [activityInTimeBucket]。
bool activityInBucket(int? status, ActivityBucket bucket) {
  final int s = status ?? -1;
  switch (bucket) {
    case ActivityBucket.live:
      return activityStatusMeta(s).live;
    case ActivityBucket.upcoming:
      return s == 1;
    case ActivityBucket.ended:
      return s >= 5;
  }
}

/// 后端日期字段(如 `/api/activity/list` 的 startDate/endDate)形如
/// "2026-08-27 13:00:00"。缺失 / 解析失败一律 null —— 不拿「今天」顶替。
DateTime? parseActivityDate(String? raw) {
  final String text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

/// 活动目录页(`/activities`)的三档判据 —— 用**后端真实下发的** startDate/endDate 推。
///
/// ★ 为什么不沿用上面那个 [activityInBucket] 的 status 判据:
///   `/api/activity/list` 公开口(后端 `PublicActivityScope.PUBLIC_SHELF`)的响应里
///   **没有 status 键**。2026-09-18 生产实测:游客 8/8 行缺(status 与 publishStatus
///   都没有),`activityStatusMeta(null)` 兜底 live:false ⇒ 三档恒空,而**同一批
///   活动**在 /feed「附近活动」正常显示。`status` 是**另一个端点**
///   (/api/official/events)下发的字段,`/official-events` 那页照旧用它,不受影响。
///
/// ⚠️ 天花板:公开口**只出「未结束」的活动**(ApiActivityController:220
///   「不出社群活动 + 只出未结束的」),所以「已结束」档在 App 侧填不满 ——
///   要它出内容得后端换口或补字段,不是前端能修的。
///
/// [now] 只为测试 / 基准图注入固定时钟;正常渲染传 null 走系统时间。
bool activityInTimeBucket({
  required String? startDate,
  required String? endDate,
  required ActivityBucket bucket,
  DateTime? now,
}) {
  final DateTime? start = parseActivityDate(startDate);
  final DateTime? end = parseActivityDate(endDate);
  final DateTime at = now ?? DateTime.now();
  switch (bucket) {
    case ActivityBucket.live:
      // 两个时间都缺 = 没有任何分档依据。不把它算进「进行中」假装知道。
      if (start == null && end == null) return false;
      // 缺 end = 没有结束时间(自建活动常见),开始过就还在进行。
      return (start == null || !at.isBefore(start)) &&
          (end == null || !at.isAfter(end));
    case ActivityBucket.upcoming:
      return start != null && at.isBefore(start);
    case ActivityBucket.ended:
      return end != null && at.isAfter(end);
  }
}

/// 列表分档的空态文案 —— 逐条对齐小程序 `EMPTY_COPY`(index.js:28-33)。
/// 返回 (标题, 副标)。
({String title, String sub}) activityEmptyCopy(ActivityBucket b, {bool mine = false}) {
  if (mine) return (title: '还没有参与的活动', sub: '报名活动后会出现在这里');
  switch (b) {
    case ActivityBucket.live:
      return (title: '暂无进行中的活动', sub: '官方策展活动会第一时间出现在这里');
    case ActivityBucket.upcoming:
      return (title: '暂无即将开始的活动', sub: '官方策展活动会第一时间出现在这里');
    case ActivityBucket.ended:
      return (title: '暂无已结束的活动', sub: '往期活动归档后会出现在这里');
  }
}

/// 搜索无结果时的空态 —— 小程序 index.js:221-222。
const ({String title, String sub}) kActivitySearchEmpty =
    (title: '没有找到相关活动', sub: '换个关键词,或看看其他分类');

/// 计数行 —— 小程序 index.js:219/224。
/// 有关键词:「「kw」N 个结果」;否则:「档名 · 共 N 个活动」。
String activitySummary({required String keyword, required String bucketLabel, required int count}) {
  final String kw = keyword.trim();
  return kw.isEmpty ? '$bucketLabel · 共 $count 个活动' : '「$kw」$count 个结果';
}

/// 档名 —— 小程序 `tabs`(index.js:62)。
const List<String> kActivityTabLabels = <String>['进行中', '即将', '已结束', '我的'];

/// 关键词匹配 —— 小程序 index.js:210-214:标题 / 副标 / 城市,大小写不敏感。
bool activityMatchesKeyword({
  required String keyword,
  String? title,
  String? subtitle,
  String? city,
}) {
  final String kw = keyword.trim().toLowerCase();
  if (kw.isEmpty) return true;
  bool hit(String? v) => (v ?? '').toLowerCase().contains(kw);
  return hit(title) || hit(subtitle) || hit(city);
}
