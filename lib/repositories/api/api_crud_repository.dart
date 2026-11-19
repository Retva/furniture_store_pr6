import 'package:dio/dio.dart';

import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../models/entity.dart';
import '../../models/list_query.dart';
import '../../models/page_result.dart';
import '../crud_repository.dart';

/// Общая часть всех репозиториев, работающих через PocketBase REST API.
class ApiCrudRepository<T extends Entity, Q extends ListQuery>
    implements CrudRepository<T, Q> {
  ApiCrudRepository(
    this.dio, {
    required this.resource,
    required this.fromJson,
    required this.toInput,
    required this.listParams,
  });

  final Dio dio;

  /// Имя коллекции PocketBase: `products` → `/api/collections/products/records`.
  final String resource;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toInput;
  final Map<String, dynamic> Function(Q query) listParams;

  final LatestRequest _listRequest = LatestRequest();
  final List<void Function()> _changeListeners = [];

  void addChangeListener(void Function() listener) =>
      _changeListeners.add(listener);

  void notifyChanged() {
    for (final listener in _changeListeners) {
      listener();
    }
  }

  String get _path => '/api/collections/$resource/records';

  PageResult<T> parsePage(Map<String, dynamic> data) => PageResult<T>(
    items: [
      for (final row in data['items'] as List)
        fromJson((row as Map).cast<String, dynamic>()),
    ],
    page: data['page'] as int,
    size: (data['perPage'] as int?) ?? (data['size'] as int?) ?? 10,
    total: (data['totalItems'] as int?) ?? (data['total'] as int?) ?? 0,
  );

  @override
  Future<PageResult<T>> find(Q query) => guard(() async {
    final response = await dio.get<Map<String, dynamic>>(
      _path,
      queryParameters: listParams(query),
      cancelToken: _listRequest.next(),
    );
    return parsePage(response.data!);
  });

  @override
  Future<List<T>> findAll({bool includeDeleted = true}) => guard(() async {
    final all = <T>[];
    var page = 1;
    while (true) {
      final response = await dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: {
          'page': page,
          'perPage': 100,
          'sort': 'name',
          if (!includeDeleted) 'filter': 'deleted_at = ""',
        },
      );
      final result = parsePage(response.data!);
      all.addAll(result.items);
      if (!result.hasNext) return List.unmodifiable(all);
      page++;
    }
  });

  @override
  Future<T?> findById(String id) async {
    try {
      return await guard(() async {
        final response = await dio.get<Map<String, dynamic>>('$_path/$id');
        return fromJson(response.data!);
      });
    } on NotFoundException {
      return null;
    }
  }

  @override
  Future<T> create(T item) => guard(() async {
    final response = await dio.post<Map<String, dynamic>>(
      _path,
      data: toInput(item),
    );
    notifyChanged();
    return fromJson(response.data!);
  });

  @override
  Future<T> update(T item) => guard(() async {
    final response = await dio.patch<Map<String, dynamic>>(
      '$_path/${item.id}',
      data: toInput(item),
    );
    notifyChanged();
    return fromJson(response.data!);
  });

  @override
  Future<void> softDelete(String id) => guard(() async {
    await dio.patch<void>(
      '$_path/$id',
      data: {'deleted_at': DateTime.now().toUtc().toIso8601String()},
    );
    notifyChanged();
  });

  @override
  Future<void> hardDelete(String id) => guard(() async {
    await dio.delete<void>('$_path/$id');
    notifyChanged();
  });

  @override
  Future<void> restore(String id) => guard(() async {
    await dio.patch<Map<String, dynamic>>(
      '$_path/$id',
      data: {'deleted_at': ''},
    );
    notifyChanged();
  });

  @override
  Future<int> deleteMany(List<String> ids) => guard(() async {
    for (final id in ids) {
      await dio.patch<void>(
        '$_path/$id',
        data: {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      );
    }
    notifyChanged();
    return ids.length;
  });

  Future<int> countWithFilter(String filter) => guard(() async {
    final response = await dio.get<Map<String, dynamic>>(
      _path,
      queryParameters: {'page': 1, 'perPage': 1, 'filter': filter},
    );
    return (response.data!['totalItems'] as int?) ?? 0;
  });
}
