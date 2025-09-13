class User {
  final String email;
  final String password;

  User({required this.email, required this.password});

  // JSON'a dönüştürme (SharedPreferences için)
  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
    };
  }

  // JSON'dan oluşturma
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      email: json['email'],
      password: json['password'],
    );
  }
}
