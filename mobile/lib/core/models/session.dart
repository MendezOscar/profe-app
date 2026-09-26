class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    this.mustChangePassword = false,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final String userId;
  final String email;
  final String fullName;
  final String role;
  final bool mustChangePassword;

  bool get isExpired => DateTime.now().isAfter(accessTokenExpiresAt.subtract(const Duration(seconds: 30)));

  factory Session.fromAuthResponse(Map<String, dynamic> json) {
    final tokens = json['tokens'] as Map<String, dynamic>;
    final user = json['user'] as Map<String, dynamic>;
    return Session(
      accessToken: tokens['accessToken'] as String,
      refreshToken: tokens['refreshToken'] as String,
      accessTokenExpiresAt: DateTime.parse(tokens['accessTokenExpiresAt'] as String),
      userId: user['userId'] as String,
      email: user['email'] as String,
      fullName: user['fullName'] as String,
      role: user['role'] as String? ?? 'Docente',
      mustChangePassword: user['mustChangePassword'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
        'userId': userId,
        'email': email,
        'fullName': fullName,
        'role': role,
        'mustChangePassword': mustChangePassword,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessTokenExpiresAt: DateTime.parse(json['accessTokenExpiresAt'] as String),
        userId: json['userId'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        role: json['role'] as String? ?? 'Docente',
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      );
}
