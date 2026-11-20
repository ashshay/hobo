/// 微博接口的容错 JSON 读取：字段经常缺、类型经常变（数字 / 字符串 / 布尔混用），
/// 所有读取都必须带默认值，不能抛异常。
library;

String jStr(Object? value, [String def = '']) {
  if (value == null) return def;
  if (value is String) return value;
  return value.toString();
}

int? jIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  return int.tryParse(value.toString().trim());
}

int jInt(Object? value, [int def = 0]) => jIntOrNull(value) ?? def;

double? jDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is bool) return value ? 1 : 0;
  return double.tryParse(value.toString().trim());
}

bool jBool(Object? value, [bool def = false]) {
  if (value == null) return def;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return def;
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return def;
}

Map<String, dynamic>? jObj(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return {for (final entry in value.entries) entry.key.toString(): entry.value};
  }
  return null;
}

List<dynamic>? jArr(Object? value) {
  if (value is List) return value;
  return null;
}

/// m.weibo.cn 把「粉丝」这类可能上亿的计数压缩成展示字符串下发，
/// 例如 `"followers_count": "72.3万"` / `"1.2亿"` / `"26"`，直接取整会得到 0。
int? parseCount(String? raw) {
  if (raw == null) return null;
  var text = raw.trim().replaceAll(',', '').replaceAll('+', '');
  if (text.isEmpty) return null;
  final unit = text.endsWith('亿')
      ? 100000000.0
      : text.endsWith('万')
      ? 10000.0
      : text.endsWith('千')
      ? 1000.0
      : text.toLowerCase().endsWith('w')
      ? 10000.0
      : text.toLowerCase().endsWith('k')
      ? 1000.0
      : 1.0;
  final digits = text.replaceAll(RegExp('[亿万什wWkK]'), '').trim();
  final value = double.tryParse(digits);
  if (value == null) return null;
  return (value * unit).toInt();
}

int jCount(Object? value, [int def = 0]) {
  if (value == null) return def;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  return parseCount(value.toString()) ?? def;
}

extension JsonAccess on Map<String, dynamic> {
  String str(String key, [String def = '']) => jStr(this[key], def);

  int intOf(String key, [int def = 0]) => jInt(this[key], def);

  int count(String key, [int def = 0]) => jCount(this[key], def);

  bool boolean(String key, [bool def = false]) => jBool(this[key], def);

  double? dbl(String key) => jDoubleOrNull(this[key]);

  Map<String, dynamic>? obj(String key) => jObj(this[key]);

  List<dynamic>? arr(String key) => jArr(this[key]);

  Object? opt(String key) => this[key];

  bool has(String key) => containsKey(key);
}
