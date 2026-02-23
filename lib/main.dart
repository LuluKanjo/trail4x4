import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const Trail4x4App());
}

class Trail4x4App extends StatelessWidget {
  const Trail4x4App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trail 4x4',
      theme: ThemeData.dark(),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(46.603354, 1.888334);
  double _speed = 0;
  double _altitude = 0;
  double _distance = 0;
  LatLng? _lastPosition;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _speed = position.speed * 3.6;
        _altitude = position.altitude;
        if (_lastPosition != null) {
          final Distance calculator = Distance();
          _distance += calculator.as(
            LengthUnit.Kilometer,
            _lastPosition!,
            _currentPosition,
          );
        }
        _lastPosition = _currentPosition;
      });
      _mapController.move(_currentPosition, _mapController.camera.zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trail4x4.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.navigation,
                        color: Colors.orange, size: 40),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.brown[900]!.withOpacity(0.9),
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
              child: const Text(
                'Trail 4x4',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.brown[900]!.withOpacity(0.9),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Vitesse', '${_speed.toStringAsFixed(0)} km/h', Icons.speed),
                  _buildStat('Altitude', '${_altitude.toStringAsFixed(0)} m', Icons.terrain),
                  _buildStat('Distance', '${_distance.toStringAsFixed(2)} km', Icons.straighten),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton(
              onPressed: () {
                _mapController.move(_currentPosition, 15);
              },
              backgroundColor: Colors.brown[800],
              child: const Icon(Icons.gps_fixed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.orange, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}
