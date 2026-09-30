// 门店 NPC:提交前校验、状态判定、对话结果解析、requestId 格式。
//
// ★★ requestId 那组是最容易被当成"随便生成一串就行"的:后端用正则卡死
//   UUID 的版本位与 variant 位,格式不对直接 INVALID_REQUEST,
//   表现是"发一句就说格式不正确",而客户端看起来一切正常。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';

/// 与后端 `NpcChatService.UUID_PATTERN` 逐字一致。
/// ⚠️ 抄一份而不是引用:后端改了这里必须跟着改,
///   而"跟着改"这件事只有在两边都写死时才会被测试逼出来。
final RegExp _backendUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}'
  r'-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

MerchantNpcProfile _valid() => const MerchantNpcProfile(
  name: '老周',
  avatar: 'https://example.com/a.png',
  persona: '你是老周,说话慢',
);

void main() {
  group('提交前校验', () {
    test('齐全时可提交', () {
      expect(_valid().canSubmit, isTrue);
      expect(_valid().blocker, isNull);
    });

    test('★ 人设必填 —— 空人设的形象被点开对话时后端会拒,要在填的时候就说', () {
      final p = _valid().copyWith(persona: '   ');
      expect(p.canSubmit, isFalse);
      expect(p.blocker, contains('说话风格'));
    });

    test('头像必填', () {
      expect(_valid().copyWith(avatar: null).blocker, contains('头像'));
    });

    test('名字必填且不超 20 字', () {
      expect(_valid().copyWith(name: '  ').blocker, contains('名字'));
      expect(_valid().copyWith(name: '名' * 21).blocker, contains('20'));
      expect(_valid().copyWith(name: '名' * 20).canSubmit, isTrue);
    });

    test('店铺知识可空,但不超 2000 字', () {
      expect(_valid().copyWith(knowledge: null).canSubmit, isTrue);
      expect(
        _valid().copyWith(knowledge: '知' * 2001).blocker,
        contains('2000'),
      );
    });

    test('招呼语可空,但不超 60 字', () {
      expect(_valid().copyWith(greeting: null).canSubmit, isTrue);
      expect(_valid().copyWith(greeting: '呼' * 61).blocker, contains('60'));
    });
  });

  group('审核状态', () {
    test('★ 没配过时后端回 configured:false 空壳,不是 null —— 客户端不必区分"失败"与"没配过"', () {
      final p = MerchantNpcProfile.fromJson(<String, dynamic>{
        'configured': false,
      });
      expect(p.configured, isFalse);
      expect(p.profileId, isNull);
    });

    test('auditStatus 缺席按待审 —— 未知状态不得当成已上线', () {
      final p = MerchantNpcProfile.fromJson(<String, dynamic>{
        'configured': true,
        'name': '老周',
      });
      expect(p.isPending, isTrue);
      expect(p.isApproved, isFalse);
    });

    test('0/1/2 三态互斥', () {
      MerchantNpcProfile at(int v) => MerchantNpcProfile.fromJson(
        <String, dynamic>{'configured': true, 'auditStatus': v},
      );
      expect(at(0).isPending, isTrue);
      expect(at(1).isApproved, isTrue);
      expect(at(2).isRejected, isTrue);
      expect(at(1).isPending, isFalse);
    });

    test('★ 状态文案取后端下发的,客户端不自己拼 —— 两端各写一套会出现两种说法', () {
      final p = MerchantNpcProfile.fromJson(<String, dynamic>{
        'configured': true,
        'auditStatus': 0,
        'statusText': '审核中,通过后玩家才能看到',
      });
      expect(p.statusText, '审核中,通过后玩家才能看到');
    });
  });

  group('对话结果', () {
    test('SUCCEEDED 显示 safeText', () {
      final r = NpcChatResult.fromJson(<String, dynamic>{
        'outcomeStatus': 'SUCCEEDED',
        'safeText': '试试椰香拿铁',
      });
      expect(r.succeeded, isTrue);
      expect(r.displayText, '试试椰香拿铁');
    });

    test('★ 未知/缺席状态按 FAILED —— 认不出的终态不得当成成功', () {
      expect(
        NpcChatResult.fromJson(<String, dynamic>{}).succeeded,
        isFalse,
      );
      expect(
        NpcChatResult.fromJson(<String, dynamic>{
          'outcomeStatus': 'WHATEVER',
        }).succeeded,
        isFalse,
      );
    });

    test('★ retryable 决定给不给重试钮 —— 合规类拒绝重试永远不会成功', () {
      final blocked = NpcChatResult.fromJson(<String, dynamic>{
        'outcomeStatus': 'REJECTED',
        'errorCode': 'INPUT_BLOCK',
        'retryable': false,
        'safeText': '这条消息暂时无法处理,请换个说法。',
      });
      expect(blocked.retryable, isFalse);

      final busy = NpcChatResult.fromJson(<String, dynamic>{
        'outcomeStatus': 'FAILED',
        'errorCode': 'AI_UNAVAILABLE',
        'retryable': true,
      });
      expect(busy.retryable, isTrue);
    });

    test('PROCESSING 是并发重放,不是终态', () {
      final r = NpcChatResult.fromJson(<String, dynamic>{
        'outcomeStatus': 'PROCESSING',
      });
      expect(r.inProgress, isTrue);
      expect(r.succeeded, isFalse);
    });

    test('safeText 缺席时兜底一句,不显示空气泡', () {
      final r = NpcChatResult.fromJson(<String, dynamic>{
        'outcomeStatus': 'FAILED',
      });
      expect(r.displayText.trim(), isNotEmpty);
    });
  });

  _voiceTests();
  _avatarTests();

  group('requestId', () {
    test('★★ 必须匹配后端那条正则 —— 版本位 4、variant 位 8/9/a/b', () {
      for (int i = 0; i < 200; i++) {
        final String id = newChatRequestId();
        expect(
          _backendUuidPattern.hasMatch(id),
          isTrue,
          reason: '第 $i 个不合格: $id',
        );
      }
    });

    test('每次都不同 —— 同一个 id 会被后端当成重放,返回上一条的结果', () {
      final Set<String> ids = <String>{
        for (int i = 0; i < 200; i++) newChatRequestId(),
      };
      expect(ids.length, 200);
    });
  });
}

