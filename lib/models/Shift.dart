class Shift {
  final int shiftId;
  final int projectId;
  final String taskName;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;
  final String status;
  final List<int> assignedEmployeeIds;
  final int? jobId;
  final int? siteId;
  final String? latitude;
  final String? longitude;

  Shift({
    required this.shiftId,
    required this.projectId,
    required this.taskName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.status,
    required this.assignedEmployeeIds,
    this.jobId,
    this.siteId,
    this.latitude,
    this.longitude,
  });

  Shift copyWith({
    int? shiftId,
    int? projectId,
    String? taskName,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? location,
    String? status,
    List<int>? assignedEmployeeIds,
    int? siteId,
    String? latitude,
    String? longitude,
    int? jobId,
  }) {
    return Shift(
      shiftId: shiftId ?? this.shiftId,
      projectId: projectId ?? this.projectId,
      taskName: taskName ?? this.taskName,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      status: status ?? this.status,
      assignedEmployeeIds: assignedEmployeeIds ?? this.assignedEmployeeIds,
      siteId: siteId ?? this.siteId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      jobId: jobId ?? this.jobId,
    );
  }

  factory Shift.fromJson(Map<String, dynamic> json) {
    try {
      return Shift(
        shiftId: (json['ShiftId'] as num?)?.toInt() ?? 0,
        projectId: (json['ProjectId'] as num?)?.toInt() ?? 0,
        taskName: json['TaskName']?.toString() ?? '',
        date: DateTime.tryParse(json['Date'] ?? '') ?? DateTime.now(),
        startTime: json['StartTime']?.toString() ?? '',
        endTime: json['EndTime']?.toString() ?? '',
        location: json['Location']?.toString() ?? '',
        status: json['Status']?.toString() ?? '',
        jobId: (json['JobId'] as num?)?.toInt(),
        assignedEmployeeIds:
            (json['AssignedEmployeeIds'] as List<dynamic>? ?? [])
                .map((e) => (e as num?)?.toInt() ?? 0)
                .toList(),
        siteId: (json['SiteId'] as num?)?.toInt(),
        latitude: json['Latitude']?.toString(),
        longitude: json['Longitude']?.toString(),
      );
    } catch (e, stack) {
      print("🔥 ERROR in Shift.fromJson(): $e\n$stack");
      rethrow;
    }
  }

  // ✅ ADDED: This method was missing and causing the error
  Map<String, dynamic> toJson() {
    return {
      'ShiftId': shiftId,
      'ProjectId': projectId,
      'TaskName': taskName,
      'Date': date.toIso8601String(), // Convert DateTime to String
      'StartTime': startTime,
      'EndTime': endTime,
      'Location': location,
      'Status': status,
      'AssignedEmployeeIds': assignedEmployeeIds,
      'JobId': jobId,
      'SiteId': siteId,
      'Latitude': latitude,
      'Longitude': longitude,
    };
  }
}
