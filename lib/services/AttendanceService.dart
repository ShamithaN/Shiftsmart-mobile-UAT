import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // Required for MediaType
import 'package:mime/mime.dart'; // Required for lookupMimeType
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_client.dart'; // Import ApiClient

class AttendanceService {
  final ApiClient _apiClient = ApiClient(); // Initialize ApiClient

  String baseUrl = dotenv.env['ATTENDANCE_BASE_URL']!;
  String fetchAttendancePhoto = dotenv.env['FETCH_ATTENDANCE_PHOTO_KEY']!;
  String getShiftById = dotenv.env['SHIFT_BY_SHIFTID_KEY']!;
  String clockinKey = dotenv.env['CLOCKIN_KEY']!;
  String clockoutKey = dotenv.env['CLOCKOUT_KEY']!;
  String breakstart = dotenv.env['BREAK_START_KEY']!;
  String breakend = dotenv.env['BREAK_END_KEY']!;

  // --- GET CLOCK PHOTO URL ---
  Future<String?> fetchClockPhotoUrl(int attendanceId,
      {required isClockIn}) async {
    final endPoint = isClockIn ? 'view-clockin-photo' : 'view-clockout-photo';
    final url = '$baseUrl/attendance/$endPoint/$attendanceId';
    try {
      final response = await _apiClient.get(url, useAuth: true);

      final jsonData = jsonDecode(response.body);
      return jsonData['photoUrl'].toString();
    } catch (e) {
      debugPrint("Error fetching clock ${isClockIn ? "in" : "out"} photo: $e");
    }
    return null;
  }

  // --- FETCH ATTENDANCE PHOTOS ---
  Future<Map<String, String?>> fetchAttendancePhotos(
      int employeeId, int shiftId) async {
    final url =
        "$baseUrl/attendance/by-employee/$employeeId?code=$fetchAttendancePhoto";
    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final record = jsonData.firstWhere(
          (attendance) => attendance['ShiftId'] == shiftId,
          orElse: () => <String, dynamic>{},
        );
        if (record == null) return {};
        return {
          'clockIn': record['ClockInPhotoUrl'] as String?,
          'clockOut': record['ClockOutPhotoUrl'] as String?,
        };
      }
    } catch (e) {
      debugPrint("Error fetching attendance photos: $e");
    }
    return {};
  }

  // --- GET SHIFTS BY ID ---
  Future<dynamic> getShiftsByShiftId(int employeeId, {int? shiftId}) async {
    final url =
        '$baseUrl/attendance/by-employee/$employeeId?code=$getShiftById';
    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final List<dynamic> shifts = jsonDecode(response.body);
        if (shiftId != null) {
          final shift = shifts.firstWhere(
            (s) => s['ShiftId'] == shiftId,
            orElse: () => null,
          );
          return shift;
        }
        return shifts;
      } else {
        throw Exception("Failed to fetch shifts: HTTP ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Error fetching shifts for employee $employeeId: $e");
    }
  }

  // --- CLOCK IN (Multi-Photo & GPS) ---
  Future<Map<String, dynamic>> clockIn({
    required int employeeId,
    required int shiftId,
    required int siteId,
    required String scheduledStartTime,
    required List<File> photos, // List of photos
    required DateTime clockInTime,
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse('$baseUrl/attendance/clockin?code=$clockinKey');
    try {
      final request = http.MultipartRequest("POST", url);

      // Auth Header
      final token = await _apiClient.getAppToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add Photos
      for (var file in photos) {
        final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
        request.files.add(await http.MultipartFile.fromPath(
          'photo',
          file.path,
          contentType: MediaType.parse(mimeType),
        ));
      }

      // Add Fields
      request.fields['employeeId'] = employeeId.toString();
      request.fields['shiftId'] = shiftId.toString();
      request.fields['siteId'] = siteId.toString();
      request.fields['scheduledStartTime'] = scheduledStartTime.toString();
      request.fields['clockInTime'] = clockInTime.toIso8601String();
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      debugPrint('📤 Clock-in HTTP status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(responseBody);
        return {
          'success': true,
          'data': result,
          'attendanceId': result['AttendanceId'] ?? result['attendanceId'],
        };
      } else {
        throw Exception(
            "Clock in failed: HTTP ${response.statusCode} - $responseBody");
      }
    } catch (e) {
      debugPrint("Clock in service error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- CLOCK OUT (Multi-Photo & GPS) ---
  Future<Map<String, dynamic>> clockOut({
    required int attendanceId,
    required DateTime clockOutTime,
    required List<File> photos,
    required double latitude,
    required double longitude,
    Duration? timeout,
  }) async {
    final url = Uri.parse(
        '$baseUrl/attendance/clockout/$attendanceId?code=$clockoutKey');
    try {
      final request = http.MultipartRequest('PUT', url);

      // Auth Header
      final token = await _apiClient.getAppToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add Photos
      for (var file in photos) {
        final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
        request.files.add(await http.MultipartFile.fromPath(
          'photo',
          file.path,
          contentType: MediaType.parse(mimeType),
        ));
      }

      // Add Fields
      request.fields['attendanceId'] = attendanceId.toString();
      request.fields['clockOutTime'] = clockOutTime.toIso8601String();
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();

      final response = timeout != null
          ? await request.send().timeout(timeout)
          : await request.send();

      final responseBody = await response.stream.bytesToString();
      debugPrint('📤 Clock-out HTTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = responseBody.isNotEmpty ? jsonDecode(responseBody) : {};
        return {'success': true, 'data': result};
      } else {
        throw Exception(
            "Clock out failed: HTTP ${response.statusCode} - $responseBody");
      }
    } catch (e) {
      debugPrint("Clock out service error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- BREAK START (Updated for C# Backend) ---
  Future<bool?> breakStart(int attendanceId,
      {required DateTime startTime}) async {
    final url =
        '$baseUrl/attendance/break/start/$attendanceId?code=$breakstart';

    try {
      final response = await _apiClient.put(
        url,
        body: {
          // Send specific time to fix timezone issue
          'breakStartTime': startTime.toIso8601String(),
        },
        useAuth: true,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint(
            "❌ Break start failed: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      throw Exception("Error :$e");
    }
  }

  // --- END BREAK (Updated for C# Backend) ---
  Future<bool?> endBreak(int attendanceId, {required DateTime endTime}) async {
    final url = '$baseUrl/attendance/break/end/$attendanceId?code=$breakend';

    try {
      final response = await _apiClient.put(
        url,
        body: {
          // Send specific time to fix timezone issue
          'breakEndTime': endTime.toIso8601String(),
        },
        useAuth: true,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint(
            "❌ Break end failed: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      throw Exception("Error: $e");
    }
  }
}
