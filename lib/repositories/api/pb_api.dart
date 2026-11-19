/// Вспомогательные функции для PocketBase REST API: фильтры, сортировка,
/// перевод snake_case ↔ camelCase для моделей Flutter.
class PbApi {
  const PbApi._();

  static String escapeFilter(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  static String sort(String field, bool ascending, {String? pbField}) {
    final name = pbField ?? _sortFields[field] ?? field;
    return ascending ? name : '-$name';
  }

  static const _sortFields = {
    'fullName': 'full_name',
    'foundedYear': 'founded_year',
    'widthCm': 'width_cm',
    'depthCm': 'depth_cm',
    'heightCm': 'height_cm',
  };

  static String combineFilters(Iterable<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(' && ');

  static String activeOnly({required bool includeDeleted}) =>
      includeDeleted ? '' : 'deleted_at = ""';

  static String searchOr(String term, List<String> fields) {
    final q = escapeFilter(term.trim());
    if (q.isEmpty) return '';
    return fields.map((f) => '$f ~ "$q"').join(' || ');
  }

  static DateTime? readDeletedAt(dynamic value) {
    if (value == null || value == '') return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic> withDeletedAt(Map<String, dynamic> pb) {
    final out = Map<String, dynamic>.from(pb);
    out['deletedAt'] = readDeletedAt(pb['deleted_at'] ?? pb['deletedAt']);
    return out;
  }

  static Map<String, dynamic> productFromPb(Map<String, dynamic> pb) =>
      withDeletedAt({
        ...pb,
        'manufacturerId': pb['manufacturer'],
        'categoryIds': pb['categories'],
        'materialIds': pb['materials'],
        'widthCm': pb['width_cm'] ?? pb['widthCm'],
        'depthCm': pb['depth_cm'] ?? pb['depthCm'],
        'heightCm': pb['height_cm'] ?? pb['heightCm'],
      });

  static Map<String, dynamic> productToPb(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('deletedAt')
      ..remove('manufacturerId')
      ..remove('categoryIds')
      ..remove('materialIds')
      ..remove('widthCm')
      ..remove('depthCm')
      ..remove('heightCm');
    data['manufacturer'] = json['manufacturerId'];
    data['categories'] = json['categoryIds'];
    data['materials'] = json['materialIds'];
    data['width_cm'] = json['widthCm'];
    data['depth_cm'] = json['depthCm'];
    data['height_cm'] = json['heightCm'];
    return data;
  }

  static Map<String, dynamic> manufacturerFromPb(Map<String, dynamic> pb) =>
      withDeletedAt({
        ...pb,
        'foundedYear': pb['founded_year'] ?? pb['foundedYear'],
        'materialIds': pb['materials'],
      });

  static Map<String, dynamic> manufacturerToPb(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('deletedAt')
      ..remove('foundedYear')
      ..remove('materialIds');
    data['founded_year'] = json['foundedYear'];
    data['materials'] = json['materialIds'];
    return data;
  }

  static Map<String, dynamic> customerFromPb(
    Map<String, dynamic> pb, {
    Map<String, dynamic>? cardPb,
  }) {
    final out = withDeletedAt({
      ...pb,
      'fullName': pb['full_name'] ?? pb['fullName'],
    });
    if (cardPb != null) {
      out['card'] = {
        'number': cardPb['number'],
        'discountPercent':
            cardPb['discount_percent'] ?? cardPb['discountPercent'],
        'issuedAt': cardPb['issued_at'] ?? cardPb['issuedAt'],
      };
    }
    return out;
  }

  static Map<String, dynamic> customerToPb(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('deletedAt')
      ..remove('fullName')
      ..remove('card');
    data['full_name'] = json['fullName'];
    return data;
  }

  static Map<String, dynamic> discountCardToPb(
    String customerId,
    Map<String, dynamic> card,
  ) => {
    'customer': customerId,
    'number': card['number'],
    'discount_percent': card['discountPercent'],
    'issued_at': card['issuedAt'],
  };

  static Map<String, dynamic> categoryFromPb(Map<String, dynamic> pb) =>
      withDeletedAt(pb);

  static Map<String, dynamic> categoryToPb(Map<String, dynamic> json) =>
      Map<String, dynamic>.from(json)
        ..remove('id')
        ..remove('deletedAt');

  static Map<String, dynamic> materialFromPb(Map<String, dynamic> pb) =>
      withDeletedAt(pb);

  static Map<String, dynamic> materialToPb(Map<String, dynamic> json) =>
      Map<String, dynamic>.from(json)
        ..remove('id')
        ..remove('deletedAt');

  static Map<String, dynamic> listParams({
    required int page,
    required int perPage,
    required String sort,
    String? filter,
    String? expand,
  }) => {
    'page': page,
    'perPage': perPage,
    'sort': sort,
    if (filter != null && filter.isNotEmpty) 'filter': filter,
    if (expand != null && expand.isNotEmpty) 'expand': expand,
  };

  static Map<String, dynamic> userFromPb(Map<String, dynamic> pb) => {
    'id': pb['id'],
    'username': pb['username'],
    'fullName': pb['name'] ?? pb['fullName'] ?? '',
    'role': pb['role'],
  };
}