// ===== P2 声音克隆 =====

void _voiceTests() {
  group('声音状态', () {
    test('★ hasVoice 缺席按没克隆过 —— 未知状态不得当成已有声音', () {
      final p = MerchantNpcProfile.fromJson(<String, dynamic>{
        'configured': true,
      });
      expect(p.hasVoice, isFalse);
    });

    test('hasVoice 只认 true;字符串 "true" 不算', () {
      expect(
        MerchantNpcProfile.fromJson(<String, dynamic>{'hasVoice': true})
            .hasVoice,
        isTrue,
      );
      expect(
        MerchantNpcProfile.fromJson(<String, dynamic>{'hasVoice': 'true'})
            .hasVoice,
        isFalse,
        reason: '后端回的是 JSON 布尔;认字符串会让别的字段误伤',
      );
    });
  });

  group('录音脚本', () {
    test('★★ available 缺席按未开放 —— 供应商没接就不该显示录音入口', () {
      expect(VoiceEnrollScript.fromJson(<String, dynamic>{}).available, isFalse);
    });

    test('解析五句 + 授权句下标', () {
      final s = VoiceEnrollScript.fromJson(<String, dynamic>{
        'available': true,
        'script': <String>['我同意…', '欢迎…', '招牌…', '往前走…', '卖完了…'],
        'consentIndex': 0,
      });
      expect(s.available, isTrue);
      expect(s.lines, hasLength(5));
      expect(s.isConsentLine(0), isTrue);
      expect(s.isConsentLine(1), isFalse);
    });

    test('空白句被滤掉 —— 空句子渲染出来是一张没内容的卡片', () {
      final s = VoiceEnrollScript.fromJson(<String, dynamic>{
        'script': <dynamic>['一句', '   ', null, '两句'],
      });
      expect(s.lines, <String>['一句', '两句']);
    });
  });

  group('回复语音', () {
    test('★ audioUrl 缺席是常态,不是错误', () {
      final r = NpcChatResult.fromJson(<String, dynamic>{
        'outcomeStatus': 'SUCCEEDED',
        'safeText': '试试椰香拿铁',
      });
      expect(r.succeeded, isTrue);
      expect(r.audioUrl, isNull);
    });

    test('空串 audioUrl 归一成 null —— 空串会让 UI 显示一个放不出声的按钮', () {
      expect(
        NpcChatResult.fromJson(<String, dynamic>{
          'outcomeStatus': 'SUCCEEDED',
          'audioUrl': '   ',
        }).audioUrl,
        isNull,
      );
    });

    test('有 audioUrl 时原样带回', () {
      expect(
        NpcChatResult.fromJson(<String, dynamic>{
          'outcomeStatus': 'SUCCEEDED',
          'audioUrl': 'https://oss/a.mp3',
        }).audioUrl,
        'https://oss/a.mp3',
      );
    });
  });
}

