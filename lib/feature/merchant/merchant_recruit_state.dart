import '../../data/models/chapter_application.dart';
import '../../data/models/merchant_recruit.dart';
import '../../data/models/topic.dart';

/// 这条路线对**当前商家**开的是哪条承接链路。
///
/// ★★ 判据不是自己猜 productType,而是**问服务端**:
///   `/api/topic/merchant-recruitment-chapters` 会用四句不同的话回答四种处境。
///   自己按 productType 分流的话,一旦品类没配 / 不是商家,
///   界面会渲成「这条路线没开招商」—— 而那是三种完全不同的处境,
///   其中两种用户自己就能解决。
enum RecruitMode {
  /// 自由探索:按**章节**申请承接,过审后填实际供给。
  chapterRecruit,

  /// 经典定向:按**节点**报名,后台择优调配。
  nodeRegistration,

  /// 商家品类没配 —— 可执行的前置态,不是"没开招商"。
  categoryMissing,

  /// 当前账号不是商家。
  notMerchant,
}

/// 招商承接页一次拉齐的全部内容。
class RecruitState {
  const RecruitState({
    required this.mode,
    required this.topicName,
    this.blockedMessage,
    this.chapters = const <RecruitChapter>[],
    this.applications = const <ChapterApplication>[],
    this.nodes = const <MyChapterNode>[],
    this.topicChapters = const <TopicChapter>[],
    this.registered,
  });

  final RecruitMode mode;
  final String topicName;

  /// 服务端拒绝的原话。品类缺失/非商家时照原文显示 —— 它自带修复指引。
  final String? blockedMessage;

  final List<RecruitChapter> chapters;
  final List<ChapterApplication> applications;
  final List<MyChapterNode> nodes;

  /// 主题结构(章节 → 节点)。经典定向报名要从这里选节点。
  final List<TopicChapter> topicChapters;

  /// 我报过这条路线没有。
  ///
  /// ★★ **null = 没查出来**,不是"没报过"。查询失败时仍然放行报名
  ///   (服务端 create 有查重闸,会给出准确的拒绝话术),
  ///   但界面要说清"没查出来",不能装作已经确认过。
  final bool? registered;

  /// 经典定向里可选的节点,按章节顺序摊平。
  List<TopicNode> get selectableNodes => <TopicNode>[
    for (final TopicChapter c in topicChapters) ...c.nodes,
  ];

  RecruitChapter? chapterOf(int? chapterId) {
    if (chapterId == null) return null;
    for (final RecruitChapter c in chapters) {
      if (c.id == chapterId) return c;
    }
    return null;
  }

  /// 一条申请当下能做什么。★ 档位从可承接章节那份里对出来 ——
  ///   `chapter-application/mine` 自己不下发 termsMode。
  ChapterApplicationAction actionOf(ChapterApplication a) {
    return ChapterApplicationAction(
      status: a.status,
      source: a.source,
      offerActive: a.offerActive,
      termsMode: chapterOf(a.chapterId)?.termsMode,
      offerId: a.offerId,
      circleThemeCode: a.circleThemeCode,
    );
  }
}
