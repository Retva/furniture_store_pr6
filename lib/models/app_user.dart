import 'json_read.dart';
import 'role.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String username;
  final String fullName;
  final Role role;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: JsonRead.id(json['id']),
      username: json['username'] as String? ?? '',
      fullName: json['fullName'] as String? ?? json['name'] as String? ?? '',
      role: Role.fromCode(json['role'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'fullName': fullName,
    'role': role.code,
  };

  AppUser copyWith({
    String? id,
    String? username,
    String? fullName,
    Role? role,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
    );
  }
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final AppUser user;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('token')) {
      final token = json['token'] as String;
      final record = json['record'] as Map<String, dynamic>? ?? const {};
      return AuthTokens(
        accessToken: token,
        refreshToken: token,
        expiresIn: 86_400,
        user: AppUser.fromJson({
          'id': record['id'],
          'username': record['username'],
          'fullName': record['name'] ?? record['fullName'],
          'role': record['role'],
        }),
      );
    }
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 900,
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
