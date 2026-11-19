import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import 'api_session.dart';
import 'debug_options.dart';

typedef ApiLogger = void Function(String line);

/// Создаёт настроенный клиент Dio. Это единственное место в приложении, где известны адрес сервера, тайм-ауты и заголовки.
Dio buildDio({
  required String baseUrl,
  ApiSession? session,
  DebugOptions? debug,
  ApiLogger? log,
  RetryPolicy retry = const RetryPolicy(),
  HttpClientAdapter? adapter,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      // Без VPN до Railway бывает 10–20+ с; 5 с давали ложный «не отвечает».
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // Ответы 4xx не считаются ошибкой транспорта: у них есть тело
      // с сообщением, и его разбирает перехватчик ниже.
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;

  final logger = log ?? (line) => developer.log(line, name: 'api');

  dio.interceptors.addAll([
    if (debug != null) DebugParamsInterceptor(debug),
    ErrorStatusInterceptor(),
    LoggingInterceptor(logger),
    if (session != null) AuthInterceptor(session, dio),
    RetryInterceptor(dio, retry, logger),
  ]);
  return dio;
}

class DebugParamsInterceptor extends Interceptor {
  DebugParamsInterceptor(this.debug);

  final DebugOptions debug;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.queryParameters = {
      ...options.queryParameters,
      ...debug.queryParameters,
    };
    handler.next(options);
  }
}

/// Подставляет токен в заголовок `Authorization`.
/// При 401 обновляет токен через refresh и один раз повторяет запрос.
/// Запросы `/auth/` не трогает — иначе неверный пароль завёл бы цикл.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.session, this.dio);

  final ApiSession session;
  final Dio dio;

  static const _retried = 'authRetried';

  bool _skip(RequestOptions o) => o.extra[ApiSession.skipAuth] == true;
  bool _isAuthPath(RequestOptions o) {
    final p = o.path;
    if (p.contains('auth-with-password') || p.contains('auth-refresh')) {
      return true;
    }
    return p.contains('/collections/users/records') &&
        o.method.toUpperCase() == 'POST' &&
        o.extra[ApiSession.skipAuth] == true;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_skip(options)) {
      final token = session.accessToken;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final unauthorized = err.response?.statusCode == 401;
    if (!unauthorized ||
        _skip(request) ||
        _isAuthPath(request) ||
        request.extra[_retried] == true) {
      return handler.next(err);
    }
    try {
      await session.auth.refreshTokens();
      final token = session.accessToken;
      if (token == null) return handler.next(err);
      request.headers['Authorization'] = 'Bearer $token';
      request.extra[_retried] = true;
      handler.resolve(await dio.fetch<dynamic>(request));
    } catch (_) {
      await session.auth.logout(); // без зацикливания
      handler.next(err);
    }
  }
}

class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(this.log);

  final ApiLogger log;

  static const _started = 'startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_started] = DateTime.now();
    log('→ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    log(
      '← ${response.statusCode} ${response.requestOptions.method} '
      '${response.requestOptions.uri.path} ${_elapsed(response.requestOptions)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    log(
      '✕ ${status ?? err.type.name} ${err.requestOptions.method} '
      '${err.requestOptions.uri.path} ${_elapsed(err.requestOptions)}',
    );
    handler.next(err);
  }

  String _elapsed(RequestOptions o) {
    final started = o.extra[_started];
    if (started is! DateTime) return '';
    return '(${DateTime.now().difference(started).inMilliseconds} мс)';
  }
}

/// Ответ 4xx пришёл как обычный (см. `validateStatus`). Здесь он
/// превращается в ошибку с нужным исключением внутри.
class ErrorStatusInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: response.requestOptions,
          response: response,
        ),
        true, // передать ошибку дальше — перехватчикам 401 и повтора
      );
      return;
    }
    handler.next(response);
  }
}

class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 400),
  });

  const RetryPolicy.none() : maxRetries = 0, baseDelay = Duration.zero;

  final int maxRetries;
  final Duration baseDelay;

  Duration delayFor(int attempt) => baseDelay * (1 << (attempt - 1));
}

/// Повтор запроса при сбое сети, тайм-ауте и ответах 5xx.
/// Повторяются только GET: чтение можно безопасно выполнить ещё раз, а повтор POST при потерянном ответе создал бы вторую запись.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this.dio, this.policy, this.log);

  final Dio dio;
  final RetryPolicy policy;
  final ApiLogger log;

  static const _attempt = 'retryAttempt';

  bool _shouldRetry(DioException e) {
    if (e.requestOptions.method != 'GET') return false;
    if (e.type == DioExceptionType.cancel) return false;
    final status = e.response?.statusCode;
    if (status != null) return status >= 500;
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.unknown;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final attempt = (request.extra[_attempt] as int? ?? 0) + 1;
    if (!_shouldRetry(err) || attempt > policy.maxRetries) {
      return handler.next(err);
    }

    final delay = policy.delayFor(attempt);
    log(
      '↻ повтор $attempt из ${policy.maxRetries} через ${delay.inMilliseconds} мс',
    );
    await Future<void>.delayed(delay);

    if (request.cancelToken?.isCancelled ?? false) return handler.next(err);
    request.extra[_attempt] = attempt;
    try {
      handler.resolve(await dio.fetch<dynamic>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Сохраняет за собой последний запрос и отменяет его, когда начинается новый.
class LatestRequest {
  CancelToken? _token;

  CancelToken next() {
    _token?.cancel('Запущен новый запрос');
    return _token = CancelToken();
  }

  void cancel() => _token?.cancel('Запрос больше не нужен');
}
