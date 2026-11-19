import 'package:dio/dio.dart';

import '../models/app_user.dart';
import '../repositories/api/pb_api.dart';
import 'api_exception.dart';
import 'api_session.dart';

/// Клиент PocketBase: вход, пользователи, статистика, личные заказы.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Options get _skip => Options(extra: {ApiSession.skipAuth: true});

  static const _users = '/api/collections/users/records';

  Future<AuthTokens> login(String identity, String password) => guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/collections/users/auth-with-password',
      data: {'identity': identity, 'password': password},
      options: _skip,
    );
    return AuthTokens.fromJson(response.data!);
  });

  Future<AuthTokens> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
  }) => guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      _users,
      data: {
        'email': email,
        'username': username,
        'password': password,
        'passwordConfirm': password,
        'name': fullName,
        'role': 'viewer',
      },
      options: _skip,
    );
    response.data;
    return login(email, password);
  });

  /// Обновление сессии; заголовок Authorization подставляет перехватчик.
  Future<AuthTokens> refresh() => guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/collections/users/auth-refresh',
    );
    return AuthTokens.fromJson(response.data!);
  });

  Future<AppUser> me() => guard(() async {
    final tokens = await refresh();
    return tokens.user;
  });

  Future<void> logout(String? refreshToken) async {}

  Future<List<AppUser>> listUsers() => guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      _users,
      queryParameters: {'page': 1, 'perPage': 200, 'sort': 'username'},
    );
    final items = response.data!['items'] as List<dynamic>? ?? const [];
    return [
      for (final item in items)
        AppUser.fromJson(PbApi.userFromPb(item as Map<String, dynamic>)),
    ];
  });

  Future<AppUser> updateUserRole(String id, RoleUpdate update) =>
      guard(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '$_users/$id',
          data: {
            'role': update.role,
            if (update.fullName != null) 'name': update.fullName,
          },
        );
        return AppUser.fromJson(PbApi.userFromPb(response.data!));
      });

  Future<Map<String, int>> stats() => guard(() async {
    const specs = {
      'products': (name: 'products', filter: 'deleted_at = ""'),
      'manufacturers': (name: 'manufacturers', filter: 'deleted_at = ""'),
      'categories': (name: 'categories', filter: 'deleted_at = ""'),
      'materials': (name: 'materials', filter: 'deleted_at = ""'),
      'customers': (name: 'customers', filter: 'deleted_at = ""'),
      'orders': (name: 'orders', filter: 'cancelled_at = ""'),
      'users': (name: 'users', filter: ''),
    };
    final result = <String, int>{};
    for (final entry in specs.entries) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/collections/${entry.value.name}/records',
        queryParameters: {
          'page': 1,
          'perPage': 1,
          if (entry.value.filter.isNotEmpty) 'filter': entry.value.filter,
        },
      );
      result[entry.key] = (response.data!['totalItems'] as int?) ?? 0;
    }
    return result;
  });

  Future<List<Map<String, dynamic>>> myOrders(String userId) => guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/collections/orders/records',
      queryParameters: {
        'page': 1,
        'perPage': 100,
        'sort': '-created',
        'filter': 'user = "${PbApi.escapeFilter(userId)}"',
        'expand': 'product,customer',
      },
    );
    final items = response.data!['items'] as List<dynamic>? ?? const [];
    return [
      for (final item in items)
        _orderForUi((item as Map).cast<String, dynamic>()),
    ];
  });

  static Map<String, dynamic> _orderForUi(Map<String, dynamic> pb) {
    final expand = pb['expand'] as Map<String, dynamic>? ?? const {};
    final product = expand['product'] ?? pb['product'];
    return {
      'id': pb['id'],
      'quantity': pb['quantity'],
      'total': pb['total'],
      'cancelledAt': pb['cancelled_at'] ?? pb['cancelledAt'],
      'product': product is Map
          ? {'name': product['name'] ?? product['id']}
          : product,
    };
  }
}

class RoleUpdate {
  const RoleUpdate({required this.role, this.fullName});

  final String role;
  final String? fullName;

  Map<String, dynamic> toJson() => {
    'role': role,
    if (fullName != null) 'fullName': fullName,
  };
}