// ===== P3 3D 形象生成 =====

void _avatarTests() {
  group('生成任务状态', () {
    test('★★ 只有明确的 PENDING 才继续轮询 —— 认不出的状态转到天荒地老是最难查的一种坏', () {
      expect(
        NpcAvatarJob.fromJson(<String, dynamic>{'jobId': 1, 'status': 'PENDING'})
            .shouldKeepPolling,
        isTrue,
      );
      for (final String s in <String>['SUCCEEDED', 'FAILED', 'WHATEVER', '']) {
        expect(
          NpcAvatarJob.fromJson(<String, dynamic>{'jobId': 1, 'status': s})
              .shouldKeepPolling,
          isFalse,
          reason: '状态 "$s" 不该继续轮询',
        );
      }
    });

    test('★ status 缺席按 FAILED 而不是 PENDING —— 认不出的终态不该让人一直等', () {
      final j = NpcAvatarJob.fromJson(<String, dynamic>{'jobId': 1});
      expect(j.status, 'FAILED');
      expect(j.pending, isFalse);
      expect(j.shouldKeepPolling, isFalse);
    });

    test('成功带 modelUrl,失败带安全文案', () {
      final ok = NpcAvatarJob.fromJson(<String, dynamic>{
        'jobId': 1,
        'status': 'SUCCEEDED',
        'modelUrl': 'https://oss/a.glb',
        'thumbUrl': 'https://oss/a.png',
      });
      expect(ok.succeeded, isTrue);
      expect(ok.modelUrl, 'https://oss/a.glb');

      final bad = NpcAvatarJob.fromJson(<String, dynamic>{
        'jobId': 1,
        'status': 'FAILED',
        'failReason': '换一张更清楚的正面照片再试试',
      });
      expect(bad.succeeded, isFalse);
      expect(bad.failReason, contains('正面照片'));
    });
  });

  group('可用性', () {
    test('★★ available 缺席按未开放 —— 供应商没接就不该显示生成入口', () {
      expect(NpcAvatarStatus.fromJson(<String, dynamic>{}).available, isFalse);
    });

    test('没提交过时 job 是 null,不是一个假的空任务', () {
      final s = NpcAvatarStatus.fromJson(<String, dynamic>{
        'available': true,
        'styles': <String>['realistic', 'cartoon', 'pixel'],
      });
      expect(s.available, isTrue);
      expect(s.styles, hasLength(3));
      expect(s.job, isNull);
    });

    test('空白风格被滤掉 —— 空字符串会渲染成一个点不中的空按钮', () {
      final s = NpcAvatarStatus.fromJson(<String, dynamic>{
        'styles': <dynamic>['realistic', '  ', null, 'pixel'],
      });
      expect(s.styles, <String>['realistic', 'pixel']);
    });
  });

  group('形象的 3D 地址', () {
    test('★ modelUrl 缺席是常态(没生成过 / 没开通 / 失败),不是错误', () {
      final p = MerchantNpcProfile.fromJson(<String, dynamic>{
        'configured': true,
      });
      expect(p.modelUrl, isNull);
    });

    test('空串归一成 null —— 空串会让渲染层去加载一个空地址', () {
      expect(
        MerchantNpcProfile.fromJson(<String, dynamic>{'modelUrl': '   '}).modelUrl,
        isNull,
      );
    });
  });
}
