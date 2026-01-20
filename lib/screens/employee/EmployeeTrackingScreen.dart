import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shiftsmart/models/Site.dart';
import 'package:shiftsmart/services/LocationService.dart';
import 'package:shiftsmart/widgets/uppernavbar.dart';

class EmployeeTrackingScreen extends StatefulWidget {
  final Site currentSite;
  final int employeeId;

  const EmployeeTrackingScreen({
    super.key,
    required this.currentSite,
    required this.employeeId,
  });

  @override
  State<EmployeeTrackingScreen> createState() => _EmployeeTrackingScreenState();
}

class _EmployeeTrackingScreenState extends State<EmployeeTrackingScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final LocationService _locationService =
      RealLocationService(); // Use your service

  // Stream to listen to location updates
  StreamSubscription<Position>? _positionStream;

  // Markers & Circles
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  // State
  bool _isInside = false;
  CameraPosition? _initialPosition;

  @override
  void initState() {
    super.initState();
    _setupGeofence();
    _startTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // 1. Draw the Site Geofence (Circle)
  void _setupGeofence() {
    final double lat = double.tryParse(widget.currentSite.latitude ?? '0') ?? 0;
    final double lng =
        double.tryParse(widget.currentSite.longitude ?? '0') ?? 0;
    final double radius = (widget.currentSite.radius ?? 150).toDouble();

    setState(() {
      _initialPosition = CameraPosition(
        target: LatLng(lat, lng),
        zoom: 16,
      );

      _circles.add(
        Circle(
          circleId: const CircleId('site_geofence'),
          center: LatLng(lat, lng),
          radius: radius,
          fillColor: Colors.blue.withOpacity(0.2),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        ),
      );

      // Add marker for the Site Center
      _markers.add(
        Marker(
          markerId: const MarkerId('site_center'),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: widget.currentSite.siteName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });
  }

  // 2. Start Live Tracking
  void _startTracking() async {
    // Location Settings
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      _updateMyLocation(position);

      // Optional: Send to backend if not already handled by background service
      _locationService.sendLocation(position, widget.employeeId);
    });
  }

  // 3. Update UI Marker
  void _updateMyLocation(Position position) async {
    final double siteLat =
        double.tryParse(widget.currentSite.latitude ?? '0') ?? 0;
    final double siteLng =
        double.tryParse(widget.currentSite.longitude ?? '0') ?? 0;
    final double radius = (widget.currentSite.radius ?? 150).toDouble();

    // Calculate Distance
    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      siteLat,
      siteLng,
    );

    bool isInside = distance <= radius;

    setState(() {
      _isInside = isInside;

      // Update Employee Marker
      _markers.removeWhere((m) => m.markerId.value == 'me');
      _markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isInside ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: "Me",
            snippet: isInside ? "Inside Site" : "Outside Site",
          ),
        ),
      );
    });

    // Move Camera to follow user
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)));
  }

  @override
  Widget build(BuildContext context) {
    if (_initialPosition == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: const Uppernavbar(showBackButton: true),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _initialPosition!,
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true, // Show blue dot
            myLocationButtonEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
          ),

          // Status Card at the Bottom
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isInside
                    ? Colors.green.withOpacity(0.9)
                    : Colors.redAccent.withOpacity(0.9),
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10)
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    _isInside
                        ? Icons.verified_user
                        : Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isInside ? "You are On Site" : "You are Off Site",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Live Tracking Active",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
