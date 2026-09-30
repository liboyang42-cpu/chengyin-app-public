/// 容错 JSON 字段解析工具。
///
/// 后端的数字/布尔字段可能以 int/long/double/String 多种形态返回(见
/// contract/README.md:"数字可能 int/long/String")。严格 num 转型
/// ((json['x'] as num?)?.toInt()) 遇到 String("100") 会抛 type cast。
/// 这里提供公开的容错函数,num/String/null 都不崩。
///
/// 逻辑对齐 checkin_models.dart 的私有 helper(_asInt/_asDouble/_asBool/_asStr)。
library;

/// 解析为 int:num 直接转,String 走 int.tryParse(失败/null 回退默认值)。
int asInt(Object? v, {int defaultValue = 0}) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? defaultValue;

/// 解析为 double?:null 保持 null;num 直接转;String 走 double.tryParse。
double? asDouble(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// 解析为 bool:认 true / 1 / "1" / "true" 为真,其余为假。
bool asBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

/// 解析为 String:null 回退空串,其余 toString。
String asStr(Object? v) => v?.toString() ?? '';
