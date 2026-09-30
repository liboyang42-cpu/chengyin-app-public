// 契约测试:票券链路模型(Entitlement / RegistrationDetail / DynCode)。
//
// 对齐后端:
//   POST /api/registration/info      → RegistrationDetail(③ 带 entitlements)
//   POST /api/verify/dyncode/issue   → DynCode
//
// ★ 本文件最重要的断言是「完成度只按 entitlements 算」:
//   verification_status 对 ③ 只表示「被核销过至少一次」
//   (ApiRegistrationController:429-431)。谁把 pendingCount 改成看
//   verificationStatus,下面那条测试立刻红。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/activity.dart';

void main() {
  group('Entitlement.fromJson (/api/registration/info 的 entitlements[])', () {
    test('正常解析:后端已 enrich chapterName / statusLabel', () {
      final e = Entitlement.fromJson(<String, dynamic>{
        'id': 501,
        'registrationId': 9001,
        'chapterId': 77,
        'topicId': 12,
        'status': 1,
        'chapterName': '第二站 · 咖啡',
        'statusLabel': '已核销',
        'redeemedAt': '2026-08-18 14:03:00',
      });

      expect(e.id, 501);
      expect(e.status, 1);
      expect(e.chapterId, 77);
      expect(e.chapterName, '第二站 · 咖啡');
      expect(e.label, '已核销');
      expect(e.isRedeemed, isTrue);
      expect(e.isPending, isFalse);
      expect(e.isInvalid, isFalse);
    });

    test('边界:statusLabel 缺失时 label 走三态兜底,不返回 null 或空串', () {
      expect(Entitlement.fromJson(<String, dynamic>{'status': 0}).label, '待核销');
      expect(Entitlement.fromJson(<String, dynamic>{'status': 1}).label, '已核销');
      expect(Entitlement.fromJson(<String, dynamic>{'status': 2}).label, '已失效');
    });

    test('边界:字段全缺 → status 默认 0(应得),不崩', () {
      final e = Entitlement.fromJson(<String, dynamic>{});
      expect(e.id, 0);
      expect(e.status, 0);
      expect(e.isPending, isTrue);
      expect(e.chapterName, isNull);
    });
  });

  group('RegistrationDetail.fromJson (/api/registration/info)', () {
    test('③ 探索票:entitlements 解析 + 标题取 cmsActivity.name', () {
      final d = RegistrationDetail.fromJson(<String, dynamic>{
        'id': 9001,
        'ownerType': 2,
        'ownerId': 3301,
        'registrationNo': 'R20260818001',
        'registrationStatus': 2,
        'verificationStatus': 1,
        'purchaseKind': 'EXPLORE_PASS',
        'realName': '李某',
        'phone': '138****8000',
        'cmsActivity': <String, dynamic>{'name': '静安探店日 · 第一期'},
        'entitlements': <dynamic>[
          <String, dynamic>{'id': 1, 'status': 1, 'chapterName': 'A'},
          <String, dynamic>{'id': 2, 'status': 0, 'chapterName': 'B'},
          <String, dynamic>{'id': 3, 'status': 0, 'chapterName': 'C'},
        ],
      });

      expect(d.id, 9001);
      expect(d.title, '静安探店日 · 第一期');
      expect(d.isExplorePass, isTrue);
      expect(d.entitlements.length, 3);
      // 手机号由后端脱敏后下发,模型原样透传,不在客户端二次处理。
      expect(d.phone, '138****8000');
    });

    test('★ 完成度只按 entitlements 算:verificationStatus=1 但仍有 2 章待核销', () {
      // 这正是 ③ 的真实形态:核销完第 1 章后 verification_status 就置 1,
      // 但票还欠 2 章。若谁把 pendingCount 改成看 verificationStatus,
      // 这条断言会红 —— 那种改法会让玩家核销完第 1 章就再也拿不到码。
      final d = RegistrationDetail.fromJson(<String, dynamic>{
        'id': 9002,
        'ownerType': 2,
        'ownerId': 3301,
        'registrationStatus': 2,
        'verificationStatus': 1,
        'purchaseKind': 'EXPLORE_PASS',
        'entitlements': <dynamic>[
          <String, dynamic>{'id': 1, 'status': 1},
          <String, dynamic>{'id': 2, 'status': 0},
          <String, dynamic>{'id': 3, 'status': 0},
        ],
      });

      expect(d.verificationStatus, 1, reason: '后端确实置了位');
      expect(d.pendingCount, 2, reason: '但还欠 2 章,不能当已完成');
    });

    test('失效章节不计入待核销(退款/取消释放容量)', () {
      final d = RegistrationDetail.fromJson(<String, dynamic>{
        'id': 9003,
        'ownerType': 2,
        'ownerId': 1,
        'entitlements': <dynamic>[
          <String, dynamic>{'id': 1, 'status': 0},
          <String, dynamic>{'id': 2, 'status': 2, 'invalidReason': 'REFUND'},
        ],
      });
      expect(d.pendingCount, 1);
      expect(d.entitlements[1].isInvalid, isTrue);
      expect(d.entitlements[1].invalidReason, 'REFUND');
    });

    test('边界:非 ③ 票无 entitlements 字段 → 空列表,isExplorePass=false', () {
      final d = RegistrationDetail.fromJson(<String, dynamic>{
        'id': 9004,
        'ownerType': 2,
        'ownerId': 1,
        'purchaseKind': 'NORMAL',
        'cmsTopic': <String, dynamic>{'name': '经典定向'},
      });
      expect(d.entitlements, isEmpty);
      expect(d.pendingCount, 0);
      expect(d.isExplorePass, isFalse);
      // cmsActivity 缺失时回落 cmsTopic 取名。
      expect(d.title, '经典定向');
    });
  });

  group('MyRegistration 的 ③ 判别与票夹筛选', () {
    MyRegistration mk(Object? productType) =>
        MyRegistration.fromJson(<String, dynamic>{
          'id': 1,
          'ownerType': 2,
          'ownerId': 2,
          'cmsActivity': <String, dynamic>{
            'name': '局',
            if (productType != null) 'productType': productType,
          },
        });

    test('productType=2 ⇒ 是探店日,票夹展示', () {
      final r = mk(2);
      expect(r.productType, 2);
      expect(r.isFreeExplore, isTrue);
      expect(r.isClassicOriented, isFalse);
      expect(r.shouldShowInApp, isTrue);
    });

    test('★★ productType=1(经典定向)也**必须**在票夹里显示', () {
      // ⚠️ 这条断言 2026-08-20 翻过面。原来锁的是「票夹隐藏 ①」,
      //   依据是 08-18 的「App 只做 ③」——而用户在 **08-19 推翻了它**:
      //   「我需要的是全部一致」「全部做 没有不做的」。
      //
      // ★ 藏 ① 的后果不是「少一个入口」,是**玩家付了钱看不到自己的票**。
      //   本文件下面那条 NULL 的断言早就写着这句话,当时范围说别管 ①。
      //
      // ★ 而且藏的是跑得动的东西:App 游玩页走
      //   `activityId → /api/play/nodes → 扫码打卡`,后端那个端点
      //   不按 productType 分支,① 的核心循环本来就实现了。
      final r = mk(1);
      expect(r.isClassicOriented, isTrue, reason: '类型判定本身不变');
      expect(r.isFreeExplore, isFalse);
      expect(r.shouldShowInApp, isTrue, reason: '谁再把 ① 滤掉,买了经典定向票的玩家就在票夹里找不到它');
    });

    test('★ productType 缺失(生产存量 NULL)⇒ fail-open,仍然展示', () {
      // 第 0 批 0-5 未回填前,本该是 ③ 的票 product_type 可能为 NULL。
      // 若谁把 shouldShowInApp 收紧成 isFreeExplore,玩家买了票却在票夹
      // 里找不到 —— 这条断言就是拦那个改法的。
      final r = mk(null);
      expect(r.productType, isNull);
      expect(r.isFreeExplore, isFalse, reason: '未知不等于 ③');
      expect(r.isClassicOriented, isFalse, reason: '未知也不等于 ①');
      expect(r.shouldShowInApp, isTrue, reason: '未知一律展示,宁可多显示不可漏');
    });

    test('后端把数字返成字符串时正确解析(契约:数字可能 int/long/String)', () {
      expect(mk('2').productType, 2);
      expect(mk('2').isFreeExplore, isTrue);
      expect(mk('1').isClassicOriented, isTrue);
      // 这里只测解析,展示与否见上面那条(2026-08-20 起 ① 也展示)。
      expect(mk('1').shouldShowInApp, isTrue);
    });

    test('解析不了的脏值落成 null,走 fail-open 而不是崩', () {
      final r = mk('abc');
      expect(r.productType, isNull);
      expect(r.shouldShowInApp, isTrue);
    });
  });

  group('TicketState 判定与文案(对齐小程序 signup wxs)', () {
    MyRegistration mk({int? reg, int? verify}) =>
        MyRegistration.fromJson(<String, dynamic>{
          'id': 1,
          'ownerType': 2,
          'ownerId': 2,
          if (reg != null) 'registrationStatus': reg,
          if (verify != null) 'verificationStatus': verify,
        });

    test('已核验 → done', () {
      expect(mk(reg: 2, verify: 1).ticketState, TicketState.done);
    });

    test('已取消 → voided', () {
      expect(mk(reg: 3).ticketState, TicketState.voided);
    });

    test('已过期(4)→ voided —— wxs state() 的 3||4 同归 void', () {
      expect(mk(reg: 4).ticketState, TicketState.voided);
      // wxs label() 在 void 里再分档:4 写「已过期」,其余写「已取消」。
      expect(mk(reg: 4).ticketStatusLabel, '已过期');
      expect(mk(reg: 3).ticketStatusLabel, '已取消');
      expect(mk(reg: 2).ticketStatusLabel, '待使用');
    });

    test('已报名未核验 → ready', () {
      expect(mk(reg: 2, verify: 0).ticketState, TicketState.ready);
    });

    test('其余 → pending', () {
      expect(mk(reg: 1).ticketState, TicketState.pending);
      expect(mk().ticketState, TicketState.pending);
    });

    test('★ 判定顺序:已核验优先于已取消,不可重排', () {
      // 核验完之后又被取消的票,小程序显示「已核验」而不是「已取消」。
      // 若把 registrationStatus==3 的判断挪到前面,这条会红。
      expect(
        mk(reg: 3, verify: 1).ticketState,
        TicketState.done,
        reason: 'verificationStatus 的判断必须在 registrationStatus 之前',
      );
    });

    test('文案与小程序 wxs 逐字一致', () {
      expect(TicketState.done.label, '已核验');
      expect(TicketState.voided.label, '已取消');
      expect(TicketState.ready.label, '待使用');
      expect(TicketState.pending.label, '待支付');
      // 票根右侧动作提示,真源 wxs `cta()` 三态逐字:
      // ready→进入游玩 / pending→去支付 / 其余不出 CTA。
      // 「查看详情」那条指订单页的路已由用户 2026-09-10 关掉(待支付是唯一例外)。
      expect(TicketState.ready.cta, '进入游玩 ›');
      expect(TicketState.pending.cta, '去支付 ›');
      expect(TicketState.done.cta, '');
      expect(TicketState.voided.cta, '');
    });
  });

  group('Activity / ActivityDetail 的 ③ 判别(后端 #739 透出 productType)', () {
    Activity mkA(Object? pt) => Activity.fromJson(<String, dynamic>{
      'id': 1,
      'name': '局',
      if (pt != null) 'productType': pt,
    });

    test('productType=2 ⇒ 探店日,列表展示', () {
      expect(mkA(2).isFreeExplore, isTrue);
      expect(mkA(2).shouldShowInApp, isTrue);
    });

    test('★★ productType=1(经典定向)也**必须**在列表里显示', () {
      // 同票夹那条:08-18「只做 ③」已被用户 08-19 推翻为「全部一致」。
      // 活动列表藏 ① 的后果是玩家根本发现不了这类局。
      expect(mkA(1).isClassicOriented, isTrue, reason: '类型判定本身不变');
      expect(mkA(1).shouldShowInApp, isTrue);
    });

    test('★ productType 缺失 ⇒ fail-open,仍展示(与票夹同口径)', () {
      final a = mkA(null);
      expect(a.productType, isNull);
      expect(a.shouldShowInApp, isTrue, reason: '存量 NULL 主题不能被藏掉，宁可多显示');
    });

    test('数字返成字符串也能解析', () {
      expect(mkA('2').productType, 2);
      expect(mkA('1').shouldShowInApp, isTrue);
    });

    test('ActivityDetail 同样解析 productType', () {
      final d = ActivityDetail.fromJson(<String, dynamic>{
        'id': 9,
        'name': '局',
        'productType': 2,
      });
      expect(d.isFreeExplore, isTrue);
    });
  });

  group('DynCode.fromJson (/api/verify/dyncode/issue)', () {
    test('正常解析:含二维码 URL 与后端下发的绝对过期时间', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final c = DynCode.fromJson(<String, dynamic>{
        'code': 'CY.9001.activity.abc123',
        'qrcodeUrl': 'https://oss/qrcode/20260818/x.png',
        'ttlMs': 300000,
        'expiresAt': now + 300000,
        'type': 'activity',
      });

      expect(c.code, 'CY.9001.activity.abc123');
      expect(c.qrcodeUrl, 'https://oss/qrcode/20260818/x.png');
      expect(c.ttlMs, 300000);
      expect(c.type, 'activity');
      expect(c.isExpired, isFalse);
      // 倒计时按 expiresAt 绝对时间算,允许执行耗时的少量偏差。
      expect(c.remaining().inSeconds, greaterThan(290));
    });

    test('已过期:remaining 归零不返回负数', () {
      final c = DynCode.fromJson(<String, dynamic>{
        'code': 'X',
        'expiresAt': DateTime.now().millisecondsSinceEpoch - 60000,
      });
      expect(c.isExpired, isTrue);
      expect(c.remaining(), Duration.zero);
    });

    test('边界:出图失败时 qrcodeUrl 为 null,code 仍可用于文本回落', () {
      final c = DynCode.fromJson(<String, dynamic>{
        'code': 'CY.FALLBACK',
        'qrcodeUrl': null,
        'expiresAt': DateTime.now().millisecondsSinceEpoch + 1000,
      });
      expect(c.qrcodeUrl, isNull);
      expect(c.code, 'CY.FALLBACK');
    });
  });
}
