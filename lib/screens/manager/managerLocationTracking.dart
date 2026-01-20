import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shiftsmart/utils/fullscreen_helper.dart';
import 'package:shiftsmart/widgets/background.dart';
import 'package:shiftsmart/widgets/search.dart';
import 'package:shiftsmart/widgets/sidenav.dart';
import 'package:shiftsmart/widgets/uppernavbar.dart';
import 'package:flutter/foundation.dart';
import 'package:shiftsmart/models/Site.dart';
import 'package:shiftsmart/models/SiteEmployee.dart';
import 'package:shiftsmart/services/SiteService.dart';

class ManagerLocationTracking extends StatefulWidget {
  final int siteId;

  const ManagerLocationTracking({super.key, required this.siteId});

  @override
  State<ManagerLocationTracking> createState() =>
      _ManagerLocationTrackingState();
}

class _ManagerLocationTrackingState extends State<ManagerLocationTracking> {
  Site? currentSite;
  List<SiteEmployee> employees = [];
  bool isLoading = true;
  final Completer<GoogleMapController> _mapController = Completer();
  Set<Marker> _markers = {};
  LatLng? _mapCenter;
  double _mapZoom = 15.0; // Increased zoom slightly
  List<SiteEmployee> filteredEmployees = [];
  final SiteService _siteService = SiteService();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    enableFullScreen();
    _loadSiteData();

