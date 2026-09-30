@Tags(<String>['needs-local-env'])
// ★★ 2026-09-05 补标 needs-local-env(此前漏标):本文件读 backendRepoPath() ——
//   仓库**外**的兄弟后端仓。dart_test.yaml 对该 tag 的定义就是「依赖本机的兄弟仓
//   (后端 / 小程序)、本机脚本或注入的密钥」,同类的 endpoint_reachability /
//   page_parity 一直是标着的,这三个是漏网。
//
//   ⚠️ 漏标的真实代价不是「多跑几条」:自托管 runner 与开发机是**同一台**,
//   所以 CI 上这些文件不会 skip,它们会去读 ~/Downloads/chengyin —— 那个仓有 16 个
//   worktree、内容随开发者切分支而变。CI 的绿因此取决于「此刻那个仓在哪个分支」,
//   而这既不可复现也没人会想到去查。2026-09-05 实测:CI 里 flutter test 跑完
//   2915 条后进程不退出、静默到 30 分钟超时,而同一条命令在同一个 workspace
//   手动跑 2 分 01 秒全过 —— 未报结果的正是这三个文件(23 条,与差额逐条吻合)。
//
//   本地仍照跑(开发机有那个兄弟仓),CI 上按 tag 排除。
library;

// 埋点客户端的三道闸,与后端 ApiAnalyticsController 同口径。
//
// ★★ 后端的校验是**整批同拒**:50 条里有一条不合规,**整批都不落库**,
//   而且只回一句错。所以闸必须搬到客户端发送前 ——
//   一条拼错的事件名会把同批 49 条正常埋点一起弄丢,还查不出是哪条。
//
// ★★ 白名单是**第二份清单**,天然会漂。所以有一条测试直接拿后端源码比 ——
//   后端加了新事件而这里没同步时会红。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/analytics_api.dart';
import '../../support/backend_repo.dart';

/// ⚠️ 读的是后端 **master** 上那一份,不是工作区那一份 —— 理由见 [backendSource]。
const String _kController =
    'chengyinhub-admin/src/main/java/com/chengyinhub/'
    'web/controller/api/ApiAnalyticsController.java';

AnalyticsEvent ev(String name, {Map<String, dynamic>? props, int? bizId}) =>
    AnalyticsEvent(eventName: name, properties: props, bizId: bizId);

