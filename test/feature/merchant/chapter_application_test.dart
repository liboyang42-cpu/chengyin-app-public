import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/chapter_application.dart';

void main() {
  ChapterApplication a({int status = 0, int source = 0, String? remark}) =>
      ChapterApplication.fromJson(<String, dynamic>{
        'id': 1,
        'status': status,
        'source': source,
        'auditRemark': remark,
      });

  group('★ 邀请 = 预先批准的申请,但要分开说', () {
    test('自己申请通过 → 「已通过」', () {
      expect(a(status: 1).statusText, '已通过');
    });
    test('★ 主办方邀请 → 说清是被邀请的', () {
      expect(a(status: 1, source: 1).statusText, '主办方已邀请你承接',
          reason: '说「已通过」商家会以为自己申请过,其实没有');
    });
  });

  group('★ 被拒必须说原因', () {
    test('有备注 → 带出来', () {
      expect(a(status: 2, remark: '门店照片不清晰').statusText, '已拒绝:门店照片不清晰');
    });
    test('没备注 → 兜底,不显示空冒号', () {
      expect(a(status: 2).statusText, '已拒绝');
      expect(a(status: 2, remark: '  ').statusText, '已拒绝');
    });
  });

  group('★ 只有自己申请的、审核中的能撤', () {
    test('审核中且是自己申请 → 能撤', () {
      expect(a().canWithdraw, isTrue);
    });
    test('★ 主办方邀请的不该由商家撤', () {
      expect(a(source: 1).canWithdraw, isFalse);
    });
    test('已通过 / 已拒绝都撤不了', () {
      expect(a(status: 1).canWithdraw, isFalse);
      expect(a(status: 2).canWithdraw, isFalse);
    });
  });

  group('点位免审', () {
    test('邀请来的免审(后端注释明说)', () {
      expect(a(source: 1).nodeNeedsAudit, isFalse);
    });
    test('自己申请的要审', () {
      expect(a().nodeNeedsAudit, isTrue);
    });
  });

  group('标题', () {
    test('两截都有 → 用 · 连接', () {
      final x = ChapterApplication.fromJson(<String, dynamic>{
        'id': 1,
        'topicName': '夜跑咖啡',
        'chapterName': '第一章',
      });
      expect(x.displayTitle, '夜跑咖啡 · 第一章');
    });
    test('只有一截 → 不带分隔符', () {
      expect(
          ChapterApplication.fromJson(
                  <String, dynamic>{'id': 1, 'topicName': '夜跑咖啡'})
              .displayTitle,
          '夜跑咖啡');
    });
    test('都没有 → 兜底,不是「 · 」', () {
      expect(ChapterApplication.fromJson(<String, dynamic>{'id': 1}).displayTitle,
          '承接申请');
    });
  });
}
