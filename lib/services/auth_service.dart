import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

class AuthService {
  // Dependencies
  final ApiClient _apiClient = ApiClient();
  final _storage = const FlutterSecureStorage();

  // Environment Keys
  String baseUrl = dotenv.env['BASE_URL'] ?? '';
  String fallbackBaseUrl = dotenv.env['BASE_URL_FALLBACK'] ?? '';
  String loginKey = dotenv.env['LOGIN_KEY'] ?? '';
  String empProfileKey = dotenv.env['FETCH_PROFILE_KEY'] ?? '';
  String logOutKey = dotenv.env['LOGOUT_KEY'] ?? '';

  // 🛠️ CRITICAL: Ensure this key matches your .env exactly
  String fetchRejectedKey = dotenv.env['FETCH_REJECTED_KEY'] ?? '';

  // Normalize URL by trimming trailing slash
  String _normalizeUrl(String url) {
    return url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  // Build a list of candidate base URLs, with fallback support.
  List<String> _candidateBaseUrls() {
    final urls = <String>[];

    if (baseUrl.isNotEmpty) urls.add(baseUrl);
    if (fallbackBaseUrl.isNotEmpty) urls.add(fallbackBaseUrl);

    // Auto-generated fallback candidates for common Azure naming differences
    final uri = Uri.tryParse(_normalizeUrl(baseUrl));
    if (uri != null && uri.host.contains('azurewebsites.net')) {
      final host = uri.host;

      if (host.contains('-prod-mt')) {
        final alt = host.replaceFirst('-prod-mt', '-prod');
        urls.add(uri.replace(host: alt).toString());
      }

      if (host.contains('-prod-mt')) {
        final alt = host.replaceFirst('-prod-mt', '-uat-mt');
        urls.add(uri.replace(host: alt).toString());
      }

      if (host.contains('-prod')) {
        final alt = host.replaceFirst('-prod', '-prod-mt');
        urls.add(uri.replace(host: alt).toString());
      }
    }

    // Preserve order and uniqueness
    return urls.toSet().toList();
  }

  /// STEP 1: Login
  Future<Map<String, dynamic>?> login(String email, String password) async {
    final List<String> candidates = _candidateBaseUrls();

    if (candidates.isEmpty) {
      return {
        'Message':
            'Connection error: BASE_URL is not configured. Please check .env.'
      };
    }

    String lastError = 'No endpoint tried yet.';

    for (final candidate in candidates) {
      final String base = _normalizeUrl(candidate);
      String loginUrl = '$base/employee/login';
      if (loginKey.isNotEmpty) {
        loginUrl += '?code=$loginKey';
      }

      final requestBody = {'Email': email, 'Password': password};

      try {
        final response = await _apiClient.post(
          loginUrl,
          body: requestBody,
          useAuth: false,
        );

        print('🔹 Login URL: $loginUrl');
        print('🔹 Login Status: ${response.statusCode}');
        print('🔹 Login Body: ${response.body}');

        dynamic decodedBody;
        try {
          decodedBody = jsonDecode(response.body);
        } catch (e) {
          decodedBody = null;
        }

        if (decodedBody is Map<String, dynamic>) {
          if (response.statusCode != 200) {
            decodedBody['statusCode'] = response.statusCode;
          }
          return decodedBody;
        }

        if (response.statusCode != 200) {
          return {
            'Message': 'Server Error (${response.statusCode}): ${response.body}'
          };
        }

        return decodedBody;
      } on SocketException catch (e) {
        lastError = 'Socket/DNS failure for $loginUrl: ${e.message}';
        print('⚠️ $lastError');
        continue;
      } catch (e) {
        return {'Message': 'Connection error: ${e.toString()}'};
      }
    }

    return {
      'Message': 'Connection error: All endpoints unreachable. $lastError'
    };
  }

  /// STEP 2: Exchange Password for Token
  Future<Map<String, dynamic>?> exchangePasswordForToken(
      String email, String password) async {
    final String exchangeUrl = '$baseUrl/auth/exchange-password';

    try {
      final requestBody = {'Email': email, 'Password': password};

      final response = await _apiClient.post(
        exchangeUrl,
        body: requestBody,
        useAuth: false,
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final String token =
            decodedResponse['appToken'] ?? decodedResponse['AppToken'];
        await _storage.write(key: 'appToken', value: token);
        print("✅ AppToken saved.");
        return decodedResponse;
      } else {
        return {
          "Message":
              "Exchange failed (${response.statusCode}): ${response.body}"
        };
      }
    } catch (e) {
      return {"Message": "Exchange error: ${e.toString()}"};
    }
  }

  /// Fetch Rejected Data (For Resubmission)
  /// 🛠️ HEAVILY UPDATED with Debugging
  Future<Map<String, dynamic>?> fetchRejectedProfileData(int employeeId) async {
    print(
        "🔹 AuthService: Starting fetchRejectedProfileData for ID: $employeeId");

    // 1. Check Key
    if (fetchRejectedKey.isEmpty) {
      print(
          "❌ CRITICAL ERROR: FETCH_REJECTED_KEY is missing in .env or AuthService!");
      return null;
    }

    // 2. Build URL
    final url =
        '$baseUrl/employee/rejected-info/$employeeId?code=$fetchRejectedKey';

    // Debug print (Hide actual key for logs)
    print("🔹 Requesting URL: .../employee/rejected-info/$employeeId?code=***");

    try {
      // 3. Make Request (useAuth: false is mandatory here)
      final response = await _apiClient.get(url, useAuth: false);

      print("🔹 Rejected Data Response Status: ${response.statusCode}");
      print("🔹 Rejected Data Response Body: ${response.body}");

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("❌ Failed to fetch data. Status: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("❌ Exception in fetchRejectedProfileData: $e");
      return null;
    }
  }

  /// Fetch Full Profile (Requires Token)
  Future<Map<String, dynamic>?> fetchFullEmployeeProfile(String email) async {
    final encodedEmail = Uri.encodeComponent(email);
    final url = '$baseUrl/employee/profile/$encodedEmail?code=$empProfileKey';

    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Fetch Profile Failed: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error fetching profile: $e");
      return null;
    }
  }

  /// Logout
  Future<bool> logout(int? employeeId) async {
    final tokenBeforeDelete = await _storage.read(key: 'appToken');
    await _storage.delete(key: 'appToken');

    if (tokenBeforeDelete == null || employeeId == null) return true;

    String logoutUrl = '$baseUrl/employee/logout';
    if (logOutKey.isNotEmpty) {
      logoutUrl += '?code=$logOutKey';
    }

    try {
      await _apiClient.post(
        logoutUrl,
        body: {"employeeId": employeeId},
        useAuth: true,
      );
      return true;
    } catch (e) {
      return true;
    }
  }

  // --- FORGOT PASSWORD KEYS ---
  String forgotRequestKey = dotenv.env['FORGOT_PASS_REQUEST_KEY'] ?? '';
  String forgotVerifyKey = dotenv.env['FORGOT_PASS_VERIFY_KEY'] ?? '';
  String forgotResetKey = dotenv.env['FORGOT_PASS_RESET_KEY'] ?? '';

  // --- FORGOT PASSWORD (TOKEN-BASED FLOW) ---

  // 1. Request OTP (Returns the Reset Token ID)
  Future<String?> requestPasswordReset(String email) async {
    if (forgotRequestKey.isEmpty) {
      print("❌ CRITICAL: FORGOT_PASS_REQUEST_KEY is missing in .env!");
      return null;
    }

    final url =
        '$baseUrl/employee/forgot-password/request?code=$forgotRequestKey';

    print("🔹 Requesting OTP for: $email");

    try {
      final response = await _apiClient.post(
        url,
        body: {"EmailOrPhone": email},
        useAuth: false,
      );

      print("🔹 OTP Request Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Parse the JSON response to get the token
        final data = jsonDecode(response.body);
        final token = data['resetTokenId']; // 👈 This is the key!
        print("✅ Received Reset Token: $token");
        return token.toString();
      } else {
        print("🔹 OTP Request Failed: ${response.body}");
        return null;
      }
    } catch (e) {
      print("🔴 Request OTP Exception: $e");
      return null;
    }
  }

  // 2. Verify OTP (Uses ResetTokenId, not Email)
  Future<bool> verifyResetOtp(String resetTokenId, String otp) async {
    final url =
        '$baseUrl/employee/forgot-password/verify?code=$forgotVerifyKey';

    // Backend expects ResetTokenId and Code
    final body = {"ResetTokenId": resetTokenId, "Code": otp};

    print("🔹 Verifying OTP...");
    print("🔹 Body: $body");

    try {
      final response = await _apiClient.post(
        url,
        body: body,
        useAuth: false,
      );

      if (response.statusCode != 200) {
        print("🔹 Verify Failed: ${response.body}");
      }
      return response.statusCode == 200;
    } catch (e) {
      print("Verify OTP Error: $e");
      return false;
    }
  }

  // 3. Reset Password (Uses ResetTokenId)
  Future<bool> resetPassword(
      String resetTokenId, String otp, String newPassword) async {
    final url = '$baseUrl/employee/forgot-password/reset?code=$forgotResetKey';

    // Backend expects ResetTokenId, Code, and NewPassword
    final body = {
      "ResetTokenId": resetTokenId,
      "Code": otp,
      "NewPassword": newPassword
    };

    print("🔹 Resetting Password...");

    try {
      final response = await _apiClient.post(
        url,
        body: body,
        useAuth: false,
      );

      if (response.statusCode != 200) {
        print("🔹 Reset Failed: ${response.body}");
      }
      return response.statusCode == 200;
    } catch (e) {
      print("Reset Password Error: $e");
      return false;
    }
  }
}
