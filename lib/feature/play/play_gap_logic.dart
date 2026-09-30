import '../../data/models/checkin_models.dart';

/// 节点点击后的唯一互动分派。
///
/// 后端合同定义 `validationMethod=0..7`：0/null 到达、1 文字、
/// 2 拍照、3 选项、4 扫码、5 GPS、6 偏好题组、7 App 传感器。
/// 未知值必须停在 [unsupported]，
/// 不能回落到定位或其它完成接口，否则会绕过节点原本的校验。
enum PlayNodeInteraction {
  freeArrivalScan,
  freeProofPhoto,
  freeMerchantCode,
  answer,
  photo,
  scan,
  arrive,
  preference,
  appSensorChallenge,
  unsupported,
}

PlayNodeInteraction playNodeInteractionFor({
  required int mode,
  required PlayNode node,
}) {
  if (mode == 2) {
    if (!node.arrived) return PlayNodeInteraction.freeArrivalScan;
    if (!node.selfReported) return PlayNodeInteraction.freeProofPhoto;
    return PlayNodeInteraction.freeMerchantCode;
  }

  return switch (node.validationMethod) {
    0 => PlayNodeInteraction.arrive,
    1 || 3 => PlayNodeInteraction.answer,
    2 => PlayNodeInteraction.photo,
    4 => PlayNodeInteraction.scan,
    5 => PlayNodeInteraction.arrive,
    6 => PlayNodeInteraction.preference,
    7 => PlayNodeInteraction.appSensorChallenge,
    null when node.needAnswer => PlayNodeInteraction.answer,
    null when node.needScan => PlayNodeInteraction.scan,
    null when node.needGps => PlayNodeInteraction.arrive,
    null => PlayNodeInteraction.arrive,
    _ => PlayNodeInteraction.unsupported,
  };
}

bool isUnsupportedPlayValidationMethod(int? validationMethod) =>
    validationMethod != null &&
    !const <int>{0, 1, 2, 3, 4, 5, 6, 7}.contains(validationMethod);

class UnsupportedPlayValidationMethod implements Exception {
  const UnsupportedPlayValidationMethod({
    required this.nodeId,
    required this.validationMethod,
  });

  final int nodeId;
  final int validationMethod;

  @override
  String toString() =>
      'UnsupportedPlayValidationMethod(nodeId: $nodeId, '
      'validationMethod: $validationMethod)';
}

/// 探店日「到店三步」的一步。
class OnsiteStep {
  const OnsiteStep({required this.title, required this.done});

  final String title;
  final bool done;
}

/// 到店三步的**显示态**。
///
/// ★ 与 [playNodeInteractionFor] **同源**:三步分别对应 arrived / selfReported / done,
///   而那个函数正是按同样三个字段决定下一步做什么。别在 UI 里另写一套 if/else ——
///   两份判据一定会漂移,而漂移的表现是「界面说第 2 步没做,点下去却走了第 3 步」。
List<OnsiteStep> onsiteSteps(PlayNode node) => <OnsiteStep>[
  OnsiteStep(title: '扫描门店码 · 记录到店时间', done: node.arrived),
  OnsiteStep(title: '拍摄现场凭证 · 到店后显示拍摄要求', done: node.selfReported),
  OnsiteStep(title: '商家核销 · 核销那一刻才算服务开始', done: node.done),
];
