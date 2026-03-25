import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shiftsmart/models/shift.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_client.dart';

class ShiftService {
  final ApiClient _apiClient = ApiClient();

  // Load Base URL and API Keys from .env
  final String baseUrl = dotenv.env['SHIFT_BASE_URL'] ?? "";

  // Keys for CRUD Operations
  final String addShiftKey = dotenv.env['ADD_SHIFT_KEY'] ?? "";
  final String updateShiftKey = dotenv.env['UPDATE_SHIFT_KEY'] ?? "";
  final String fetchShiftKey = dotenv.env['FETCH_SHIFT_KEY'] ?? "";
  final String fetchShiftByEmpKey = dotenv.env['FETCH_SHIFT_BY_EMP_KEY'] ?? "";
  final String deleteShiftKey =
      dotenv.env['DELETE_SHIFT_KEY'] ?? dotenv.env['UPDATE_SHIFT_KEY'] ?? "";

  // Keys for Employee Actions (Respond/Swap)
  final String respondShiftKey = dotenv.env['RESPOND_SHIFT_KEY'] ?? '';
  final String swapShiftKey = dotenv.env['SWAP_SHIFT_KEY'] ?? '';

  ShiftService() {
    if (baseUrl.isEmpty) debugPrint("❌ ShiftService: SHIFT_BASE_URL is missing");
  }

  // ===========================================================================
  // EMPLOYEE FUNCTIONS (View, Respond, Swap)
  // ===========================================================================

  // 1. Fetch Shifts assigned to a specific Employee (Returns Shift Objects)
  Future<List<Shift>> fetchShiftsByEmployeeId(int employeeId) async {
    final String url =
        '$baseUrl/shift/employee/$employeeId?code=$fetchShiftByEmpKey';

    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return jsonData.map((data) => Shift.fromJson(data)).toList();
      } else {
        debugPrint(
            "Failed to load employee shifts. Status: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("Exception in fetchShiftsByEmployeeId: $e");
      return [];
    }
  }

