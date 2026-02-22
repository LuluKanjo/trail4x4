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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
      _mapController.move(_currentPosition, 13);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trail 4x4',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.brown[800],
        centerTitle: true,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13,
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
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.orange,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getCurrentLocation,
        backgroundColor: Colors.brown[800],
        child: const Icon(Icons.gps_fixed),
      ),
    );
  }
}