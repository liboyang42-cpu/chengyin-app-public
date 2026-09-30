import 'package:chengyin_app/data/models/withdrawal.dart';

/// 余额三段(`/api/wallet/stages`)的固定替身,给渲染这一块的用例共用。
///
/// ★ 每个渲染 `WithdrawalPage` 的用例都要注入它:不注入就会去打**真接口**,
///   测试环境里那个请求不回来 —— 页面会停在加载态,`pumpAndSettle` 直接超时。
const MemberFundsStages kFundsStagesFixture = MemberFundsStages(
  pendingSettlement: 88.5,
  disputed: 0,
  withdrawable: 328.6,
  complaintPeriod: <ComplaintPeriodStage>[
    ComplaintPeriodStage(availableDate: '2026-09-25', amount: 120),
  ],
  amountsKnown: true,
);
