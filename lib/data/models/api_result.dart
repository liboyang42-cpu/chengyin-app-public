/// 后端统一返回包装(对齐 RuoYi `AjaxResult`: code/msg/data)。
class ApiResult<T> {
  ApiResult({required this.code, required this.msg, this.data});

  final int code;
  final String msg;
  final T? data;

  /// RuoYi 约定 200 为成功。
  bool get ok => code == 200;

  factory ApiResult.fromJson(
    Map<String, dynamic> json,
    T Function(Object? data)? parse,
  ) {
    final Object? raw = json['data'];
    return ApiResult<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      msg: (json['msg'] ?? '').toString(),
      data: parse != null ? parse(raw) : raw as T?,
    );
  }
}
