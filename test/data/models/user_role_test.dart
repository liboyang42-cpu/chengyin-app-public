// 身份解析必须与后端 / 小程序**逐字同口径**。
//
// 真源三份,必须一致:
//   后端  chengyinhub-system/.../RoleServiceImpl.java:38-55  resolveRole
//   小程序 chengyinhub-xcx/utils/identity/identity-policy.js  resolveRole
//   App   lib/data/models/user.dart                          effectiveRole
//
// ★ 为什么值得单独一组测试:三端不一致**不会报错**,只会让同一个账号在
//   小程序里是商家视角、在 App 里是玩家视角 —— 少一批入口、主题还从浅色变深色。
//   App 此前把 userType 整个丢掉,并把缺席的 role 兜成 'player',正是这个毛病。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/user.dart';

User _u(Map<String, dynamic> json) => User.fromJson(<String, dynamic>{
      'id': 1,
      'nickname': '阿兰',
      ...json,
    });

void main() {
  group('effectiveRole 镜像 RoleServiceImpl.resolveRole', () {
    test('role 非空时优先,userType 不参与', () {
      // ★ 这一条是关键:role='player' 且 userType=2 —— 后端返 'player'。
      //   写成「userType==2 就是商家」会在这里判错。
      expect(_u({'role': 'player', 'userType': 2}).effectiveRole, 'player');
      expect(_u({'role': 'club', 'userType': 2}).effectiveRole, 'club');
      expect(_u({'role': 'merchant', 'userType': 1}).effectiveRole, 'merchant');
    });

    test('role 缺席时按 userType==2 兜底判商家', () {
      expect(_u({'userType': 2}).effectiveRole, 'merchant');
      expect(_u({'role': '', 'userType': 2}).effectiveRole, 'merchant');
    });

    test('role 缺席且 userType 不是 2 → player', () {
      expect(_u({'userType': 1}).effectiveRole, 'player');
      expect(_u({'userType': 0}).effectiveRole, 'player');
      // userType 完全缺席(AppUser 那套结构不下发它)
      expect(_u({}).effectiveRole, 'player');
    });

    test('★ userType 是字符串 "2" 也要认', () {
      // 小程序注释写明「storage 里可能是 number 2 或字符串 '2'」,
      // 后端 JSON 走 Long 但两套结构不一致过。松散匹配是有意的。
      expect(_u({'userType': '2'}).effectiveRole, 'merchant');
    });

    test('★ role 不再被解析层兜成 player —— 缺席与「确实是玩家」必须可分', () {
      // 这是整组测试的地基:兜了就没法判 userType 该不该生效。
      expect(_u({'userType': 2}).role, '');
      expect(_u({'role': 'player'}).role, 'player');
    });
  });

  group('isMerchantView 决定 8 个条件浅色页的主题', () {
    test('只有 merchant 视角是浅色', () {
      expect(_u({'role': 'merchant'}).isMerchantView, isTrue);
      expect(_u({'userType': 2}).isMerchantView, isTrue);
      expect(_u({'role': 'player'}).isMerchantView, isFalse);
      // ★ club(俱乐部主理人)**不是**商家视角 —— 小程序侧 isClubView 是
      //   另一个函数,两者不能合并。合并会让主理人看到浅色商家皮。
      expect(_u({'role': 'club'}).isMerchantView, isFalse);
    });
  });
}
