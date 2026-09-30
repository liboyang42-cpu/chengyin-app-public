/// 节点核验方式(validationMethod)码表的唯一真源。
///
/// ★★ 与小程序 `chengyinhub-xcx/utils/validation-method-labels.js` 同口径。
///   App 这边曾经裂成四套:template.dart 把码 1 错标「扫码核销」、码 4–7
///   全塌成「其他」;city_node_detail 说「文字暗号」;city_node_poi 说
///   「答题打卡」;商家表单又说「扫张贴码 / 走到就算」。同一条后端码,
///   四个页面四个叫法。新增一档只改这里。
const Map<int, String> kValidationMethodLabels = <int, String>{
  0: '无需验证',
  1: '文字作答',
  2: '拍照打卡',
  3: '选项问答',
  4: '到店扫码',
  5: 'GPS 到达',
  6: '偏好题组',
  7: '传感器挑战',
};

/// 核验方式文案。
///
/// - 码 0–7 → 真源里的名字;
/// - `null` → `null` —— 「还没配」不是「无需验证」,空语义交给调用方决定;
/// - 认不出的码 → 「其他」,不编一个名字 —— 后端加了新方式时,
///   编出来的名字会一直错下去而没人发现。
String? validationMethodLabel(int? code) {
  if (code == null) return null;
  return kValidationMethodLabels[code] ?? '其他';
}
