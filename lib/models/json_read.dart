/// Безопасное чтение полей из JSON: отсутствующее поле, null или значение
/// другого типа не роняют разбор, а заменяются значением по умолчанию.
class JsonRead {
  const JsonRead._();

  static int integer(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static String text(Object? value, [String fallback = '']) =>
      value is String ? value : (value == null ? fallback : value.toString());

  /// Идентификатор записи: строка; число из старых данных переводится в строку.
  static String id(Object? value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    if (value is num) return value.toString();
    return value.toString();
  }

  /// Список идентификаторов. Понимает обе формы: `['a','b']` — так связи
  /// хранятся локально и уходят на сервер, и `[{"id": "x", "name": …}]` —
  /// так сервер присылает развёрнутые объекты.
  static List<String> ids(Object? value) {
    if (value is! List) return const [];
    final result = <String>[];
    for (final e in value) {
      if (e is Map) {
        final parsed = id(e['id']);
        if (parsed.isNotEmpty) result.add(parsed);
        continue;
      }
      if (e is num) {
        if (e > 0) result.add(e.toString());
        continue;
      }
      if (e is String) {
        final parsed = id(e);
        if (parsed.isEmpty) continue;
        final asInt = int.tryParse(parsed);
        if (asInt != null && asInt > 0) {
          result.add(parsed);
        } else if (RegExp(r'^(l\d+|[a-z0-9]{15})$').hasMatch(parsed)) {
          result.add(parsed);
        }
      }
    }
    return result;
  }

  /// Идентификатор связанной записи: из поля `manufacturerId` или, если
  /// его нет, из вложенного объекта `manufacturer: {"id": …}`.
  static String refId(
    Map<String, dynamic> json,
    String idKey,
    String objectKey,
  ) {
    if (json[idKey] != null) return id(json[idKey]);
    final nested = json[objectKey];
    return nested is Map ? id(nested['id']) : '';
  }

  static DateTime? date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static Map<String, dynamic>? map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : null;
}
