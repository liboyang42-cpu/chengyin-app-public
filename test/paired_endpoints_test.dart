// 门禁:成对的接口不许只接一半。
//
// ★ 这是端点对账十一批下来**最高频的形态**,前面每一批的发现事后看都命中它:
//   · 出码接了、核销没接        → 玩家能出示,商家扫不了
//   · 建单接了、取消没接        → 买了票不能退
//   · 只读流接了、互动没接      → 看得到「3 赞」点不了赞
//   · 点赞接了、我赞过的没接    → 收藏了找不到自己收藏过什么
//   · 第一步接了、第二步没接    → 后端说「请选择章节」,却没有可选的东西
//   · **写接了、读没接**        → 见下面「只写不读」那一组,单独出现过四次
//
// ★「只写不读」是这里面最隐蔽的一支:写成功了、界面也刷新了,**看起来完全正常** ——
//   直到用户换个设备、重装、或者第二天再进来,才发现状态根本没被读回来。
//   本地那次乐观更新掩盖了缺口,所以当场测不出来。
//
// 共同点:**已接的那一半工作正常**,所以界面上完全看不出缺了东西。
// 逐页看图永远发现不了,只有把成对的两端摆在一起才能发现。
//
// 这道闸把已知的成对关系钉住:一端接了,另一端也必须接。
// 负控:注释掉任意一条已接的端点 → 本测试必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 成对关系。左右两端**必须同进同出**。
/// ⚠️ 加新接口时如果它有对偶(出/收、建/删、写/读回),记得往这里加一行。
const List<(String, String, String)> _kPairs = <(String, String, String)>[
  // (一端, 另一端, 只接一半会怎样)
  (
    '/api/verify/citynode/issue',
    '/api/verify/citynode/redeem',
    '玩家能出示据点码,商家扫不了'
  ),
  (
    '/api/verify/groupcode/issue',
    '/api/verify/groupcode/redeem',
    '玩家能出示团码,商家扫不了'
  ),
  (
    '/api/registration/create',
    '/api/registration/cancel',
    '能报名不能取消'
  ),
  (
    '/api/registration/cancel',
    '/api/registration/cancel-refund',
    '未支付能取消、已支付的退不了款'
  ),
  (
    '/api/registration/scan_qr_code',
    '/api/registration/scan_qr_code_chapter',
    '后端说「请选择章节」,却没有端点接收那个选择 —— 核销是死胡同'
  ),
  (
    '/api/club/post/feed',
    '/api/club/post/like',
    '圈子看得到赞数,点不了赞'
  ),
  (
    '/api/club/post/comment/list',
    '/api/club/post/comment/create',
    '评论看得到,发不出去'
  ),
  (
    '/api/activity/like',
    '/api/activity/like_list',
    '赞了活动,找不到自己赞过什么'
  ),
  (
    '/api/topic/like',
    '/api/topic/like_list',
    '收藏了主题,找不到之后想参加的路线'
  ),
  (
    '/api/coupon/qr-token',
    '/api/coupon/verification',
    '玩家能出示券码,商家核销不了'
  ),
  (
    '/api/roam/reveal',
    '/api/roam/finish',
    '格子点亮了,但从不结算 —— 探索值和勋章永远发不出去'
  ),
  (
    '/api/roam/reveal',
    '/api/roam/tiles',
    '点亮了迷雾但读不回来 —— 重装或换设备后地图退回一片全黑'
  ),
  // ——— 只写不读:写的那一半让人以为功能是完整的 ———
  (
    '/api/merchant/business-status/update',
    '/api/merchant/business-status',
    '设了营业状态却读不回来 —— 两个按钮恒定长一样,营业中的商家看着像没开门'
  ),
  (
    '/api/compliance/consents',
    '/api/compliance/consents/latest',
    '同意提交了却读不回来 —— 用户签过了还要再签,而合规要的正是"在哪个版本上签的"'
  ),
  (
    '/api/login',
    '/api/logout',
    '能登录不能登出 —— token 在服务端一直有效,手机丢了那份凭据还能用'
  ),
  (
    '/api/im/block',
    '/api/im/report',
    '只能拉黑不能举报 —— 被拉黑的人对别人照发,Apple 1.2 也不认'
  ),
  (
    '/api/template/topic-template/use',
    '/api/template/topic-template/list',
    '整包主题能复制成草稿、却浏览不到主题货架 —— 用户知道有人在用,不知道该用哪个'
  ),
];

void main() {
  test('★ 成对的接口不许只接一半', () {
    final StringBuffer src = StringBuffer();
    int scanned = 0;
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      src.write(e.readAsStringSync());
    }
    final String all = src.toString();

    expect(scanned, greaterThanOrEqualTo(100),
        reason: '只扫到 $scanned 个 lib 文件,太少了 —— 目录变了?');

    bool has(String ep) => all.contains("'$ep'");

    final List<String> broken = <String>[];
    for (final (String a, String b, String why) in _kPairs) {
      final bool ha = has(a);
      final bool hb = has(b);
      if (ha == hb) continue; // 都接或都没接,都不算「只接一半」
      final String missing = ha ? b : a;
      final String present = ha ? a : b;
      broken.add('$present 接了,但 $missing 没接 —— $why');
    }

    expect(broken, isEmpty,
        reason: '成对的接口只接一半,界面上看不出来(已接的那一半工作正常):\n'
            '${broken.join('\n')}');
  });

  test('清单里的端点都还存在于代码中 —— 防止改名后这道闸静默失效', () {
    final StringBuffer src = StringBuffer();
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) src.write(e.readAsStringSync());
    }
    final String all = src.toString();

    final List<String> gone = <String>[];
    for (final (String a, String b, _) in _kPairs) {
      for (final String ep in <String>[a, b]) {
        if (!all.contains("'$ep'")) gone.add(ep);
      }
    }
    // ★ 全部成对接完之后,这个清单应该一条不缺。缺了说明端点被改名或删掉了,
    //   而上面那条断言对「两端都没接」是放行的 —— 只靠它会静默失效。
    expect(gone, isEmpty,
        reason: '这些端点在代码里找不到了(改名?删了?)。'
            '请更新 _kPairs,否则上一条断言会对它们视而不见:\n${gone.join('\n')}');
  });
}
