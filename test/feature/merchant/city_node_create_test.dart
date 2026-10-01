// 报名成为节点(据点投放申请)的三条硬语义。
//
// 这一页每一条都对应一个"会静默出错"的失败:
//   ① 店址默认取档案坐标,但**必须让商家点头一次**。
//      静默提交的话,坐标偏了没人会发现 —— 表现成"玩家一直打不了卡",
//      而商家完全不知道问题在哪。
//   ② 提交成功后再点**不重复提交**,只重做回读。
//      后端没有幂等键,重复点 = 重复的投放申请。
//   ③ 提交返回 200 只是**回执**;回列表里找到这条申请才算观测。
//      找不到时说"还没同步出来",不能说"失败"——说失败商家会再提一次。
//
// 另外:配额满时**隐藏**入口并说清原因,而不是让人配完玩法、确认完店址,
// 最后一步才撞「在架据点已达上限」——那是最坏的失败时机。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';

import 'package:chengyin_app/data/models/merchant_city_node.dart';
import '../../support/source_text.dart';

void main() {
  final String page = codeOf(
    'lib/feature/merchant/merchant_city_node_create_page.dart',
  );
  final String list = codeOf(
    'lib/feature/merchant/merchant_city_node_page.dart',
  );

  test('★★ 提交前必须两步都齐:模板 + 店址已确认', () {
    expect(
      page.contains(
        'bool get _canSubmit =>\n      _templateId != null && _confirmed',
      ),
      isTrue,
      reason: '少了 _confirmed 就是"拿档案坐标静默提交",坐标偏了没人会发现',
    );
  });

  test('★★ 已提交过就只回读,不再发第二次申请', () {
    // 后端没有幂等键。这个守卫没了 = 手抖点两下就是两条投放申请。
    expect(
      page.contains('final int? already = _submittedApplicationId;'),
      isTrue,
    );
    expect(
      page.contains('if (already != null) {\n      await _readBack(already);'),
      isTrue,
      reason: '提交成功后再点必须走回读分支,不能落到 saveCityNode',
    );
  });

  test('★★ 提交后要回读列表确认,不能只信 200', () {
    expect(page.contains('_readBack('), isTrue);
    expect(
      page.contains('home.applications'),
      isTrue,
      reason: '回读必须去列表里找这条申请 —— 那才是"从对面读回来"',
    );
  });

  test('★ 回读没找到时说「还没同步」,不说「失败」', () {
    expect(page.contains('merchantNodeAwaitSync'), isTrue);
    expect(AppLocalizationsZh().merchantNodeAwaitSync, contains('申请已提交,但审核状态还没同步出来'));
    // 说失败会让商家再提一次 —— 而申请其实已经在了。
    expect(page.contains('提交失败'), isFalse);
  });

  test('★★ 玩法配置页已经有了 —— 换成真跳转,但仍不许替商家挑模板', () {
    // 之前这里是一句"还在做"的提示。**「不做假入口」那条仍然成立**:
    // 现在换成真跳转,是因为 NodeTemplateEditPage 真建好了,
    // 不是因为放宽了标准。
    expect(page.contains("push('/merchant/node-template')"), isTrue);
    expect(page.contains('玩法配置页还在做'), isFalse);

    // ★ 仍然只接受配置页**带回来**的 id —— 不许自己挑一个已有模板。
    //   挑错模板 = 玩家到店后玩到别的店的关卡。
    expect(page.contains("final Object? id = r['id'];"), isTrue);
    expect(
      page.contains('templateList') || page.contains('firstTemplate'),
      isFalse,
      reason: '出现"取一个已有模板"的写法 = 在替商家瞎挑',
    );
  });

  test('★ 店址确认的提示必须说清**后果**', () {
    expect(page.contains('merchantNodeAddressHint(_radiusM)'), isTrue);
    expect(AppLocalizationsZh().merchantNodeAddressHint(80), contains('80 米内才算到达'));
    expect(
      AppLocalizationsZh().merchantNodeAddressHint(80).contains('偏了他会一直打不了卡'),
      isTrue,
      reason: '只说"请确认店址"的话,商家不知道确认的是什么、错了会怎样',
    );
  });

  group('配额', () {
    test('★ 投放入口保留，配额满时点击原样说明', () {
      expect(list.contains('merchantNodePlace'), isTrue);
      expect(list.contains('merchantNodeQuota'), isTrue);
      expect(AppLocalizationsZh().merchantNodeQuota, '在架据点已达上限,请先下线其他据点');
      expect(list.contains('home.quotaExhausted'), isTrue);
    });

    test('quotaExhausted 的判据:后端没下发上限时不算满', () {
      const CityNodeHome noQuota = CityNodeHome(used: 5, max: 0);
      expect(
        noQuota.quotaExhausted,
        isFalse,
        reason:
            'max=0 是"后端没下发上限",不是"上限为零" —— '
            '判成满会把入口永久藏起来',
      );
      const CityNodeHome full = CityNodeHome(used: 3, max: 3);
      expect(full.quotaExhausted, isTrue);
    });
  });
}
