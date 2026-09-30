import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

bool hasReportInElseBranch(String source) => RegExp(
  r'isOwner\s*\?\s*Semantics\([\s\S]{0,320}?onPressed:\s*_delete[\s\S]{0,320}?:\s*Semantics\([\s\S]{0,320}?onPressed:\s*_report',
).hasMatch(source);

/// UGC 审核能力门禁 —— **Apple 审核指南 1.2 的硬要求**。
///
/// 原文要求提供 UGC 的 App 必须具备:①过滤机制 ②举报入口 ③屏蔽滥用用户 ④公开联系方式。
/// 缺任何一条基本必被拒。
///
/// ★ 为什么写成门禁而不是「记得别删」:这些入口是**审核用的**,日常开发中
///   没有人会用到,重构时最容易被当成没用的代码顺手删掉 —— 删了也不会有
///   任何测试变红,直到提审被拒才发现。这就是它存在的理由。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('举报入口', () {
    test('广场动态详情页有举报', () {
      final src = read('lib/feature/square/square_detail_page.dart');
      expect(
        src.contains('.report(widget.postId)'),
        isTrue,
        reason: 'Apple 1.2:UGC 必须能举报,而且要真打到举报接口。删了提审会被拒',
      );
      expect(
        src.contains('cyConfirm('),
        isTrue,
        reason: '举报前要确认一次(与小程序 reportSquare 同口径)',
      );
    });

    test('评论也能单独举报', () {
      final src = read('lib/feature/square/square_detail_page.dart');
      expect(
        src.contains('.reportComment(commentId)'),
        isTrue,
        reason: '评论同样是 UGC;只给动态举报、评论没有,审核照样挑得出来',
      );
    });

    test('举报接口真实存在于 API 层', () {
      final String api = read('lib/data/api/square_api.dart');
      expect(api.contains("'/api/creativesquare/report'"), isTrue);
      expect(api.contains("'/api/comment/report'"), isTrue);
      expect(api.contains('reportComment'), isTrue);
    });
  });

  group('屏蔽用户', () {
    test('聊天页有拉黑', () {
      final src = read('lib/feature/im/im_chat_page.dart');
      expect(src.contains('_blockPeer'), isTrue, reason: 'Apple 1.2:必须能屏蔽滥用用户');
      expect(src.contains('imApiProvider).block'), isTrue);
    });

    test('拉黑用的是 memberId 不是 conversationId', () {
      final src = read('lib/feature/im/im_chat_page.dart');
      expect(
        src.contains('block(widget.peerMemberId)'),
        isTrue,
        reason:
            '后端 /api/im/block 要 target_member_id;'
            '传 conversationId 会拉黑到一个不存在的人或者报错',
      );
    });

    test('memberId 没带过来时不显示拉黑入口', () {
      final src = read('lib/feature/im/im_chat_page.dart');
      expect(
        src.contains('widget.peerMemberId > 0'),
        isTrue,
        reason: '摆一个点下去必然失败的按钮,比没有这个按钮更糟',
      );
    });

    test('会话列表把 memberId 传下去了', () {
      final src = read('lib/feature/im/im_list_page.dart');
      expect(
        src.contains("'memberId': cp.id.toString()"),
        isTrue,
        reason:
            '不传的话聊天页拿到 0,拉黑入口永远不显示 —— '
            '门禁会绿,但功能等于不存在',
      );
    });
  });

  group('★ 举报入口按归属分流 —— 别让人举报自己', () {
    // 原来详情页无条件显示「举报」:用户在自己的帖子上只能举报自己,
    // 而真正想做的「发错了想删掉」反倒没入口。专业广场统一走带版本 CAS 的软删除。
    final String page = File(
      'lib/feature/square/square_detail_page.dart',
    ).readAsStringSync();

    test('自己的动态给删除入口', () {
      expect(page.contains('_delete'), isTrue);
      expect(page.contains('CupertinoIcons.delete'), isTrue);
    });

    test('★ 举报与删除是二选一,不是都显示', () {
      // 判据:举报那个原生按钮落在 else 分支里。
      expect(
        hasReportInElseBranch(page),
        isTrue,
        reason: '举报入口应在 else 分支 —— 自己的帖只该看到删除',
      );
    });

    test('负控：没有 else 分流的举报按钮会被抓到', () {
      expect(
        hasReportInElseBranch(
          'Semantics(child: CupertinoButton(onPressed: _report))',
        ),
        isFalse,
      );
    });

    test('删除走 API 层,不是前端假删', () {
      final String api = File(
        'lib/data/api/square_api.dart',
      ).readAsStringSync();
      expect(api.contains('/api/v1/community/posts/'), isTrue);
      expect(api.contains('expectedVersion'), isTrue);
    });

    test('★ 删除前有确认 —— 软删在后端,前端拿不回来', () {
      expect(page.contains('cyConfirm'), isTrue);
      expect(page.contains("danger: true"), isTrue);
    });
  });

  group('★ IM:举报消息 / 免打扰 / 删除会话 —— 后端一直有,App 从没接', () {
    final String api = File('lib/data/api/im_api.dart').readAsStringSync();
    final String chat = File(
      'lib/feature/im/im_chat_page.dart',
    ).readAsStringSync();
    final String list = File(
      'lib/feature/im/im_list_page.dart',
    ).readAsStringSync();

    test('三条端点都接上了', () {
      expect(api.contains('/api/im/report'), isTrue);
      expect(api.contains('/api/im/mute'), isTrue);
      expect(api.contains('/api/im/delete'), isTrue);
    });

    test('★ 举报的是消息(message_id),不是会话', () {
      expect(
        api.contains("'message_id'"),
        isTrue,
        reason:
            'Apple 1.2 要的是能举报**具体内容**;'
            '按会话举报等于把整段对话打包丢给审核',
      );
    });

    test('★ 举报理由必须传到后端 —— 界面收了就不能半路扔掉', () {
      // 原来 showReportSheet 让用户选了理由,却只 pop(true),理由被丢在弹层里。
      expect(api.contains("'reason'"), isTrue);
      final String sheet = File(
        'lib/core/moderation/report_sheet.dart',
      ).readAsStringSync();
      expect(
        sheet.contains('Future<String?> showReportSheet'),
        isTrue,
        reason: '弹层应回选中的理由,不是一个 bool',
      );
      expect(
        sheet.contains('pop(true)'),
        isFalse,
        reason: 'pop(true) 会把用户选的理由扔掉',
      );
    });

    test('举报只对别人的消息开放 —— 举报自己没有意义', () {
      expect(
        chat.contains('isMine\n                    ? _Bubble'),
        isTrue,
        reason: '自己的气泡不该挂长按举报',
      );
    });

    test('★ 删除会话的文案要说清删的是哪一侧', () {
      expect(
        list.contains('不会清除对方消息记录'),
        isTrue,
        reason: '不说清的话,用户会以为是「撤回」——那是对用户撒谎',
      );
      // ⚠️ 只查**代码里的字符串字面量**,不查注释 ——
      //    注释里解释「不能写成撤回」是应该的,第一版把注释也扫进去了,自己红了自己。
      final String code = list
          .split('\n')
          .where((String l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(RegExp(r"'[^']*撤回[^']*'").hasMatch(code), isFalse);
      expect(RegExp(r"'[^']*已销毁[^']*'").hasMatch(code), isFalse);
    });
  });

  group('★ 俱乐部圈子:此前是纯只读,连举报入口都没有', () {
    final String api = File('lib/data/api/club_api.dart').readAsStringSync();
    final String page = File(
      'lib/feature/club/club_feed_page.dart',
    ).readAsStringSync();

    test('互动四条端点都接上了', () {
      for (final String e in <String>[
        '/api/club/post/like',
        '/api/club/post/create',
        '/api/club/post/delete',
        '/api/club/post/report',
      ]) {
        expect(api.contains(e), isTrue, reason: '$e 没接');
      }
    });

    test('★ 圈子帖有举报入口 —— Apple 1.2 对 UGC 是硬要求', () {
      expect(page.contains('showReportSheet'), isTrue);
    });

    test('★ 自己的帖给删除,别人的给举报', () {
      expect(page.contains('final bool mine'), isTrue);
      expect(page.contains('deletePost'), isTrue);
      expect(page.contains('reportPost'), isTrue);
    });

    test('★ 点赞不做本地乐观更新 —— 失败会留下一个假的已赞态', () {
      // 后端 like 是切换式的,调用方不传「想变成什么」,调完以服务端为准。
      expect(page.contains('ref.invalidate(clubFeedProvider)'), isTrue);
      expect(
        RegExp(r'setState\(\(\)\s*=>\s*\w*[Ll]iked').hasMatch(page),
        isFalse,
        reason: '本地先改再对账,请求失败时用户会看到一个没生效的赞',
      );
    });

    test('图片按分号拼 —— 后端存的是分号分隔字符串,传数组它不认', () {
      expect(api.contains("images.join(';')"), isTrue);
    });
  });

  group('文案诚实性', () {
    test('举报提示不许说「已下架」', () {
      final src = read('lib/core/moderation/report_sheet.dart');
      // 后端语义:举报只入审核队列,不立即下架。
      expect(
        src.contains('已下架'),
        isFalse,
        reason: '后端明确「举报只进统一审核队列,不立即下架」,说下架就是骗用户',
      );
      expect(
        src.contains('审核期间该内容仍可能可见'),
        isTrue,
        reason: '要主动说清楚,否则用户举报完看内容还在会以为没生效',
      );
    });
  });
}
