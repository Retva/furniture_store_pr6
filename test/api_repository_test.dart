import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_store/api/api_client.dart';
import 'package:furniture_store/api/api_exception.dart';
import 'package:furniture_store/api/api_session.dart';
import 'package:furniture_store/api/auth_api.dart';
import 'package:furniture_store/api/debug_options.dart';
import 'package:furniture_store/models/basic_query.dart';
import 'package:furniture_store/models/product.dart';
import 'package:furniture_store/models/product_query.dart';
import 'package:furniture_store/repositories/api/api_repositories.dart';
import 'package:furniture_store/repositories/order_repository.dart';
import 'package:furniture_store/repositories/repository_exception.dart';
import 'package:furniture_store/state/auth_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (cancelFuture != null) {
      return Future.any([
        handler(options),
        cancelFuture.then<ResponseBody>(
          (_) => throw DioException.requestCancelled(
            requestOptions: options,
            reason: 'cancelled',
          ),
        ),
      ]);
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object? body) => ResponseBody.fromString(
  body == null ? '' : jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

Never offline(RequestOptions options) => throw DioException.connectionError(
  requestOptions: options,
  reason: 'Connection refused',
);

Future<Object?> errorOf(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (e) {
    return e;
  }
  return null;
}

Map<String, dynamic> productJson(String id, {String sku = 'DV-1001'}) => {
  'id': id,
  'name': 'Диван «Осло»',
  'sku': sku,
  'manufacturer': '2',
  'categories': ['1'],
  'materials': ['4', '9'],
  'price': 54990,
  'stock': 3,
  'width_cm': 210,
  'depth_cm': 95,
  'height_cm': 85,
  'color': 'серый',
  'description': '',
  'deleted_at': '',
};

Map<String, dynamic> page(List<Object> items, {int total = 1, int size = 10}) =>
    {
      'items': items,
      'page': 1,
      'perPage': size,
      'totalItems': total,
      'totalPages': 1,
    };

const sofa = Product(
  id: '',
  name: 'Диван «Осло»',
  sku: 'DV-1001',
  manufacturerId: '2',
  categoryIds: ['1'],
  materialIds: ['4', '9'],
  price: 54990,
  stock: 3,
  widthCm: 210,
  depthCm: 95,
  heightCm: 85,
  color: 'серый',
);

void main() {
  late FakeAdapter adapter;
  late AuthNotifier auth;
  late ApiSession session;
  late DebugOptions debug;
  late Dio dio;
  late ApiProductRepository products;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    adapter = FakeAdapter((o) async => json(200, page([])));
    debug = DebugOptions();
    final bootstrap = buildDio(
      baseUrl: 'http://test',
      adapter: adapter,
      log: (_) {},
      retry: const RetryPolicy.none(),
    );
    auth = AuthNotifier(prefs, AuthApi(bootstrap));
    session = ApiSession(auth);
    dio = buildDio(
      baseUrl: 'http://test',
      session: session,
      debug: debug,
      adapter: adapter,
      log: (_) {},
      retry: const RetryPolicy(maxRetries: 3, baseDelay: Duration.zero),
    );
    auth.api = AuthApi(dio);
    products = ApiProductRepository(dio);
  });

  group('Чтение', () {
    test('поиск, фильтр, сортировка и страница уходят на сервер', () async {
      adapter.handler = (o) async =>
          json(200, page([productJson('7')], total: 31));

      final result = await products.find(
        const ProductQuery(
          search: 'диван',
          categoryId: '1',
          sortField: 'price',
          sortAscending: false,
          page: 2,
          size: 25,
        ),
      );

      final sent = adapter.requests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/api/collections/products/records');
      expect(sent.uri.queryParameters['page'], '2');
      expect(sent.uri.queryParameters['perPage'], '25');
      expect(sent.uri.queryParameters['sort'], '-price');
      final filter = sent.uri.queryParameters['filter']!;
      expect(filter, contains('deleted_at = ""'));
      expect(filter, contains('диван'));
      expect(filter, contains('categories ?~ "1"'));
      expect(result.total, 31);
      expect(result.items.single.id, '7');
    });

    test('развёрнутые связи из ответа превращаются в идентификаторы', () async {
      adapter.handler = (o) async => json(200, productJson('7'));

      final product = await products.findById('7');

      expect(product!.manufacturerId, '2');
      expect(product.categoryIds, ['1']);
      expect(product.materialIds, ['4', '9']);
    });

    test('404 при чтении записи — это null, а не ошибка', () async {
      adapter.handler = (o) async => json(404, {'message': 'Объект не найден'});

      expect(await products.findById('999'), isNull);
    });

    test('новый поиск отменяет незавершённый предыдущий', () async {
      adapter.handler = (o) async {
        final filter = o.queryParameters['filter'] as String?;
        if (filter == null || !filter.contains('шкаф')) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        return json(
          200,
          page([
            productJson(filter != null && filter.contains('шкаф') ? '2' : '1'),
          ]),
        );
      };

      final first = errorOf(() => products.find(const ProductQuery()));
      final second = await products.find(const ProductQuery(search: 'шкаф'));

      expect(await first, isA<CancelledException>());
      expect(second.items.single.id, '2');
    });

    test('служебные параметры __delay и __fail добавляются из меню', () async {
      debug
        ..slowResponses = true
        ..failResponses = true;
      adapter.handler = (o) async => json(200, page([]));

      await products.find(const ProductQuery());

      expect(adapter.requests.first.uri.queryParameters['__delay'], '1500');
      expect(adapter.requests.first.uri.queryParameters['__fail'], '500');
    });
  });

  group('Запись', () {
    test(
      'на сервер уходят идентификаторы связей, без id и deletedAt',
      () async {
        auth.adoptTokensForTest(accessToken: 'token-1');
        adapter.handler = (o) async => json(200, productJson('42'));

        final created = await products.create(sofa);

        final post = adapter.requests.last;
        final body = post.data as Map<String, dynamic>;
        expect(post.method, 'POST');
        expect(body['manufacturer'], '2');
        expect(body['categories'], ['1']);
        expect(body['width_cm'], 210);
        expect(body.containsKey('id'), isFalse);
        expect(body.containsKey('deletedAt'), isFalse);
        expect(post.headers['Authorization'], 'Bearer token-1');
        expect(created.id, '42');
      },
    );

    test('422 — ошибки привязаны к полям формы', () async {
      auth.adoptTokensForTest(accessToken: 'token-1');
      adapter.handler = (o) async => json(400, {
        'message': 'Ошибка валидации',
        'data': {
          'sku': {'message': 'Артикул DV-1001 уже есть у другого товара'},
        },
      });

      final error = await errorOf(() => products.create(sofa));

      expect(error, isA<ApiValidationException>());
      expect(error, isA<ValidationException>());
      expect(
        (error as ValidationException).errors['sku'],
        'Артикул DV-1001 уже есть у другого товара',
      );
    });

    test('409 — текст сервера доходит до пользователя', () async {
      auth.adoptTokensForTest(accessToken: 'token-1');
      final manufacturers = ApiManufacturerRepository(dio);
      adapter.handler = (o) async => json(409, {
        'message':
            'Нельзя удалить «Северный лес»: на него ссылаются 5 товаров.',
      });

      final error = await errorOf(() => manufacturers.softDelete('2'));

      expect(error, isA<ConflictException>());
      expect(
        (error as RepositoryException).message,
        'Нельзя удалить «Северный лес»: на него ссылаются 5 товаров.',
      );
    });

    test('409 при заказе больше, чем есть на складе', () async {
      auth.adoptTokensForTest(accessToken: 'token-1');
      final orders = ApiOrderRepository(dio);
      adapter.handler = (o) async => json(409, {
        'message': 'На складе только 3 шт. товара «Диван «Осло»»',
      });

      final error = await errorOf(
        () => orders.place(customerId: '1', productId: '7', quantity: 5),
      );

      expect(error, isA<ConflictException>());
      expect(adapter.requests.single.path, '/api/collections/orders/records');
    });

    test(
      'истёкший токен: обновляется через refresh и запрос повторяется',
      () async {
        auth.adoptTokensForTest(accessToken: 'old', refreshToken: 'refresh-1');
        var refreshes = 0;
        adapter.handler = (o) async {
          if (o.path.contains('auth-refresh')) {
            refreshes++;
            return json(200, {
              'token': 'fresh',
              'record': {
                'id': '1',
                'username': 'manager',
                'name': 'Менеджер',
                'role': 'manager',
              },
            });
          }
          return o.headers['Authorization'] == 'Bearer fresh'
              ? json(200, productJson('7'))
              : json(401, {'message': 'Требуется аутентификация'});
        };

        await products.softDelete('7');

        expect(refreshes, 1);
        expect(adapter.requests.length, 3);
        expect(adapter.requests.first.method, 'PATCH');
      },
    );

    test('403 — недостаточно прав', () async {
      auth.adoptTokensForTest(accessToken: 'viewer-token');
      adapter.handler = (o) async =>
          json(403, {'message': 'Операция доступна начиная с роли «manager»'});

      final error = await errorOf(() => products.softDelete('7'));

      expect(error, isA<ForbiddenException>());
    });
  });

  group('Сбои и повторы', () {
    test(
      'сервер выключен — NetworkException после трёх повторов GET',
      () async {
        adapter.handler = offline;

        final error = await errorOf(() => products.find(const ProductQuery()));

        expect(error, isA<NetworkException>());
        expect(adapter.requests.length, 4);
      },
    );

    test('POST при сбое сети не повторяется', () async {
      auth.adoptTokensForTest(accessToken: 'token-1');
      adapter.handler = offline;

      final error = await errorOf(() => products.create(sofa));

      expect(error, isA<NetworkException>());
      expect(adapter.requests.length, 1);
    });

    test('500 повторяется, и если сервер ожил — данные приходят', () async {
      var call = 0;
      adapter.handler = (o) async => ++call < 3
          ? json(500, {'message': 'Ошибка'})
          : json(200, page([productJson('1')]));

      final result = await products.find(const ProductQuery());

      expect(result.items.length, 1);
      expect(adapter.requests.length, 3);
    });

    test('400 и 404 не повторяются', () async {
      adapter.handler = (o) async => json(404, {'message': 'Ресурс не найден'});

      final error = await errorOf(
        () => ApiCategoryRepository(
          dio,
        ).find(const BasicQuery(spec: categoryQuerySpec)),
      );

      expect(error, isA<NotFoundException>());
      expect(adapter.requests.length, 1);
    });

    test('коды ответа переводятся в свои исключения', () {
      expect(mapHttpError(401, null), isA<UnauthorizedException>());
      expect(mapHttpError(403, null), isA<ForbiddenException>());
      expect(mapHttpError(404, null), isA<NotFoundException>());
      expect(mapHttpError(409, null), isA<ConflictException>());
      expect(mapHttpError(422, null), isA<ApiValidationException>());
      expect(mapHttpError(503, null), isA<ServerException>());
    });
  });
}