  // 2. Fetch Shifts assigned to a specific Employee (Returns Raw JSON)
  // Essential for views needing custom fields like 'MyStatus' or 'MyRejectionReason'
  // that may not exist on the standard Shift model.
  Future<List<Map<String, dynamic>>> fetchShiftsByEmployeeIdRaw(
      int employeeId) async {
    final String url =
        '$baseUrl/shift/employee/$employeeId?code=$fetchShiftByEmpKey';
    debugPrint("🔍 ShiftService: Fetching shifts for employee $employeeId from $url");

    try {
      final response = await _apiClient.get(url, useAuth: true);
      debugPrint("📡 ShiftService Status (EmpId $employeeId): ${response.statusCode}");
      debugPrint("📄 ShiftService Body snippet: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}");

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        debugPrint("✅ ShiftService: Found ${jsonData.length} shifts for employee.");
        return jsonData.cast<Map<String, dynamic>>();
      } else {
        debugPrint("❌ ShiftService: Failed to fetch shifts for employee. Status: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("❌ ShiftService: Exception in fetchShiftsByEmployeeIdRaw: $e");
      return [];
    }
  }

  // 3. Respond to a Shift Assignment (Accept or Decline)
  Future<bool> respondToShift(int shiftId, String action,
      {String? reason}) async {
    final String url = '$baseUrl/shift/respond?code=$respondShiftKey';

    final body = {
      "ShiftId": shiftId,
      "Action": action, // "Accept" or "Decline"
      "Reason": reason // Required if action is "Decline"
    };

    try {
      final response = await _apiClient.post(
        url,
        body: body,
        useAuth: true,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint("Respond failed: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("Exception in respondToShift: $e");
      return false;
    }
  }

  // 4. Request a Shift Swap
  Future<bool> requestSwap(int shiftId) async {
    // Backend expects a PATCH request for swap operations
    final String url = '$baseUrl/shift/swap/$shiftId?code=$swapShiftKey';

    try {
      final response = await _apiClient.patch(
        url,
        body: {}, // Body is empty as ID is in URL
        useAuth: true,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint("Swap request failed: ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("Exception in requestSwap: $e");
      return false;
    }
  }

  // 5. Helper: Fetch and Filter Shifts for a specific Job & Employee
  // Useful for viewing history or upcoming shifts for a single job card.
  Future<List<Map<String, dynamic>>> fetchShiftsForJobAndEmployee({
    required int employeeId,
    required int jobId,
  }) async {
    try {
      // Get all shifts for the employee (Raw to preserve status)
      final allShifts = await fetchShiftsByEmployeeIdRaw(employeeId);

      // Filter by JobId
      final jobShifts = allShifts.where((shift) {
        return shift['JobId'].toString() == jobId.toString();
      }).toList();

      // Sort Chronologically (Date -> Start Time)
      jobShifts.sort((a, b) {
        final dateA = DateTime.parse(a['Date']);
        final dateB = DateTime.parse(b['Date']);
        if (dateA != dateB) return dateA.compareTo(dateB);
        return a['StartTime'].compareTo(b['StartTime']);
      });

      return jobShifts;
    } catch (e) {
      debugPrint("Exception in fetchShiftsForJobAndEmployee: $e");
      return [];
    }
  }

  // ===========================================================================
  //  MANAGER / ADMIN FUNCTIONS (Create, Update, View All)
  // ===========================================================================

  // 6. Fetch All Shifts (Master List for Managers)
  Future<List<Shift>> fetchAllShifts() async {
    final url = '$baseUrl/shift/getall?code=$fetchShiftKey';

    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is List) {
          debugPrint("✅ Fetched ${jsonData.length} shifts successfully.");
          return jsonData.map<Shift>((data) => Shift.fromJson(data)).toList();
        } else {
          debugPrint("⚠️ Unexpected JSON format for fetchAllShifts: $jsonData");
          return [];
        }
      } else {
        debugPrint(
            "❌ Failed to fetch all shifts. Status: ${response.statusCode}, Body: ${response.body}");
        return [];
      }
    } catch (e) {
      debugPrint("❌ Exception in fetchAllShifts: $e");
      return [];
    }
  }

  // 7. Fetch All Raw Shifts (Legacy/Dashboard use)
  Future<List<Map<String, dynamic>>> fetchAllRawShifts() async {
    final url = '$baseUrl/shift/getall?code=$fetchShiftKey';

    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is List) {
          return jsonData.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint("Exception in fetchAllRawShifts: $e");
    }
    return [];
  }

  // 8. Create New Shift
  Future<bool> addShift(Map<String, dynamic> shiftData) async {
    final String url = '$baseUrl/shift/create?code=$addShiftKey';

    try {
      final response = await _apiClient.post(
        url,
        body: shiftData,
        useAuth: true,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        debugPrint('Failed to add shift: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Exception in addShift: $e');
      return false;
    }
  }

  // 9. Update Existing Shift
  Future<bool> updateShift(int id, Map<String, dynamic> shiftData) async {
    final updateUrl = '$baseUrl/shift/update/$id?code=$updateShiftKey';

    // Ensure ID is included in body for consistency
    shiftData['ShiftId'] = id;

    try {
      final response = await _apiClient.put(
        updateUrl,
        body: shiftData,
        useAuth: true,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        debugPrint('Failed to update shift: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Exception in updateShift: $e');
      return false;
    }
  }

  // ===========================================================================
  //  SHIFT REPORTS (Manager Portal)
  // ===========================================================================

  /// Fetch shift report for a specific shift (Manager's view)
  /// This endpoint aggregates attendance and shift data for reporting purposes
  Future<Map<String, dynamic>?> fetchShiftReport(int shiftId) async {
    final String url = '$baseUrl/shift/$shiftId/report?code=$fetchShiftKey';

    try {
      final response = await _apiClient.get(url, useAuth: true);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        debugPrint('✅ Shift report fetched successfully for Shift ID: $shiftId');
        return jsonData;
      } else {
        debugPrint(
            'Failed to fetch shift report. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception in fetchShiftReport: $e');
      return null;
    }
  }

  // 11. Delete Shift
  Future<bool> deleteShift(int id) async {
    final deleteUrl = '$baseUrl/shift/delete/$id?code=$deleteShiftKey';

    try {
      debugPrint('🗑️ Deleting shift $id → $deleteUrl');
      final response = await _apiClient.delete(deleteUrl, useAuth: true);
      debugPrint('🗑️ Delete response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        debugPrint('Failed to delete shift (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Exception in deleteShift: $e');
      return false;
    }
  }
}
