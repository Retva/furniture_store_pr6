import 'package:dio/dio.dart';

import '../../api/api_exception.dart';
import '../../models/basic_query.dart';
import '../../models/customer.dart';
import '../../models/furniture_material.dart';
import '../../models/manufacturer.dart';
import '../../models/manufacturer_query.dart';
import '../../models/product.dart';
import '../../models/product_category.dart';
import '../../models/page_result.dart';
import '../../models/product_query.dart';
import '../category_repository.dart';
import '../customer_repository.dart';
import '../manufacturer_repository.dart';
import '../material_repository.dart';
import '../product_repository.dart';
import 'api_crud_repository.dart';
import 'pb_api.dart';

class ApiProductRepository extends ApiCrudRepository<Product, ProductQuery>
    implements ProductRepository {
  ApiProductRepository(super.dio)
    : super(
        resource: 'products',
        fromJson: (json) => Product.fromJson(PbApi.productFromPb(json)),
        toInput: (p) => PbApi.productToPb(p.toJson()),
        listParams: _productListParams,
      );

  static Map<String, dynamic> _productListParams(ProductQuery q) {
    final parts = <String>[
      if (!q.includeDeleted) PbApi.activeOnly(includeDeleted: false),
      if (q.search.trim().isNotEmpty)
        PbApi.searchOr(q.search, const ['name', 'sku']),
      if (q.categoryId != null)
        'categories ?~ "${PbApi.escapeFilter(q.categoryId!)}"',
      if (q.manufacturerId != null)
        'manufacturer = "${PbApi.escapeFilter(q.manufacturerId!)}"',
      if (q.priceFrom != null) 'price >= ${q.priceFrom}',
      if (q.priceTo != null) 'price <= ${q.priceTo}',
    ];
    return PbApi.listParams(
      page: q.page,
      perPage: q.size,
      sort: PbApi.sort(q.sortField, q.sortAscending),
      filter: PbApi.combineFilters(parts),
      expand: 'manufacturer,categories,materials',
    );
  }

  @override
  Future<int> countByManufacturer(String manufacturerId) => countWithFilter(
    PbApi.combineFilters([
      'manufacturer = "${PbApi.escapeFilter(manufacturerId)}"',
      PbApi.activeOnly(includeDeleted: false),
    ]),
  );

  @override
  Future<int> countByCategory(String categoryId) => countWithFilter(
    PbApi.combineFilters([
      'categories ?~ "${PbApi.escapeFilter(categoryId)}"',
      PbApi.activeOnly(includeDeleted: false),
    ]),
  );

  @override
  Future<int> countByMaterial(String materialId) => countWithFilter(
    PbApi.combineFilters([
      'materials ?~ "${PbApi.escapeFilter(materialId)}"',
      PbApi.activeOnly(includeDeleted: false),
    ]),
  );
}

class ApiManufacturerRepository
    extends ApiCrudRepository<Manufacturer, ManufacturerQuery>
    implements ManufacturerRepository {
  ApiManufacturerRepository(super.dio)
    : super(
        resource: 'manufacturers',
        fromJson: (json) =>
            Manufacturer.fromJson(PbApi.manufacturerFromPb(json)),
        toInput: (m) => PbApi.manufacturerToPb(m.toJson()),
        listParams: _manufacturerListParams,
      );

  static Map<String, dynamic> _manufacturerListParams(ManufacturerQuery q) {
    final parts = <String>[
      if (!q.includeDeleted) PbApi.activeOnly(includeDeleted: false),
      if (q.search.trim().isNotEmpty)
        PbApi.searchOr(q.search, const ['name', 'country']),
      if (q.country != null) 'country = "${PbApi.escapeFilter(q.country!)}"',
    ];
    return PbApi.listParams(
      page: q.page,
      perPage: q.size,
      sort: PbApi.sort(q.sortField, q.sortAscending),
      filter: PbApi.combineFilters(parts),
      expand: 'materials',
    );
  }

  @override
  Future<List<String>> countries() async {
    final all = await findAll(includeDeleted: false);
    return ({for (final m in all) m.country}.toList()..sort());
  }
}

