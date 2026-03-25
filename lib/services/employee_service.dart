import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:shiftsmart/models/employee.dart';
import 'package:shiftsmart/models/empcert_model.dart'; // 👈 Ensure this model is imported
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmployeeService {
  final ApiClient _apiClient = ApiClient();

  // --- Environment Variables ---
  final String baseUrl = dotenv.env['BASE_URL'] ?? ""; // Safe getters for keys
  final String certBaseUrl = dotenv.env['CERT_BASE_URL'] ?? "";

  String fetchEmpKey = dotenv.env['FETCH_EMP_KEY'] ?? "";
  String get uploadKey => dotenv.env['CERT_UPLOAD_KEY'] ?? '';
  String get fetchKey => dotenv.env['FETCH_DOCUMENTS1_KEY'] ?? '';
  String empNameMap = dotenv.env['EMP_NAME_MAP_KEY'] ?? "";

  EmployeeService() {
    if (baseUrl.isEmpty) debugPrint("❌ EmployeeService: BASE_URL is missing");
  }
  final String bankLookupKey = dotenv.env['BANK_LOOKUP_KEY'] ?? '';

  // ✅ Keys for documents
  final String empDocsKey = dotenv.env['EMP_DOCS_KEY'] ?? '';
  final String certUploadKey = dotenv.env['CERT_UPLOAD_KEY'] ?? '';

  // --- 1. Fetch All Employees ---
  Future<List<Employee>> fetchAllEmployees() async {
    final url = '$baseUrl/employee/all?code=$fetchEmpKey';
    debugPrint("🔍 EmployeeService: Fetching all employees from $url");
    try {
      final response = await _apiClient.get(url, useAuth: true);
      debugPrint("📡 EmployeeService Status: ${response.statusCode}");
      debugPrint("📄 EmployeeService Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}");

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        debugPrint("✅ EmployeeService: Found ${jsonData.length} employees.");
        final filtered = jsonData.where((e) {
          final role = (e['userRole'] ?? '').toString().toLowerCase();
          return role != 'manager' && role != 'admin';
        }).toList();
        return filtered.map((e) => Employee.fromJson(e)).toList();
      } else {
        debugPrint("Failed to load employees: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("Error fetching employees: $e");
      return [];
    }
  }

  // --- 2. Fetch Employee Name Map ---
  Future<Map<int, String>> fetchEmployeeNameMap() async {
    final url = '$baseUrl/employee/all?code=$empNameMap';
    try {
      final response = await _apiClient.get(url, useAuth: true);
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return {
          for (var e in jsonData)
            (e['employeeId'] as num).toInt():
                _buildFullName(e['firstName'], e['middleName'], e['lastName']),
        };
      } else {
        debugPrint("Failed to load employee name map: ${response.statusCode}");
        return {};
      }
    } catch (e) {
      debugPrint("Error fetching employee name map: $e");
      return {};
    }
  }

  String _buildFullName(dynamic first, dynamic middle, dynamic last) {
    final firstName = first?.toString().trim() ?? '';
    final middleName = middle?.toString().trim() ?? '';
    final lastName = last?.toString().trim() ?? '';
    return [firstName, middleName.isNotEmpty ? middleName : lastName]
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  // --- 3. Bank Lookup ---
  Future<Map<String, dynamic>> lookupBank(String bsb) async {
    final String url = '$baseUrl/utility/bank-lookup/$bsb?code=$bankLookupKey';
    debugPrint("🚀 Calling Bank Lookup: $url");

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('appToken');

      Map<String, String> headers = {'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        debugPrint(
            "⚠️ Warning: No Auth Token found locally. Attempting request with API Key only.");
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      debugPrint("📡 Response Status: ${response.statusCode}");
      // debugPrint("📦 Response Body: ${response.body}");

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        return {
          'status': 'Error',
          'message': 'Unauthorized (401). API Key invalid or Token required.'
        };
      } else {
        return {
          'status': 'Error',
          'message': 'Lookup Failed: ${response.statusCode}'
        };
      }
    } catch (e) {
      debugPrint("❌ Exception: $e");
      return {'status': 'Error', 'message': "Connection error"};
    }
  }

  // --- 4. Upload Document (Multipart) ---
  Future<String?> uploadDocument(File file, String docType) async {
    // Use cert upload endpoint which supports multipart
    final String url = '$baseUrl/employee/document/upload?code=$certUploadKey';
    debugPrint("🚀 Uploading Document ($docType) to: $url");

    try {
      var request = http.MultipartRequest('POST', Uri.parse(url));

      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('appToken');
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(mimeType),
      ));

      request.fields['documentType'] = docType;

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint("📤 Upload Status: ${response.statusCode}");
      debugPrint("📦 Upload Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['url'] ?? data['DocumentUrl'] ?? data['documentUrl'] ?? 'uploaded';
      } else {
        debugPrint("❌ Upload failed with ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Upload Error: $e");
    }
    return null;
  }

  // --- 🌟 5. Fetch Documents for an Employee ---
  Future<List<EmployeeCertificate>> fetchEmployeeDocuments(int empId) async {
    // Use /employee/documents/{id} with EMP_DOCS_KEY
    final url = '$baseUrl/employee/documents/$empId?code=$empDocsKey';
    debugPrint("🔍 Fetching Documents from: $url");

    try {
      final response = await _apiClient.get(url, useAuth: false);

      debugPrint("📦 Document Fetch Status: ${response.statusCode}");
      debugPrint("📦 Document Fetch Body: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}");

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);

        List<dynamic> rawDocs = [];

        // Handle both List and Map responses
        if (data is List) {
          rawDocs = data;
        } else if (data is Map<String, dynamic>) {
          rawDocs = data['Documents'] ?? data['ApprovedDocuments'] ?? data['Result'] ?? [];
        }

        debugPrint("✅ Documents parsed: ${rawDocs.length}");

        return rawDocs.map<EmployeeCertificate>((doc) {
          return EmployeeCertificate(
            documentId: doc['DocumentId'] ?? 0,
            employeeId: empId,
            fileName: doc['DocumentType'] ?? doc['FileName'] ?? 'Document',
            fileType: doc['DocumentType'] ?? 'General',
            documentUrl: doc['DocumentUrl'] ?? '',
            documentType: doc['DocumentType'] ?? 'General',
            status: doc['Status'] ?? 'Approved',
            uploadedAt: doc['UploadedAt'] ?? DateTime.now().toIso8601String(),
            remarks: doc['Remarks'],
            updatedAt: doc['UpdatedAt'],
          );
        }).toList();
      } else {
        debugPrint("⚠️ Failed to fetch docs. Status: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching profile docs: $e");
      return [];
    }
  }
}
