// 文案批(club 域):App 上屏的字逐字取小程序原文。
//
// 为什么单开一个文件而不是散进各页测试:这里钉的是**widget 测试跑不到的那几态** ——
// 加载骨架的读屏文案(`loading-label` 在小程序是 aria-label,不显示)、
// 「确认查看权限」失败才出现的两态、保存失败才出现的 inline-error 标题、
// 以及跑一次失败请求才看得到的错误页标题。
// 造这些态要挂网络/权限,不假造 —— 按仓内既有 gate 的做法直接钉源码字面量,改字就红。
//
// 真源:`~/Downloads/chengyin` 的 `github/master:chengyinhub-xcx/`,逐条见下方出处。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 页 → (文件, 该页必须逐字出现的原句)。
const Map<String, List<String>> _kOriginal = <String, List<String>>{
  // pages/club/workbench/index.wxml:cy-error title / retry。
  // 该页在 App 里只做「外部深链 → 跳转」,小程序 errorText 的另一条取值
  // 「暂时无法进入俱乐部管理，请重试或返回俱乐部。」属 `wx.redirectTo` 的 fail 回调
  // (`index.js:30`);App 走 go_router 不存在这条失败态,故不钉进页面源码。
  'pages/club/workbench/index': <String>['没能进入俱乐部管理', '重试进入'],
  // pages/club/group-code/index.wxml:cy-page-title subtitle 与两个终态的出口。
  'pages/club/group-code/index': <String>[
    '选择本次带队场次',
    '请从俱乐部管理进入具体场次',
    '当前账号不能出示这一场的团码',
    '当前账号没有出码权限',
    '缺少路线或场次信息',
    '返回俱乐部，选择具体场次后再出示团码',
    '进入俱乐部管理',
  ],
  // pages/club/topic-detail/index.wxml:骨架 loading-label、四圆钮与台账的 aria-label。
  'pages/club/topic-detail/index': <String>['正在加载活动详情', '活动快捷入口', '打开核销台账'],
  // pages/club/enroll/index.wxml:权限确认/名册/报名详情三处 loading-label,
  // 权限层失败的标题与重试键,网络失败态副标,以及空态 sub(逗号照原文半角)。
  'pages/club/enroll/index': <String>[
    '正在确认报名名册查看权限',
    '正在加载报名名册',
    '正在加载报名详情',
    '暂时无法确认查看权限',
    '重新检查',
    '检查网络后重新加载报名名册',
    '在发布器选择「城市定向」票种并归属本俱乐部,即可在此查看报名名册。',
  ],
  // pages/club/topic-story/index.wxml:骨架 loading-label、两处空态 sub、取答案中。
  'pages/club/topic-story/index': <String>[
    '正在加载剧情与玩法',
    '开放商家承接后，由承接商家补齐站点与玩法。',
    '承接商家补齐模板后会出现在这里。',
    '正在取答案…',
  ],
  // pages/club/customer-detail/index.wxml:骨架 loading-label、两个按钮的 aria-label、
  // 保存失败的 inline-error 标题。
  'pages/club/customer-detail/index': <String>[
    '正在加载客户详情',
    '取消编辑标签与备注',
    '添加标签',
    '标签与备注没保存成功',
  ],
  // pages/club/customers/index.wxml:骨架 loading-label。
  'pages/club/customers/index': <String>['正在加载客户名单'],
};

void main() {
  test('★ club 域:文案批动过的原句逐字留在源码里', () {
    const Map<String, String> sources = <String, String>{
      'pages/club/workbench/index': 'lib/feature/club/club_workbench_page.dart',
      'pages/club/group-code/index':
          'lib/feature/club/club_group_code_page.dart',
      'pages/club/topic-detail/index':
          'lib/feature/club/club_topic_detail_page.dart',
      'pages/club/enroll/index': 'lib/feature/club/club_enroll_page.dart',
      'pages/club/topic-story/index':
          'lib/feature/club/club_topic_story_page.dart',
      'pages/club/customer-detail/index':
          'lib/feature/club/club_customer_detail_page.dart',
      'pages/club/customers/index': 'lib/feature/club/club_customers_page.dart',
    };
    for (final MapEntry<String, List<String>> entry in _kOriginal.entries) {
      final String src = File(sources[entry.key]!).readAsStringSync();
      for (final String line in entry.value) {
        expect(
          src.contains(line),
          isTrue,
          reason: '${entry.key} 缺了小程序原句「$line」',
        );
      }
    }
  });
}
