import 'package:chengyin_app/data/api/square_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/square_draft.dart';

void main() {
  group('★ 正文必填,图片可选', () {
    test('空正文挡住', () {
      expect(const SquareDraft().canSubmit, isFalse);
      expect(const SquareDraft(contents: '   ').canSubmit, isFalse);
      expect(const SquareDraft().blocker, '写点什么再发吧');
    });
    test('只有图片没正文,后端也会拒 —— 前端先拦', () {
      const d = SquareDraft(pics: <String>['a.jpg']);
      expect(d.canSubmit, isFalse, reason: '后端 :442「请输入发布内容」,图片不算内容');
    });
    test('有正文就能发', () {
      expect(const SquareDraft(contents: '今天走了六个点').canSubmit, isTrue);
    });

    test('不完整内容可以存草稿但不能发布', () {
      expect(const SquareDraft(pics: <String>['a.jpg']).canSave, isTrue);
      expect(
        const SquareDraft(
          contents: '还没选回复人',
          commentPolicy: 'MENTIONED',
        ).canSave,
        isTrue,
      );
      expect(const SquareDraft().canSave, isFalse);
    });
  });

  group('★ 关联态必须自洽', () {
    test('dataType=0 无需 dataId', () {
      expect(const SquareDraft(dataType: 0).linkConsistent, isTrue);
    });
    test('仅提及者回复必须选人', () {
      const missing = SquareDraft(contents: 'x', commentPolicy: 'MENTIONED');
      expect(missing.canSubmit, isFalse);
      expect(missing.blocker, '请先选择可以回复的人');

      const complete = SquareDraft(
        contents: 'x',
        commentPolicy: 'MENTIONED',
        mentionedMemberIds: <int>[11],
      );
      expect(complete.canSubmit, isTrue);
    });
    test('说了要关联却没 id → 不自洽', () {
      expect(
        const SquareDraft(dataType: 1).linkConsistent,
        isFalse,
        reason: '后端会存下一条指向空的记录',
      );
      expect(const SquareDraft(dataType: 2, dataId: 0).linkConsistent, isFalse);
    });
    test('齐了才自洽', () {
      expect(const SquareDraft(dataType: 1, dataId: 9).linkConsistent, isTrue);
    });
  });

  group('★ 取消关联要同时清两个字段', () {
    test('withoutLink 同时清 dataId 与 dataType', () {
      const d = SquareDraft(contents: 'x', dataType: 1, dataId: 9);
      final n = d.withoutLink();
      expect(n.dataId, isNull);
      expect(n.dataType, 0);
      expect(n.linkConsistent, isTrue);
      expect(n.contents, 'x', reason: '别把正文一起清了');
    });
    test('withoutLink 同时清理新关联并退出社区可见性', () {
      const d = SquareDraft(
        contents: 'x',
        referenceType: 'CLUB',
        referenceId: 18,
        communityId: 18,
        audience: 'COMMUNITY',
      );
      final n = d.withoutLink();
      expect(n.referenceType, isNull);
      expect(n.referenceId, isNull);
      expect(n.communityId, isNull);
      expect(n.audience, 'PUBLIC');
      expect(n.linkConsistent, isTrue);
    });
    test('withoutLink 也会退出仅社群成员回复', () {
      const d = SquareDraft(
        contents: 'x',
        referenceType: 'CLUB',
        referenceId: 18,
        communityId: 18,
        commentPolicy: 'MEMBERS',
      );

      expect(d.withoutLink().commentPolicy, 'EVERYONE');
    });
    test('编辑草稿取消关联不丢版本和既有媒体', () {
      const d = SquareDraft(
        workflowId: 'edit-workflow',
        id: 7,
        expectedVersion: 4,
        contents: 'x',
        pics: <String>['old.jpg'],
        existingMediaIds: <int>[31],
        existingPicCount: 1,
        referenceType: 'ROUTE',
        referenceId: 66,
      );

      final n = d.withoutLink();

      expect(n.id, 7);
      expect(n.expectedVersion, 4);
      expect(n.pics, <String>['old.jpg']);
      expect(n.existingMediaIds, <int>[31]);
      expect(n.existingPicCount, 1);
    });
    test('copyWith 做不到 —— 它把 null 当"不改"', () {
      const d = SquareDraft(contents: 'x', dataType: 1, dataId: 9);
      // 这行是**反例**:copyWith(dataId: null) 不会清空。
      expect(
        d.copyWith(dataId: null).dataId,
        9,
        reason: '正因如此才需要专门的 withoutLink',
      );
    });
  });

  group('提交体', () {
    test('图片用英文分号连接', () {
      const d = SquareDraft(contents: 'x', pics: <String>['a.jpg', 'b.jpg']);
      expect(d.toForm()['pics'], 'a.jpg;b.jpg');
    });
    test('空图片列表不带 pics 字段', () {
      expect(
        const SquareDraft(contents: 'x').toForm().containsKey('pics'),
        isFalse,
      );
    });
    test('无 id 时不带 id(新增)', () {
      expect(
        const SquareDraft(contents: 'x').toForm().containsKey('id'),
        isFalse,
      );
      expect(const SquareDraft(id: 7, contents: 'x').toForm()['id'], '7');
    });
    test('dataId 为 0 不带出去', () {
      expect(
        const SquareDraft(
          contents: 'x',
          dataId: 0,
        ).toForm().containsKey('data_id'),
        isFalse,
      );
    });
    test('正文裁掉两端空白', () {
      expect(
        const SquareDraft(contents: '  今天走了六个点  ').toForm()['contents'],
        '今天走了六个点',
      );
    });
  });

  group('★ 发布失败三分:权限 / 内容 / 故障', () {
    test('不是自己的帖 → 不给重试', () {
      final e = SquarePublishException('无权编辑该内容');
      expect(e.isNotOwner, isTrue);
      expect(e.retryable, isFalse, reason: '重试一万次也不会变成自己的帖');
    });
    test('内容被审核拒 → 不给重试(要改文字)', () {
      for (final String m in <String>['内容含有违规信息', '涉及敏感词', '审核未通过']) {
        final e = SquarePublishException(m);
        expect(e.isContentRejected, isTrue, reason: m);
        expect(e.retryable, isFalse, reason: m);
      }
    });
    test('★ 真故障 → 给重试', () {
      for (final String m in <String>['网络异常', '请稍后重试', '服务不可用']) {
        final e = SquarePublishException(m);
        expect(e.retryable, isTrue, reason: '$m 该给重试');
        expect(
          e.isContentRejected,
          isFalse,
          reason: '$m 被判成内容问题就不给重试了 —— 另一个方向的坏',
        );
      }
    });
    test('混合措辞按故障处理(「网络」优先)', () {
      expect(SquarePublishException('网络异常,内容未提交').retryable, isTrue);
    });
  });
}
