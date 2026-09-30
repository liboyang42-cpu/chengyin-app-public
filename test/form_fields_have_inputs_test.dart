// 模型 toJson 里发的字段,界面必须有地方填。
//
// ★★ 今天连撞三次同一个形状,**其中一次是我自己刚犯完又犯**:
//   · 玩法编辑器:NodeTemplateDraft.toJson 发 imgUrl,界面没输入 ⇒ 永远发空
//   · 发布活动页:ActivityPublishForm 有 imgUrl,我建页时漏了 ⇒ 同上
//   · 玩法详情/路线详情:后端在发、模型没解析(另一个方向)
//
//   共同点:数据链路的某一节被掐断,而**两头看起来都正常** ——
//   后端有字段、模型有字段、接口通、有人调,就是没人填/没人读。
//   端点对账查不出来,靠人记也记不住 —— 所以立一条门禁。
//
// ⚠️ 这条只覆盖**点名的几个表单**。做成全仓通用判据很难:
//   字段可能由别处赋值(路由参数、上一页带入),一刀切必然误报。
//   与其做一个天天误报最后没人看的门禁,不如覆盖窄一点但每条都算数。

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

/// 表单文件 → 它必须能填的字段(界面上要出现对应的 Key 或 setter)。
const Map<String, List<String>> kFormsMustAcceptInput = <String, List<String>>{
  'lib/feature/publish/publish_activity_page.dart': <String>['imgUrl'],
  'lib/feature/merchant/node_template_edit_page.dart': <String>['imgUrl'],
};

void main() {
  test('★★ toJson 发的字段,界面必须有地方填', () {
    final List<String> bad = <String>[];
    for (final MapEntry<String, List<String>> e
        in kFormsMustAcceptInput.entries) {
      final String code = codeOf(e.key);
      for (final String field in e.value) {
        // ⚠️ 「有地方填」要看**真的从用户输入拿到值**那一处,
        //   不是「文件里出现过这个字段名」—— 移除按钮也写
        //   `copyWith(imgUrl: '')`,只查字段名的话把它也算成「能填」,
        //   于是删掉上传路径照样绿(负控当场证伪,今天第五次同型)。
        final bool settable = code.contains(field + ': urls.first') ||
            code.contains(field + ': urls[0]') ||
            RegExp(field + r": _c\['" + field + r"'\]").hasMatch(code);
        if (!settable) bad.add('${e.key} 的 $field');
      }
    }
    expect(bad, isEmpty,
        reason: '这些字段模型在发、界面却没地方填 —— 提交时永远是空值:\n'
            '${bad.join('\n')}');
  });
}
