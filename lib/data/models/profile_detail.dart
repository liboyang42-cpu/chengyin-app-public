import 'category.dart';

/// 完整资料卡模型。对齐后端 `UmsMember`(`POST /api/user/info`,member_id 留空取本人)。
/// 字段名以 controller 回填的 UmsMember 为准:nickname/avatar/introduction/levelId/
/// point/followNum/fansNum/likeNum/topicNum/activityNum(camelCase)。
class ProfileDetail {
  ProfileDetail({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.introduction,
    required this.levelId,
    required this.point,
    this.balance,
    this.friendNum,
    required this.followNum,
    required this.fansNum,
    required this.likeNum,
    required this.topicNum,
    required this.activityNum,
    this.isFollow,
    this.casePics = const <String>[],
    this.wechat = '',
    this.routePreferences = const <Category>[],
  });

  /// 观看者与本人的关注关系。★★ **三态**,null 不是 false:
  /// 后端 PublicMemberServiceImpl 对匿名访问**有意不下发**这个字段
  /// (注释原话:「匿名:不查关注关系,isFollow 保持 null」)。
  /// 把 null 当成"未关注"会让游客看到一个假的「关注」按钮 ——
  /// 点下去撞登录墙,而界面刚才还告诉他"你没关注这个人"。
  final bool? isFollow;

  final int id;
  final String nickname;
  final String avatar;
  final String introduction;
  final int levelId;
  final int point;

  /// 可提现余额(元)。
  ///
  /// ★ 用 `double?` 而不是 `double` —— **必须分清「没拿到」和「余额是 0」**。
  ///   两者的界面完全不同:没拿到要说「余额没取到,请重试」,
  ///   而不是说「无可提现金额」—— 后者是在替用户陈述他的资产,而我们其实不知道。
  final double? balance;

  /// 好友数。★ **后端 `/api/user/info` 目前没有这个字段**(小程序
  /// components/cy/profile/index.js:804 原注释:「/api/user/info 当前没有
  /// friendNum 契约。缺字段显示「—」,不能造一个 0。」)—— null ≠ 0。
  final int? friendNum;

  final int followNum;
  final int fansNum;
  final int likeNum;
  final int topicNum;
  final int activityNum;
  final List<String> casePics;
  final String wechat;
  final List<Category> routePreferences;

  factory ProfileDetail.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return ProfileDetail(
      id: asInt(json['id']),
      nickname: (json['nickname'] ?? '') as String,
      avatar: (json['avatar'] ?? '') as String,
      introduction: (json['introduction'] ?? '') as String,
      levelId: asInt(json['levelId']),
      point: asInt(json['point']),
      balance: (json['balance'] as num?)?.toDouble(),
      friendNum: (json['friendNum'] as num?)?.toInt(),
      followNum: asInt(json['followNum']),
      fansNum: asInt(json['fansNum']),
      likeNum: asInt(json['likeNum']),
      topicNum: asInt(json['topicNum']),
      activityNum: asInt(json['activityNum']),
      casePics: (json['casePics'] as String? ?? '')
          .split(';')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
      wechat: (json['wechat'] as String? ?? '').trim(),
      routePreferences:
          (json['sysCategoryList'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Category.fromJson)
              .where((Category category) => category.id > 0)
              .toList(growable: false),
      // 后端现在发 0/1;将来若改发布尔也接得住。字段缺失 = null(见上)。
      isFollow: switch (json['isFollow']) {
        final num n => n.toInt() == 1,
        final bool b => b,
        _ => null,
      },
    );
  }
}
