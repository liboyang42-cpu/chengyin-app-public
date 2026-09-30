// 本轮新建的九个页面的整页快照。
//
// fixture 一律造**语义边界**而不是漂亮数据 —— 拍一屏理想数据只能证明
// "顺利时长得不难看",证明不了别的。本轮靠看图抓到过的那类问题:
//   · 该说清的没说清(状态未知/为什么看不到号码/删了会连带删什么)
//   · 该藏的没藏(已中标却给取消按钮、配额满还露入口)
//   · 空态说了假话(把"没拿到"说成"没有")
//
// 更新基准图:flutter test --update-goldens test/golden/pages_new_batch_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/coop/complaint_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_registrations_page.dart';
import 'package:chengyin_app/feature/merchant/node_template_edit_page.dart';
import 'package:chengyin_app/feature/merchant/project_home_page.dart';
import 'package:chengyin_app/feature/merchant/project_players_page.dart';
import 'golden_theme.dart';

import '../support/fixed_auth.dart';

/// ★★ 商家页在真机上是**浅色**的(app_router.dart 的 _merchantLight)——
///   用深色 goldenTheme 拍出来的黑底是**没人会看到的画面**,
///   基准图会变成假证据。golden_theme.dart 的注释早写了这条,
///   而我这一轮的五个商家页全拍成了深色。
///
///   判据:该页的路由有没有包 _merchantLight。
Widget _app(List<dynamic> overrides, Widget home, {bool light = false}) =>
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: light ? merchantGoldenTheme() : goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );

Future<void> _shot(
  WidgetTester t,
  Widget app,
  String path, {
  Size size = const Size(390, 1000),
}) async {
  setGoldenViewport(t, size);
  await t.pumpWidget(app);
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

void main() {
  testWidgets('★ 我的报名:已中标(无取消钮)/ 已驳回(有原因+可改)/ 状态未知', (
    WidgetTester tester,
  ) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          merchantRegistrationsProvider(
            RegistrationListFilter.all,
          ).overrideWith(
            (ref) async => <TopicRegistration>[
              // 已中标:不给取消按钮(点了必撞 service 的闸)
              TopicRegistration.fromJson(<String, dynamic>{
                'id': 1,
                'topicId': 1,
                'topicName': '静安夜行',
                'addressName': '静安咖啡',
                'status': 1,
                'auditStatus': 1,
              }),
              // 已驳回:要显示原因,且仍可改
              TopicRegistration.fromJson(<String, dynamic>{
                'id': 2,
                'topicId': 2,
                'topicName': '徐汇书店巡礼',
                'addressName': '徐汇书店',
                'status': 2,
                'reason': '现场照片看不清门头',
              }),
              // ★ 驳回但后端没填原因 —— 说实话,不编一句
              TopicRegistration.fromJson(<String, dynamic>{
                'id': 3,
                'topicId': 3,
                'topicName': '虹口面包房',
                'status': 2,
              }),
              // ★ 状态没拿到 —— 显示"状态未知",不默认成"审核中"
              TopicRegistration.fromJson(<String, dynamic>{
                'id': 4,
                'topicId': 4,
                'topicName': '拿不到状态的那条',
              }),
            ],
          ),
        ],
        const MerchantRegistrationsPage(),
        light: true,
      ),
      'goldens/page_merchant_registrations.png',
      size: const Size(390, 1200),
    );
  });

  testWidgets('★★ 项目主页:既主办又承接(两块都要在)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          projectHomeProvider(null).overrideWith(
            (ref) async => <String, dynamic>{
              'role': 'host',
              'topic': <String, dynamic>{'name': '静安夜行', 'city': '上海'},
              'host': <String, dynamic>{
                'recruit': <String, dynamic>{
                  'nodeTotal': 6,
                  'nodeFilled': 4,
                  'pendingCount': 2,
                },
                // 后端 `host.players` 是 {paidCount} 这个对象,不是名单数组。
                'players': <String, dynamic>{'paidCount': 3},
              },
              // ★ 同一个人也报名承接了 —— 这块不能被 role=host 藏掉
              'join': <String, dynamic>{
                'registration': <String, dynamic>{'addressName': '我的咖啡店'},
              },
            },
          ),
        ],
        const ProjectHomePage(),
        light: true,
      ),
      'goldens/page_project_home.png',
    );
  });

  testWidgets('★★ 玩家名单:三态 + 看不到号码时说清为什么', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          projectPlayersProvider(null).overrideWith(
            (ref) async => <String, dynamic>{
              'summary': <String, dynamic>{
                'paidCount': 3,
                'arrivedCount': 1,
                'pendingCount': 2,
                'refundedCount': 1,
              },
              'rows': <dynamic>[
                <String, dynamic>{
                  'name': '小李',
                  'ticketName': '双人票',
                  'state': 'arrived',
                },
                <String, dynamic>{'name': '小王', 'state': 'pending'},
                // ★ 已退款必须单独一态 —— 混进"未到"商家会一直等
                <String, dynamic>{'name': '小张', 'state': 'refunded'},
              ],
              'contactVisible': false,
              // ★ 后端给的原话,原样显示 —— 自己写"暂无权限"用户不知道找谁
              'contactHint': '这条路线由俱乐部带团,玩家联系方式请找俱乐部负责人',
            },
          ),
        ],
        const ProjectPlayersPage(),
        light: true,
      ),
      'goldens/page_project_players.png',
    );
  });

  testWidgets('★ 参与人信息:真源行式(姓名 + 手机号 + 行内说明)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        signedInAuthOverride(),
        addressListProvider.overrideWith(
          (ref) async => <MemberAddress>[
            MemberAddress.fromJson(<String, dynamic>{
              'id': 1,
              'fullName': '李某',
              'mobilePhone': '13800001111',
              'province': '上海市 静安区',
              'detailAddress': '南京西路 1266 号',
              'isDefault': 1,
            }),
            // 同一张表里后补的行:真源列表照样只显示姓名+手机号+行内说明,
            // 不再自造「没有地址」提示(B1 P1-3 收口)。
            MemberAddress.fromJson(<String, dynamic>{
              'id': 2,
              'fullName': '王某',
              'mobilePhone': '13900002222',
            }),
          ],
        ),
      ], const AddressListPage()),
      'goldens/page_address_list.png',
    );
  });

  testWidgets('★ 投诉与建议:活动 + 类型 + 内容 + 联系方式(选填)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        complainableTopicsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{'topicId': 1, 'topicName': '静安夜行'},
            <String, dynamic>{'topicId': 2, 'topicName': '徐汇书店巡礼'},
          ],
        ),
      ], const ComplaintPage()),
      'goldens/page_complaint.png',
    );
  });

  testWidgets('★ 投诉空态:说清判据(已支付才能投诉)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        complainableTopicsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[],
        ),
      ], const ComplaintPage()),
      'goldens/page_complaint_empty.png',
    );
  });

  testWidgets('★★ 节点玩法:选了"选项问答"才露那几栏', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(const <dynamic>[], const NodeTemplateEditPage(), light: true),
      'goldens/page_node_template.png',
      size: const Size(390, 1400),
    );
  });
}