void main() {
  group('★★ 白名单与后端逐字一致', () {
    test('事件名清单同步', () {
      final String? src = backendSource(_kController);
      if (src == null) {
        markTestSkipped('后端仓库不在预期路径,跳过比对');
        return;
      }
      final int at = src.indexOf('ALLOWED_EVENTS = new HashSet');
      expect(at, greaterThan(0));
      final String block = src.substring(at, src.indexOf('));', at));
      final Set<String> backend = RegExp(
        r'"([a-z_]+)"',
      ).allMatches(block).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(backend.length, greaterThan(30), reason: '解析失效了');
      expect(
        AnalyticsApi.allowedEvents,
        backend,
        reason:
            '客户端白名单和后端漂了 —— '
            '多出来的会被整批拒(拖累同批其他事件),少的那些会被本地挡掉再也发不出去',
      );
    });

    test('敏感键清单同步', () {
      final String? src = backendSource(_kController);
      if (src == null) {
        markTestSkipped('后端仓库不在预期路径,跳过比对');
        return;
      }
      final int at = src.indexOf('SENSITIVE_PROPERTY_KEYS = new HashSet');
      final String block = src.substring(at, src.indexOf('));', at));
      final Set<String> backend = RegExp(
        r'"([a-z]+)"',
      ).allMatches(block).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(backend.length, greaterThan(15));
      expect(AnalyticsApi.sensitiveKeys, backend);
    });

    test('漫游 AI 表面四个事件同步', () {
      final String? src = backendSource(_kController);
      if (src == null) {
        markTestSkipped('后端仓库不在预期路径,跳过比对');
        return;
      }
      final int at = src.indexOf('ROAM_AI_SURFACE_EVENTS = new HashSet');
      final String block = src.substring(at, src.indexOf('));', at));
      final Set<String> backend = RegExp(
        r'"([a-z_]+)"',
      ).allMatches(block).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(AnalyticsApi.roamAiSurfaceEvents, backend);
    });
  });

  group('闸①:事件名', () {
    test('白名单内放行', () {
      expect(AnalyticsApi.validate(ev('roam_start')), isNull);
    });

    test('拼错的被挡下,并说清是哪个', () {
      final String? why = AnalyticsApi.validate(ev('roam_started'));
      expect(why, contains('roam_started'), reason: '不说是哪条的话,整批被拒时查不出来');
    });

    test('空名被挡', () {
      expect(AnalyticsApi.validate(ev('')), '事件名称不能为空');
    });
  });

  group('闸②:敏感属性', () {
    test('★★ 键要先剥非字母数字再比 —— user_name 也算 name', () {
      expect(
        AnalyticsApi.validate(
          ev('search_submit', props: <String, dynamic>{'user_name': 'x'}),
        ),
        '事件属性不得包含敏感个人信息',
        reason: '只按原样比会漏掉带下划线的写法',
      );
      expect(
        AnalyticsApi.validate(
          ev('search_submit', props: <String, dynamic>{'user-name': 'x'}),
        ),
        isNotNull,
      );
    });

    test('★★ 嵌套容器一律拒 —— 不是"检查里面"', () {
      expect(
        AnalyticsApi.validate(
          ev(
            'search_submit',
            props: <String, dynamic>{
              'meta': <String, dynamic>{'ok': 1},
            },
          ),
        ),
        isNotNull,
        reason: '属性必须是扁平的标量',
      );
      expect(
        AnalyticsApi.validate(
          ev(
            'search_submit',
            props: <String, dynamic>{
              'ids': <int>[1, 2],
            },
          ),
        ),
        isNotNull,
      );
    });

    test('★★ 值本身像手机号/邮箱/卡号也拒,哪怕键名无辜', () {
      for (final String v in <String>[
        '13800001111',
        'a@b.com',
        '6222021234567890123',
      ]) {
        expect(
          AnalyticsApi.validate(
            ev('search_submit', props: <String, dynamic>{'v': v}),
          ),
          isNotNull,
          reason: '「$v」应被值级规则拦下',
        );
      }
    });

    test('正常扁平属性放行', () {
      expect(
        AnalyticsApi.validate(
          ev(
            'search_submit',
            props: <String, dynamic>{'result_count': 12, 'from': 'home'},
          ),
        ),
        isNull,
      );
    });

    test('属性过长被挡', () {
      final String big = jsonEncode(<String, dynamic>{'a': 'x' * 4100});
      expect(big.length, greaterThan(4000));
      expect(
        AnalyticsApi.validate(
          AnalyticsEvent(
            eventName: 'search_submit',
            properties: <String, dynamic>{'a': 'x' * 4100},
          ),
        ),
        '事件属性过长',
      );
    });
  });

  group('闸③:漫游 AI 表面事件只记"发生过"', () {
    test('★★ 带 bizId 或属性都被挡', () {
      expect(
        AnalyticsApi.validate(ev('roam_poi_meaning_shown', bizId: 7)),
        '漫游 AI 表面埋点不得关联业务对象或携带属性',
        reason: 'session/POI 可被反查成路线或地点 —— 这是隐私口径不是洁癖',
      );
      expect(
        AnalyticsApi.validate(
          ev('roam_route_story_shown', props: <String, dynamic>{'len': 3}),
        ),
        isNotNull,
      );
    });

    test('bizId=0 视同没有', () {
      expect(
        AnalyticsApi.validate(ev('roam_route_story_shown', bizId: 0)),
        isNull,
      );
    });

    test('裸事件放行', () {
      expect(AnalyticsApi.validate(ev('roam_footprint_hint_shown')), isNull);
    });

    test('★ 同名限制不误伤别的漫游事件', () {
      // roam_start 不在四个表面事件里,带属性是允许的。
      expect(
        AnalyticsApi.validate(
          ev('roam_start', props: <String, dynamic>{'mode': 'fog'}),
        ),
        isNull,
      );
    });
  });
}
