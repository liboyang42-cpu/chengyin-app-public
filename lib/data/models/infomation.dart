/// 城瘾玩法页的资讯条目。
/// 对齐后端 `CmsInfomation{ id, title, subtitle, sortId, contents }`
/// (ApiCommonController#infomationList)。
///
/// ★ 规则逐条移植自小程序 `subpackageA/pages/infomation/infomation.js:44-62`,
///   那段注释把判据写得很清楚,原样保留其精神:**只做由契约直接推出的事,从不伪造标题**。
class Infomation {
  const Infomation({
    required this.id,
    required this.title,
    this.subtitle,
    this.contents,
  });

  final int id;
  final String title;
  final String? subtitle;
  final String? contents;

  /// 摘要。★ **subtitle 与 title 逐字相同时不渲染** ——
  ///   把同一个值印两遍,信息量为零。
  String? get summary {
    final s = subtitle?.trim() ?? '';
    if (s.isEmpty) return null;
    if (s == title.trim()) return null;
    return s;
  }

  /// 这一条能不能显示给用户。三条判据:
  ///   a. title 为空          → 列表上没有可读锚点
  ///   b. contents 为空       → 点进详情是空正文
  ///   c. **标题是纯数字,且没有任何能区分它的副标题** → 无有效用户可读标题
  ///
  /// ⚠️ (c) **绝不是「过滤数字」**。判据是「纯数字 **且** 无区分信息」:
  ///   - title='11'   subtitle='11'             → 不可读(线上真实存在这一行)
  ///   - title='11'   subtitle=''               → 不可读
  ///   - title='2024' subtitle='年度城市定向回顾' → **保留**(数值命名 + 有效副标题)
  ///   - title='11'   subtitle='新手上路指南'     → **保留**(副标题给了语义)
  ///   - title='72小时城市漫游'                   → **保留**(非纯数字)
  bool get usable {
    final t = title.trim();
    if (t.isEmpty) return false;
    if ((contents ?? '').trim().isEmpty) return false;
    final pureDigits = RegExp(r'^\d+$').hasMatch(t);
    if (pureDigits && summary == null) return false;
    return true;
  }

  factory Infomation.fromJson(Map<String, dynamic> json) {
    return Infomation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      subtitle: json['subtitle'] as String?,
      contents: json['contents'] as String?,
    );
  }
}

/// 三种玩法。本地常量,与小程序 MODES 一致。
class PlayMode {
  const PlayMode({
    required this.key,
    required this.name,
    required this.tag,
    required this.desc,
    required this.route,
  });

  final String key;
  final String name;
  final String tag;
  final String desc;

  /// App 侧的真实落点。★ 必须是路由表里真有的 ——
  ///   门禁 test/router_targets_exist_test.dart 盯着。
  final String route;
}

const List<PlayMode> kPlayModes = <PlayMode>[
  PlayMode(
    key: 'classic',
    name: '城市定向',
    tag: '组队 · 按顺序',
    desc: '按顺序打卡通关,到点了大家一起出发。适合约人、适合有剧情的路线。',
    // 源 MODES 三张卡全部 switchTab 到 tabBar 页:经典/自由→首页,漫游→漫游
    // (subpackageA/pages/infomation/infomation.js:20-43)。App 首页是 /feed,
    // 漫游 tab 是 /roam —— /map 是另一个独立地图页,不是漫游。
    route: '/feed',
  ),
  PlayMode(
    key: 'free',
    name: '自由探索',
    tag: '随时 · 自己走',
    desc: '点位全开,想从哪个开始都行。买张通行证随时开玩,不用等人凑齐。',
    route: '/feed',
  ),
  PlayMode(
    key: 'roam',
    name: '漫游',
    tag: '无终点 · 散步',
    desc: '边走边点亮城市迷雾,没有任务也没有终点。顺路散个步也算数。',
    route: '/roam',
  ),
];