class ApiCategoryRepository
    extends ApiCrudRepository<ProductCategory, BasicQuery>
    implements CategoryRepository {
  ApiCategoryRepository(super.dio)
    : super(
        resource: 'categories',
        fromJson: (json) =>
            ProductCategory.fromJson(PbApi.categoryFromPb(json)),
        toInput: (c) => PbApi.categoryToPb(c.toJson()),
        listParams: (q) => _basicListParams(q, const ['name']),
      );
}

class ApiMaterialRepository
    extends ApiCrudRepository<FurnitureMaterial, BasicQuery>
    implements MaterialRepository {
  ApiMaterialRepository(super.dio)
    : super(
        resource: 'materials',
        fromJson: (json) =>
            FurnitureMaterial.fromJson(PbApi.materialFromPb(json)),
        toInput: (m) => PbApi.materialToPb(m.toJson()),
        listParams: (q) => _basicListParams(
          q,
          const ['name', 'kind', 'origin'],
          extra: (query) {
            if (query.filter != null && query.filter!.isNotEmpty) {
              return 'kind = "${PbApi.escapeFilter(query.filter!)}"';
            }
            return '';
          },
        ),
      );
}

Map<String, dynamic> _basicListParams(
  BasicQuery q,
  List<String> searchFields, {
  String Function(BasicQuery)? extra,
}) {
  final parts = <String>[
    if (!q.includeDeleted) PbApi.activeOnly(includeDeleted: false),
    if (q.search.trim().isNotEmpty) PbApi.searchOr(q.search, searchFields),
    if (extra != null) extra(q),
  ];
  final sortField = q.sortField == 'discount' ? 'full_name' : q.sortField;
  return PbApi.listParams(
    page: q.page,
    perPage: q.size,
    sort: PbApi.sort(
      sortField,
      q.sortAscending,
      pbField: sortField == 'full_name' ? 'full_name' : null,
    ),
    filter: PbApi.combineFilters(parts),
  );
}

