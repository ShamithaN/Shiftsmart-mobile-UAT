import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // Kept only for image upload
import 'package:shiftsmart/models/job.dart';
import 'package:shiftsmart/models/job_role.dart';
import 'package:shiftsmart/models/job_role_type.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_client.dart';

class JobService {
  // 1. Initialize ApiClient
  final ApiClient _apiClient = ApiClient();

  final String baseUrl = dotenv.env['JOB_BASE_URL'] ?? "";
  String fetchJobKey = dotenv.env['FETCH_JOB_KEY'] ?? "";
  String addJobKey = dotenv.env['ADD_JOB_KEY'] ?? "";
  String imageJobKey = dotenv.env['JOB_IMAGE_KEY'] ?? "";
  String updateJobKey = dotenv.env['UPDATE_JOB_KEY'] ?? "";
  String updateJobImageKey = dotenv.env['UPDATE_JOB_IMAGE_KEY'] ?? "";
  String deleteJobKey = dotenv.env['DELETE_JOB_KEY'] ?? "";
  String completeJobKey = dotenv.env['COMPLETE_JOB_KEY'] ?? "";
  String jobRoleKey = dotenv.env['JOBROLE_KEY'] ?? "";
  String jobRoleTypeKey = dotenv.env['JOBROLE_TYPE_KEY'] ?? "";
  String jobRoleTypeCreateKey = dotenv.env['JOBROLE_TYPE_CREATE_KEY'] ?? "";
  String jobRoleTypeDeleteKey = dotenv.env['JOBROLE_TYPE_DELETE_KEY'] ?? "";

  JobService() {
    _debugEnv();
  }

  void _debugEnv() {
    if (baseUrl.isEmpty) debugPrint("❌ JobService: JOB_BASE_URL is missing");
    if (fetchJobKey.isEmpty) debugPrint("❌ JobService: FETCH_JOB_KEY is missing");
    // ... adding more checks if needed, but the ?? "" is already safer
  }


  // --- FETCH ALL JOBS ---
  Future<List<Job>> fetchAllJobs() async {
    final geturl = '$baseUrl/job/list?code=$fetchJobKey';
    debugPrint("Fetching Jobs from: $geturl");
    try {
      // Re-enabling useAuth: true as per approved plan
      final response = await _apiClient.get(geturl, useAuth: true);

      debugPrint("Job response status: ${response.statusCode}");
      debugPrint("Job response body: ${response.body}");

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is List) {
          if (jsonData.isNotEmpty) {
            return jsonData.map<Job>((data) => Job.fromJson(data)).toList();
          } else {
            debugPrint("Jobs list is empty from server.");
            return [];
          }
        } else {
          debugPrint("Unexpected data format: ${jsonData.runtimeType}");
          return [];
        }
      } else {
        debugPrint("Failed to load jobs. Status code: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("Error in fetchAllJobs: $e");
      return [];
    }
  }

  // --- ADD JOB (Data Only) ---
  Future<int?> addJob(Map<String, dynamic> jobData) async {
    final url = '$baseUrl/job/create?code=$addJobKey';
    try {
      // FIX: Use ApiClient with useAuth: true
      final response = await _apiClient.post(
        url,
        body: jobData,
        useAuth: true,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return 1;
      } else {
        return null;
      }
    } catch (e) {
      debugPrint("Error adding job data: $e");
      rethrow;
    }
  }

  // --- ADD JOB WITH IMAGE (Multipart Request) ---
  // Note: Multipart requests are special, so we manually add the token here.
  Future<bool> createJobWithImage(
      Map<String, dynamic> jobData, File image) async {
    final url = Uri.parse('$baseUrl/job/upload-with-image?code=$imageJobKey');
    try {
      final request = http.MultipartRequest("POST", url);

      // FIX: Manually get token and add header
      final token = await _apiClient.getAppToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['job'] = jsonEncode(jobData);
      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      final response = await request.send();

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        debugPrint("Failed to add job with image ${response.statusCode}");
        return false;
      }
    } catch (e) {
      debugPrint("Error occured while adding job with image $e");
      rethrow;
    }
  }

  // --- UPDATE JOB ---
  Future<bool> updateJob(int jobId, Map<String, dynamic> jobData) async {
    final url = '$baseUrl/job/update/$jobId?code=$updateJobKey';
    try {
      // FIX: Use ApiClient with useAuth: true
      final response = await _apiClient.put(
        url,
        body: jobData,
        useAuth: true,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint("Error updating job: $e");
      rethrow;
    }
  }

  // --- FETCH JOB ROLES ---
  Future<List<JobRole>> fetchJobRole(int jobId) async {
    final url = '$baseUrl/job/roles/$jobId?code=$jobRoleKey';
    try {
      // FIX: Use ApiClient with useAuth: true
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return jsonData.map((e) => JobRole.fromJson(e)).toList();
      } else {
        throw Exception("Failed to fetch job roles");
      }
    } catch (e) {
      debugPrint("Error fetching job roles");
      rethrow;
    }
  }

  // --- DELETE JOB ---
  Future<bool> deleteJob(int jobId) async {
    final url = '$baseUrl/job/delete/$jobId?code=$deleteJobKey';
    try {
      final response = await _apiClient.delete(url, useAuth: true);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("Error deleting job: $e");
      return false;
    }
  }

  // --- COMPLETE JOB ---
  Future<bool> completeJob(int jobId) async {
    final url = '$baseUrl/job/complete/$jobId?code=$completeJobKey';
    try {
      final response = await _apiClient.post(url, body: {}, useAuth: true);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("Error completing job: $e");
      return false;
    }
  }

  // --- UPDATE JOB WITH IMAGE ---
  Future<bool> updateJobWithImage(int jobId, Map<String, dynamic> jobData, File image) async {
    final url = Uri.parse('$baseUrl/job/update-with-image/$jobId?code=$updateJobImageKey');
    try {
      final request = http.MultipartRequest("PUT", url);

      final token = await _apiClient.getAppToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['job'] = jsonEncode(jobData);
      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      final response = await request.send();
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint("Error updating job with image: $e");
      return false;
    }
  }

  // --- FETCH JOB ROLE TYPES ---
  Future<List<JobRoleType>> fetchJobRoleType() async {
    final url = '$baseUrl/jobroletype/list?code=$jobRoleTypeKey';
    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return jsonData.map((e) => JobRoleType.fromJson(e)).toList();
      } else {
        throw Exception("Failed to fetch job role types");
      }
    } catch (e) {
      debugPrint("Error fetching data");
      rethrow;
    }
  }

  // --- CREATE JOB ROLE TYPE ---
  Future<bool> createJobRoleType(Map<String, dynamic> data) async {
    final url = '$baseUrl/jobroletype/create?code=$jobRoleTypeCreateKey';
    try {
      final response = await _apiClient.post(url, body: data, useAuth: true);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint("Error creating job role type: $e");
      return false;
    }
  }

  // --- DELETE JOB ROLE TYPE ---
  Future<bool> deleteJobRoleType(int id) async {
    final url = '$baseUrl/jobroletype/delete/$id?code=$jobRoleTypeDeleteKey';
    try {
      final response = await _apiClient.delete(url, useAuth: true);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("Error deleting job role type: $e");
      return false;
    }
  }
}