    // Auto-refresh locations every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _refreshEmployeeLocations();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Initial load (gets site details + employees)
  Future<void> _loadSiteData() async {
    try {
      final site = await _fetchSiteDetails(widget.siteId);

      setState(() {
        currentSite = site;
        // Set map center to site location
        _mapCenter = LatLng(
          double.tryParse(site.latitude ?? '') ?? 0.0,
          double.tryParse(site.longitude ?? '') ?? 0.0,
        );
      });

      await _refreshEmployeeLocations();
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  // Separated function to just refresh employees (for the Timer)
  Future<void> _refreshEmployeeLocations() async {
    if (currentSite == null) return;

    try {
      final siteEmployees =
          await _siteService.fetchEmployeesInSite(widget.siteId, currentSite!);

      if (mounted) {
        setState(() {
          employees = siteEmployees;
          // Re-apply current search query if needed, currently just resetting
          filteredEmployees = List.from(siteEmployees);
          isLoading = false;
          _createMarkers(currentSite!, siteEmployees);
        });
      }
    } catch (e) {
      debugPrint("Error refreshing locations: $e");
    }
  }

  void _createMarkers(Site site, List<SiteEmployee> employees) {
    final markers = <Marker>{};
    final lat = double.tryParse(site.latitude ?? '') ?? 0.0;
    final lng = double.tryParse(site.longitude ?? '') ?? 0.0;

    // 1. Add Site Marker (Blue)
    markers.add(Marker(
      markerId: MarkerId('site_${site.siteId}'),
      position: LatLng(lat, lng),
      infoWindow:
          InfoWindow(title: site.siteName, snippet: "Radius: ${site.radius}m"),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ));

    // 2. Add Employee Markers
    int employeeCount = 0;
    for (final employee in employees) {
      if (employee.clockInLat != null && employee.clockInLng != null) {
        employeeCount++;

        // Color coding: Green = Inside, Red = Outside
        final double markerHue = employee.isInside
            ? BitmapDescriptor.hueGreen
            : BitmapDescriptor.hueRed;

        markers.add(Marker(
          markerId: MarkerId('employee_${employee.employeeId}'),
          position: LatLng(employee.clockInLat!, employee.clockInLng!),
          infoWindow: InfoWindow(
            title: employee.name,
            snippet: employee.isInside
                ? 'Inside Fence'
                : 'Outside (${(employee.distance! * 1000).toStringAsFixed(0)}m away)',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(markerHue),
        ));
      }
    }

    setState(() {
      _markers = markers;
    });
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController.complete(controller);
    if (kIsWeb || !mounted) return;
    try {
      final darkMapStyle = await DefaultAssetBundle.of(context)
          .loadString('assets/map_styles/dark.json');
      controller.setMapStyle(darkMapStyle);
    } catch (e) {
      debugPrint('Error loading map style: $e');
    }
  }

  Future<Site> _fetchSiteDetails(int siteId) async {
    final site = await _siteService.fetchSiteById(siteId);
    if (site != null) {
      return site;
    } else {
      throw Exception('Site not found');
    }
  }

  void onQueryChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredEmployees = List.from(employees);
      } else {
        filteredEmployees = employees
            .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const Sidenav(),
      appBar: const Uppernavbar(),
      backgroundColor: const Color(0xFF1C2230),
      body: Stack(
        children: [
          const Positioned.fill(child: Background()),
          SafeArea(
            child: Column(
              children: [
                Search(onQueryChanged: onQueryChanged),
                Expanded(
                  flex: 2,
                  child: _buildMapSection(),
                ),
                Expanded(
                  flex: 1,
                  child: _buildEmployeeListSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mapCenter == null) {
      return const Center(
          child: Text("No location data available",
              style: TextStyle(color: Colors.white)));
    }

    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: _mapCenter!,
        zoom: _mapZoom,
      ),
      markers: _markers,
      mapType: MapType.normal,
      zoomControlsEnabled: false,
      myLocationEnabled: false,
      circles: currentSite != null
          ? {
              Circle(
                circleId: CircleId('geofence_${currentSite!.siteId}'),
                center: LatLng(
                  double.tryParse(currentSite!.latitude ?? '') ?? 0.0,
                  double.tryParse(currentSite!.longitude ?? '') ?? 0.0,
                ),
                radius: currentSite!.radius ?? 0.0,
                strokeWidth: 2,
                strokeColor: Colors.blue.withOpacity(0.7),
                fillColor: Colors.blue.withOpacity(0.2),
              )
            }
          : {},
    );
  }

  Widget _buildEmployeeListSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Live Tracking',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text('${employees.length} Active',
                    style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _buildEmployeeList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeList() {
    // FIX: Show ALL clocked-in employees, not just the ones inside!
    // Sort so outside employees (problematic ones) appear at the top
    filteredEmployees.sort((a, b) {
      if (a.isInside == b.isInside) return 0;
      return a.isInside ? 1 : -1; // Put Outside first
    });

    if (filteredEmployees.isEmpty) {
      return const Center(
        child: Text("No employees currently active",
            style: TextStyle(color: Colors.black)),
      );
    }

    return ListView.builder(
      itemCount: filteredEmployees.length,
      itemBuilder: (context, index) {
        final employee = filteredEmployees[index];
        return _buildEmployeeCard(employee);
      },
    );
  }

  Widget _buildEmployeeCard(SiteEmployee employee) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Use a lighter dark color or white card since container is white-ish
        color: const Color(0xFF2A3243),
        borderRadius: BorderRadius.circular(10),
        border: employee.isInside
            ? null
            : Border.all(
                color: Colors.redAccent, width: 1), // Red border for outside
      ),
      child: Row(
        children: [
          // Profile Pic or Avatar
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade700,
              image: employee.profilePicture != null
                  ? DecorationImage(
                      image: NetworkImage(employee.profilePicture!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: employee.profilePicture == null
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: employee.isInside ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      employee.isInside ? "Inside Fence" : "Outside Fence",
                      style: TextStyle(
                          color: employee.isInside
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Distance
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (employee.distance != null)
                Text(
                  '${(employee.distance! * 1000).toStringAsFixed(0)}m',
                  style: TextStyle(
                      color:
                          employee.isInside ? Colors.white70 : Colors.redAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              if (employee.clockInTime != null)
                Text(
                  _formatClockInTime(employee.clockInTime!),
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatClockInTime(String clockInTime) {
    try {
      final dateTime = DateTime.parse(clockInTime);
      return DateFormat('HH:mm').format(dateTime);
    } catch (e) {
      return clockInTime;
    }
  }
}