class ApiCustomerRepository extends ApiCrudRepository<Customer, BasicQuery>
    implements CustomerRepository {
  ApiCustomerRepository(this._dio)
    : super(
        _dio,
        resource: 'customers',
        fromJson: (json) => Customer.fromJson(PbApi.customerFromPb(json)),
        toInput: (c) => PbApi.customerToPb(c.toJson()),
        listParams: _customerListParams,
      );

  final Dio _dio;
  static const _cardsPath = '/api/collections/discount_cards/records';

  static Map<String, dynamic> _customerListParams(BasicQuery q) {
    final parts = <String>[
      if (!q.includeDeleted) PbApi.activeOnly(includeDeleted: false),
      if (q.search.trim().isNotEmpty)
        PbApi.searchOr(q.search, const ['full_name', 'email', 'phone']),
    ];
    return PbApi.listParams(
      page: q.page,
      perPage: q.size,
      sort: PbApi.sort(
        q.sortField == 'discount' ? 'full_name' : q.sortField,
        q.sortAscending,
        pbField: q.sortField == 'fullName' ? 'full_name' : null,
      ),
      filter: PbApi.combineFilters(parts),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _cardsByCustomer(
    List<String> customerIds,
  ) async {
    if (customerIds.isEmpty) return {};
    final filter = customerIds
        .map((id) => 'customer = "${PbApi.escapeFilter(id)}"')
        .join(' || ');
    final response = await _dio.get<Map<String, dynamic>>(
      _cardsPath,
      queryParameters: {'page': 1, 'perPage': 500, 'filter': filter},
    );
    final items = response.data!['items'] as List? ?? const [];
    final map = <String, Map<String, dynamic>>{};
    for (final row in items) {
      final card = (row as Map).cast<String, dynamic>();
      final cust = card['customer']?.toString() ?? '';
      if (cust.isNotEmpty) map[cust] = card;
    }
    return map;
  }

  Future<List<String>> _customerIdsWithCardFilter(BasicQuery q) async {
    if (q.filter != 'yes' && q.filter != 'no') return const [];
    final response = await _dio.get<Map<String, dynamic>>(
      _cardsPath,
      queryParameters: {'page': 1, 'perPage': 500},
    );
    final withCard = <String>{
      for (final row in response.data!['items'] as List? ?? const [])
        '${(row as Map)['customer']}',
    };
    if (q.filter == 'yes') return withCard.toList();
    final customers = await _dio.get<Map<String, dynamic>>(
      '/api/collections/customers/records',
      queryParameters: {'page': 1, 'perPage': 500, 'filter': 'deleted_at = ""'},
    );
    final all = [
      for (final row in customers.data!['items'] as List? ?? const [])
        '${(row as Map)['id']}',
    ];
    return all.where((id) => !withCard.contains(id)).toList();
  }

  @override
  Future<PageResult<Customer>> find(BasicQuery query) => guard(() async {
    final params = Map<String, dynamic>.from(listParams(query));
    if (query.filter == 'yes' || query.filter == 'no') {
      final ids = await _customerIdsWithCardFilter(query);
      if (ids.isEmpty) return PageResult.empty(size: query.size);
      final cardFilter = ids
          .map((id) => 'id = "${PbApi.escapeFilter(id)}"')
          .join(' || ');
      final base = params['filter'] as String? ?? '';
      params['filter'] = PbApi.combineFilters([base, cardFilter]);
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/collections/customers/records',
      queryParameters: params,
    );
    final raw = response.data!;
    final rows = raw['items'] as List? ?? const [];
    final ids = [for (final row in rows) '${(row as Map)['id']}'];
    final cards = await _cardsByCustomer(ids);
    return PageResult<Customer>(
      items: [
        for (final row in rows)
          Customer.fromJson(
            PbApi.customerFromPb(
              (row as Map).cast<String, dynamic>(),
              cardPb: cards['${row['id']}'],
            ),
          ),
      ],
      page: raw['page'] as int,
      size: (raw['perPage'] as int?) ?? query.size,
      total: (raw['totalItems'] as int?) ?? 0,
    );
  });

  @override
  Future<Customer?> findById(String id) async {
    try {
      return await guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/collections/customers/records/$id',
        );
        final cards = await _cardsByCustomer([id]);
        return Customer.fromJson(
          PbApi.customerFromPb(response.data!, cardPb: cards[id]),
        );
      });
    } on NotFoundException {
      return null;
    }
  }

  @override
  Future<Customer> create(Customer item) => guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/collections/customers/records',
      data: toInput(item),
    );
    final id = '${response.data!['id']}';
    if (item.card != null) {
      await _dio.post<void>(
        _cardsPath,
        data: PbApi.discountCardToPb(id, item.card!.toJson()),
      );
    }
    notifyChanged();
    return (await findById(id))!;
  });

  @override
  Future<Customer> update(Customer item) => guard(() async {
    await _dio.patch<Map<String, dynamic>>(
      '/api/collections/customers/records/${item.id}',
      data: toInput(item),
    );
    await _syncCard(item);
    notifyChanged();
    return (await findById(item.id))!;
  });

  Future<void> _syncCard(Customer item) async {
    final existing = await _dio.get<Map<String, dynamic>>(
      _cardsPath,
      queryParameters: {
        'page': 1,
        'perPage': 1,
        'filter': 'customer = "${PbApi.escapeFilter(item.id)}"',
      },
    );
    final cards = existing.data!['items'] as List? ?? const [];
    if (item.card == null) {
      for (final row in cards) {
        await _dio.delete<void>('$_cardsPath/${(row as Map)['id']}');
      }
      return;
    }
    final body = PbApi.discountCardToPb(item.id, item.card!.toJson());
    if (cards.isEmpty) {
      await _dio.post<void>(_cardsPath, data: body);
    } else {
      await _dio.patch<void>(
        '$_cardsPath/${(cards.first as Map)['id']}',
        data: body,
      );
    }
  }
}
