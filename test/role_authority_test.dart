// 门禁:能力判定必须读后端的单一事实源,不许在客户端自己推。
//
// ★★ 后端 `/api/role/info` 的注释原话:
//   「下发三端能力位全集,前端 roleGuard 一律读这里」。
//
//   App 此前是自己从 role / userType 推能力 —— 那是第二份判据,必然和后端漂。
//   **实测已经漂了一处**:
//     后端 canCreateClub = !isMerchant && ownedClubCount < 2
//     App  用 effectiveRole == 'club' 一律拦死
//   ⇒ 已是主理人、但还没建满 2 个的人被挡在外面,还被告知"已成为主理人"。
//
// ★ 这条盯的是**能力判定**(canXxx / 配额),不是**视觉分流**。
//   `isMerchantView` 决定用哪套配色、进哪个视角,那是展示问题,
//   本地推是合理的 —— 所以不在禁用之列。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

void main() {
  test('★★ 不许用 role 字面量替代后端的能力位', () {
    // 这些是后端 permission 里的键;客户端出现"用 role 判它"的写法就是在推。
    const List<String> capabilityWords = <String>[
      'canCreateClub',
      'canCreateTheme',
      'canPublishCoupon',
      'canDesignMedal',
    ];

    final List<String> offenders = <String>[];
    int scanned = 0;

    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.endsWith('role_info.dart')) continue; // 模型本身
      if (e.path.endsWith('role_provider.dart')) continue;
      scanned++;
      final String code = codeOf(e.path);
      for (final String cap in capabilityWords) {
        if (!code.contains(cap)) continue;
        // 出现能力位的地方,必须是从 RoleInfo 读的(can('xxx') 或 permission[...])。
        final bool readsAuthority =
            code.contains("can('$cap')") || code.contains("permission['$cap']");
        if (!readsAuthority) {
          offenders.add('${e.path}  提到 $cap 却不是从 RoleInfo 读的');
        }
      }
    }

    expect(scanned, greaterThan(50), reason: '只扫到 $scanned 个文件 —— 目录变了?');
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('★★ 主理人申请页用 canCreateClub,不用 effectiveRole', () {
    final String code = codeOf('lib/feature/club/club_apply_page.dart');
    expect(code.contains("can('canCreateClub')"), isTrue);
    expect(code.contains("user.effectiveRole == 'club'"), isFalse,
        reason: '已是主理人但没建满 2 个的人会被挡在外面');
  });

  test('★ 还没读到身份时不预判 —— 别把人挡在一个还不知道结论的门外', () {
    final String code = codeOf('lib/feature/club/club_apply_page.dart');
    expect(code.contains('if (role != null && !role.can'), isTrue,
        reason: 'role 为 null(还在读)时不该走进拦截分支');
  });

  test('★ 建满上限时说清是「建满了」,不说「已成为主理人」', () {
    final String code = codeOf('lib/feature/club/club_apply_page.dart');
    final int quotaStart = code.indexOf('final bool quotaFull');
    final int formStart = code.indexOf('return ClubStepScaffold', quotaStart);
    final String quotaBranch = code.substring(quotaStart, formStart);
    expect(quotaBranch.contains('达到上限'), isTrue);
    expect(quotaBranch.contains('已成为主理人'), isFalse,
        reason: '那句话会让人以为功能没了,而其实是配额用完了');
  });
}
