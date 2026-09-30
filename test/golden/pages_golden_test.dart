// 整页视觉快照。
//
// 组件快照只证明「零件」对,证明不了「整页」布局对 —— 间距节奏、层级关系、
// 长文截断这些只有整页渲染才看得出来。页面依赖 Riverpod,这里用 override
// 注入固定假数据,不打网络。
//
// 更新基准图:flutter test --update-goldens test/golden

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'golden_theme.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';

MyRegistration _reg({
  required int id,
  required String title,
  int regStatus = 2,
  int verify = 0,
  String? no,
  String? date,
  double? amount,
  String? imgUrl,
  String? startDate,
  String? endDate,
  String? addressName,
}) {
  return MyRegistration.fromJson(<String, dynamic>{
    'id': id,
    'ownerType': 2,
    'ownerId': 100 + id,
    'registrationNo': no ?? 'R2026081800$id',
    'registrationStatus': regStatus,
    'verificationStatus': verify,
    'participateDate': date ?? '2026-08-24 14:00',
    if (amount != null) 'payableAmount': amount,
    'cmsActivity': <String, dynamic>{
      'name': title,
      'productType': 2,
      if (imgUrl != null) 'imgUrl': imgUrl,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (addressName != null) 'addressName': addressName,
    },
  });
}

// 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,
// 这里靠推断即可,少一个 import 少一处版本耦合。
//
// ★ 票夹对**游客**会换成登录门(#231 P1),而基准图拍的是有票、有订单的那种
//   画面 —— 那里必然有人在登录态,统一摆好。
class _GoldenAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GoldenAuth.new),
      ...overrides,
    ].cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

void main() {
  testWidgets('票夹:有票(四态各一)', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 780));
    await tester.pumpWidget(
      _app(<dynamic>[
        myTicketsProvider.overrideWith(
          (ref) async => WalletSnapshot(
            tickets: <MyRegistration>[
              _reg(id: 1, title: '静安探店日 · 第一期'),
              _reg(id: 2, title: '徐汇咖啡巡礼 · 周末场', verify: 1),
              _reg(id: 3, title: '一个很长很长的活动名称用来检验标题两行截断是否正确显示省略号'),
            ],
          ),
        ),
        // 票夹会静默拉一次 /api/team/my(队伍入口行)。golden 不发真请求,
        // 也没有队伍 —— 钉成空索引,基准图像素不变。
        walletMyTeamsProvider.overrideWith(
          (ref) async => const <String, WalletTeam>{},
        ),
      ], const TicketsPage()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_tickets.png'),
    );
  });

  testWidgets('我的订单:含待支付', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 700));
    await tester.pumpWidget(
      _app(<dynamic>[
        myOrdersProvider.overrideWith(
          (ref) async => <MyRegistration>[
            // 三张卡各带一种金额形态:待付的、已付的、零元的。
            // ★ startDate/endDate 一律用 2099:订单状态(未开始/进行中/已完成)是拿
            //   这两个日期跟 DateTime.now() 比出来的,写成近期日期的基准图会在那天
            //   过去之后每天红一次 —— 2026-08-26 实证:id 5 从「未开始 + 申请退款/
            //   查看票夹」变成「已完成 + 查看详情」,3.09% 像素差,而代码一行没改。
            //   页面只渲染 MM.dd HH:mm(不带年份),所以换年份像素不变、基线不用重拍。
            //   同类惯用法见 pages_account_golden_test.dart 的 2099-12-31。
            _reg(
              id: 4,
              title: '静安探店日 · 第二期',
              regStatus: 1,
              amount: 149,
              imgUrl: 'https://img.example/order-4.jpg',
              startDate: '2099-08-24 14:00:00',
              endDate: '2099-08-24 18:00:00',
              addressName: '静安寺 1 号口',
            ),
            _reg(
              id: 5,
              title: '普陀夜市寻味',
              amount: 49.9,
              imgUrl: 'https://img.example/order-5.jpg',
              startDate: '2099-08-25 19:00:00',
              endDate: '2099-08-25 22:00:00',
              addressName: '环球港南广场',
            ),
            _reg(
              id: 6,
              title: '已取消的一单',
              regStatus: 3,
              amount: 0,
              imgUrl: 'https://img.example/order-6.jpg',
              startDate: '2099-08-20 19:00:00',
              endDate: '2099-08-20 22:00:00',
              addressName: '上海图书馆',
            ),
          ],
        ),
      ], const OrdersPage()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_orders.png'),
    );
  });
}
