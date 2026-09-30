import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/my_project.dart';

void main() {
  MyProject p(Map<String, dynamic> m) => MyProject.fromJson(<String, dynamic>{
    'title': 'X',
    'bizType': 'topic',
    ...m,
  });

  group('★ 有人报名就不给删', () {
    test('0 报名 → 可删', () {
      expect(p(<String, dynamic>{}).deletable, isTrue);
      expect(p(<String, dynamic>{}).deleteBlockedReason, isNull);
    });
    test('有报名 → 不可删,并说清原因', () {
      final x = p(<String, dynamic>{'signupCount': 3});
      expect(x.deletable, isFalse);
      expect(x.deleteBlockedReason, '已有 3 人报名,不能删除');
    });
  });

  group('★ 数据全为 0 时整行不显示', () {
    test('刚发布的不显示「0 报名 · 0 浏览」', () {
      expect(
        p(<String, dynamic>{}).statsText,
        isNull,
        reason: '对刚发布的内容是噪音,还显得很惨',
      );
    });
    test('只有浏览 → 只显示浏览', () {
      expect(p(<String, dynamic>{'viewCount': 12}).statsText, '12 浏览');
    });
    test('都有 → 用 · 连接', () {
      expect(
        p(<String, dynamic>{'signupCount': 2, 'viewCount': 12}).statsText,
        '2 报名 · 12 浏览',
      );
    });
  });

  group('★ 三种业务各有各的端点', () {
    test('topic / activity / template 各不相同', () {
      final t = ProjectEndpoints.forBizType('topic')!;
      final a = ProjectEndpoints.forBizType('activity')!;
      final m = ProjectEndpoints.forBizType('template')!;
      expect(<String>{t.delete, a.delete, m.delete}.length, 3);
      expect(
        <String>{t.toggleStatus, a.toggleStatus, m.toggleStatus}.length,
        3,
      );
    });
    test('template 的上下架是 updateLibraryStatus(语义是入库/出库)', () {
      expect(
        ProjectEndpoints.forBizType('template')!.toggleStatus,
        '/api/template/updateLibraryStatus',
      );
    });
    test('★ 未知类型返回 null —— 不猜端点', () {
      expect(
        ProjectEndpoints.forBizType('whatever'),
        isNull,
        reason: '猜一个端点去调,是在拿用户的数据赌',
      );
      expect(ProjectEndpoints.forBizType(''), isNull);
    });
  });

  group('解析', () {
    test('未知或缺失 bizType 不冒充 topic', () {
      expect(p(<String, dynamic>{'bizType': 'future'}).detailRoute, isNull);
      expect(
        MyProject.fromJson(<String, dynamic>{'title': 'X'}).bizType,
        isEmpty,
      );
    });
    test('三种已知 bizType 有各自详情路由', () {
      expect(p(<String, dynamic>{}).detailRoute, '/topic/0');
      expect(
        p(<String, dynamic>{'bizType': 'activity'}).detailRoute,
        '/activity/0',
      );
      expect(
        p(<String, dynamic>{'bizType': 'template'}).detailRoute,
        '/template/0',
      );
    });
    test('publishStatus 只认 online', () {
      expect(p(<String, dynamic>{'publishStatus': 'online'}).isOnline, isTrue);
      expect(
        p(<String, dynamic>{'publishStatus': 'offline'}).isOnline,
        isFalse,
      );
      expect(p(<String, dynamic>{}).isOnline, isFalse);
    });
    test('类型文案用后端的,不自己映射', () {
      expect(
        p(<String, dynamic>{'projectTypeText': '探店日'}).projectTypeText,
        '探店日',
      );
    });
    test('标题兜底', () {
      expect(p(<String, dynamic>{'title': '  '}).title, '未命名');
    });
  });
}
