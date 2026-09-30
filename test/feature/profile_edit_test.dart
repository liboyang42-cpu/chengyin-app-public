import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/profile_edit.dart';

void main() {
  group('★ 昵称必填 —— 后端不校验,前端是唯一一道', () {
    test('空 / 全空格都挡住', () {
      expect(const ProfileEditForm().canSubmit, isFalse);
      expect(const ProfileEditForm(name: '   ').canSubmit, isFalse);
      expect(const ProfileEditForm().blocker, '昵称不能为空');
    });
    test('有昵称就放行', () {
      expect(const ProfileEditForm(name: '阿岚').canSubmit, isTrue);
      expect(const ProfileEditForm(name: '阿岚').blocker, isNull);
    });
  });

  group('★ 没改动就别提交', () {
    const orig = ProfileEditForm(name: '阿岚', introduction: '爱走路');
    test('完全一样 → 没改动', () {
      expect(orig.changedFrom(orig), isFalse);
    });
    test('只是多了空格 → 仍算没改动', () {
      expect(orig.copyWith(name: ' 阿岚 ').changedFrom(orig), isFalse,
          reason: '白提交一次会触发一次内容安全审核,可能因历史文案被拒');
    });
    test('任一字段真变了 → 算改动', () {
      expect(orig.copyWith(name: '阿蓝').changedFrom(orig), isTrue);
      expect(orig.copyWith(introduction: '爱骑车').changedFrom(orig), isTrue);
      expect(orig.copyWith(avatar: 'http://x/a.jpg').changedFrom(orig), isTrue);
      expect(orig.copyWith(wechat: 'abc').changedFrom(orig), isTrue);
    });
  });

  group('★ 内容被拒 ≠ 网络故障', () {
    test('内容类措辞识别得出', () {
      for (final String m in <String>[
        '内容含有违规信息',
        '简介包含敏感词',
        '昵称不合规',
        '内容审核未通过',
      ]) {
        expect(isContentRejected(m), isTrue, reason: m);
      }
    });
    test('故障类不能被误判成内容问题', () {
      for (final String m in <String>['网络异常', '请稍后重试', '服务不可用']) {
        expect(isContentRejected(m), isFalse,
            reason: '$m 被判成内容问题的话,就不给重试了 —— 那是另一个方向的坏');
      }
    });
    test('「网络」优先于内容词 —— 混合措辞按故障处理', () {
      expect(isContentRejected('网络异常,内容未提交'), isFalse);
    });
  });

  group('提交体', () {
    test('文本字段两端空白裁掉', () {
      const f = ProfileEditForm(
          name: '  阿岚  ', introduction: ' 爱走路 ', wechat: ' abc ');
      final j = f.toJson();
      expect(j['name'], '阿岚');
      expect(j['introduction'], '爱走路');
      expect(j['wechat'], 'abc');
    });
  });
}
