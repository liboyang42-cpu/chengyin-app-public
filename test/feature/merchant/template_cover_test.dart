// 玩法封面:模型里一直有 imgUrl,编辑器里却没有这个输入。
//
// ★★ `NodeTemplateDraft.toJson` 从一开始就发 imgUrl —— 但界面上没地方填,
//   所以**永远发空**。结果是玩法在列表和详情里都没有图,
//   而后端和模型都一副「支持封面」的样子。
//   这类缺口端点对账查不出来(接口通、字段也在),只有对着页面比才看得见。

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  test('★★ 编辑器必须有封面上传入口', () {
    final String src = codeOf('lib/feature/merchant/node_template_edit_page.dart');
    expect(src.contains("Key('template-cover-upload')"), isTrue,
        reason: 'toJson 里发 imgUrl,而界面没地方填 —— 永远发空');
    expect(src.contains('pickAndUploadImages'), isTrue);
  });

  test('★ 标出比例 —— 传错形状只能裁', () {
    final String src = codeOf('lib/feature/merchant/node_template_edit_page.dart');
    expect(src.contains('kHint16x9'), isTrue);
  });

  test('★★ 上传失败不许清掉已有的图', () {
    // 换图失败还把旧图弄没了,用户要重新找一张;保留旧的最坏只是没换成。
    final String src = codeOf('lib/feature/merchant/node_template_edit_page.dart');
    // 只在 urls 非空时才写 —— 不写 else 分支去清空。
    expect(src.contains('if (urls.isNotEmpty && mounted)'), isTrue,
        reason: '拿到新图才覆盖;失败路径不碰 imgUrl');
  });

  test('有图时给「换一张」和「移除」两个动作', () {
    final String src = codeOf('lib/feature/merchant/node_template_edit_page.dart');
    expect(src.contains("Key('template-cover-replace')"), isTrue);
    expect(src.contains("Key('template-cover-remove')"), isTrue);
  });
}
