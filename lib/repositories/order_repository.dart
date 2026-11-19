import 'package:dio/dio.dart';

import '../api/api_exception.dart';
import '../models/order.dart';
import 'api/pb_api.dart';

/// Оформление заказов. Есть только у сервера: остатки и скидки считает он.
abstract interface class OrderRepository {
  /// Бросает [ConflictException] (409), если товара на складе меньше,
  /// чем заказано, и [ApiValidationException] (422) при неверных данных.
  Future<Order> place({
    required String customerId,
    required String productId,
    required int quantity,
  });

  Future<List<Order>> forProduct(String productId);

  Future<Order> cancel(String orderId);
}

class ApiOrderRepository implements OrderRepository {
  ApiOrderRepository(this.dio);

  final Dio dio;

  static const _path = '/api/collections/orders/records';

  static Map<String, dynamic> _orderFromPb(Map<String, dynamic> pb) {
    final expand = pb['expand'] as Map<String, dynamic>? ?? const {};
    final customer = expand['customer'] ?? pb['customer'];
    final product = expand['product'] ?? pb['product'];
    return {
      'id': pb['id'],
      'customerId': customer,
      'customer': customer is Map ? customer : null,
      'productId': product,
      'product': product is Map ? product : null,
      'quantity': pb['quantity'],
      'total': pb['total'],
      'createdAt': pb['created'] ?? pb['createdAt'],
      'cancelledAt': pb['cancelled_at'] ?? pb['cancelledAt'],
    };
  }

  @override
  Future<Order> place({
    required String customerId,
    required String productId,
    required int quantity,
  }) => guard(() async {
    final response = await dio.post<Map<String, dynamic>>(
      _path,
      data: {
        'customer': customerId,
        'product': productId,
        'quantity': quantity,
      },
    );
    return Order.fromJson(_orderFromPb(response.data!));
  });

  @override
  Future<List<Order>> forProduct(String productId) => guard(() async {
    final response = await dio.get<Map<String, dynamic>>(
      _path,
      queryParameters: {
        'page': 1,
        'perPage': 100,
        'sort': '-created',
        'filter': 'product = "${PbApi.escapeFilter(productId)}"',
        'expand': 'customer,product',
      },
    );
    return [
      for (final row in response.data!['items'] as List)
        Order.fromJson(_orderFromPb((row as Map).cast<String, dynamic>())),
    ];
  });

  @override
  Future<Order> cancel(String orderId) => guard(() async {
    final response = await dio.patch<Map<String, dynamic>>(
      '$_path/$orderId',
      data: {'cancelled_at': DateTime.now().toUtc().toIso8601String()},
    );
    return Order.fromJson(_orderFromPb(response.data!));
  });
}
