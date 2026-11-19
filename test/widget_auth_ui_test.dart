import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_store/api/auth_api.dart';
import 'package:furniture_store/models/app_user.dart';
import 'package:furniture_store/models/role.dart';
import 'package:furniture_store/screens/login_screen.dart';
import 'package:furniture_store/state/auth_notifier.dart';
import 'package:furniture_store/state/debug_settings_notifier.dart';
import 'package:furniture_store/widgets/app_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AuthNotifier> createAuth({Role role = Role.viewer}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = AuthNotifier(prefs, AuthApi(Dio()));
  auth.adoptTokensForTest(
    accessToken: 'test-token',
    user: AppUser(
      id: '1',
      username: role.code,
      fullName: role.label,
      role: role,
    ),
  );
  return auth;
}

Widget shellApp(AuthNotifier auth, {Size size = const Size(1280, 800)}) {
  final router = GoRouter(
    initialLocation: '/products',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/products',
            builder: (context, state) => const Center(child: Text('Каталог')),
          ),
          GoRoute(
            path: '/my-orders',
            builder: (context, state) => const Center(child: Text('Заказы')),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) =>
                const Center(child: Text('Пользователи экран')),
          ),
        ],
      ),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider(create: (_) => DebugSettingsNotifier()),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Валидация формы входа', () {
    testWidgets('форма не отправляется с пустым логином и паролем', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthNotifier(prefs, AuthApi(Dio()));

      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: '/register',
            builder: (context, state) =>
                const Scaffold(body: Text('Регистрация')),
          ),
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('Домой')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.tap(find.text('Войти'));
      await tester.pump();

      expect(find.text('Введите логин'), findsOneWidget);
      expect(find.text('Введите пароль'), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
    });
  });

  group('Навигация по ролям', () {
    testWidgets('у покупателя скрыты админ-разделы', (tester) async {
      final auth = await createAuth(role: Role.viewer);
      await tester.pumpWidget(shellApp(auth));
      await tester.pumpAndSettle();

      expect(find.text('Каталог'), findsWidgets);
      expect(find.text('Мои заказы'), findsOneWidget);
      expect(find.text('Пользователи'), findsNothing);
      expect(find.text('Статистика'), findsNothing);
      expect(find.text('Покупатели'), findsNothing);
    });

    testWidgets('у администратора видны пользователи и статистика', (
      tester,
    ) async {
      final auth = await createAuth(role: Role.admin);
      await tester.pumpWidget(shellApp(auth));
      await tester.pumpAndSettle();

      expect(find.text('Пользователи'), findsOneWidget);
      expect(find.text('Статистика'), findsOneWidget);
      expect(find.text('Мои заказы'), findsNothing);
    });
  });

  group('Адаптивная навигация', () {
    testWidgets('на узком окне навигация снизу', (tester) async {
      final auth = await createAuth(role: Role.manager);
      await tester.pumpWidget(shellApp(auth, size: const Size(360, 740)));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('на широком окне боковая полоса', (tester) async {
      final auth = await createAuth(role: Role.manager);
      await tester.pumpWidget(shellApp(auth, size: const Size(1280, 800)));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
