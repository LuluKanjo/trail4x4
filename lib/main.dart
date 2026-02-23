import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'weather_service.dart';
import 'poi_service.dart';
import 'routing_service.dart';

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
      home: const MapScreen(
        weatherKey: '40ec667fbf278cf67533b2c70d799dd1',
        tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso',
        graphhopperKey: '', 
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  final String weatherKey;
  final String tomtomKey;
  final String graphhopperKey;
  const MapScreen({super.key, required this.weatherKey, required this.tomtomKey, required this.graphhopperKey});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(46.603354, 1.888334);
  double _speed = 0;
  double _altitude = 0;
  double _totalTripDistance = 0;
  LatLng? _lastPosition;
  bool _followMe = true;
  
  List<String> _sosContacts = [];
  bool _isRecording = false;
  final List<LatLng> _trace = [];
  
  late WeatherService _weatherService;
  late POIService _poiService;
  late RoutingService _routingService;
  
  final List<POI> _pois = [];
  List<LatLng> _route = [];
  double _remainingDist = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _weatherService = WeatherService(widget.weatherKey);
    _poiService = POIService(tomtomKey: widget.tomtomKey);
    _routingService = RoutingService('');
    _startTracking();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _sosContacts = prefs.getStringList('sos_contacts') ?? []);
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3))
    .listen((Position pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _speed = pos.speed * 3.6;
        _altitude = pos.altitude;
        if (_lastPosition != null) {
          _totalTripDistance += const Distance().as(LengthUnit.Kilometer, _lastPosition!, _currentPosition);
        }
        _lastPosition = _currentPosition;
        if (_isRecording) _trace.add(_currentPosition);
        
        if (_route.isNotEmpty) {
          _remainingDist = const Distance().as(LengthUnit.Meter, _currentPosition, _route.last);
        }
      });
      if (_followMe) _mapController.move(_currentPosition, _mapController.camera.zoom);
    });
  }

  Future<void> _calculateRoute(String destName) async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/search?q=$destName&format=json&limit=1'));
      final data = json.decode(res.body);
      if (data.isNotEmpty) {
        final dest = LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
        final routeData = await _routingService.getOffRoadRoute(_currentPosition, dest);
        if (routeData != null) {
          setState(() {
            _route = routeData.points;
            _remainingDist = routeData.distance;
          });
        }
      }
    } catch (e) { debugPrint('$e'); }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _currentPosition, initialZoom: 14, onPositionChanged: (pos, hasGesture) {
              if (hasGesture) setState(() => _followMe = false);
            }),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.blueAccent, strokeWidth: 6)]),
              if (_trace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _trace, color: Colors.orange, strokeWidth: 4)]),
              MarkerLayer(markers: [
                Marker(point: _currentPosition, width: 40, height: 40, child: const Icon(Icons.navigation, color: Colors.orange, size: 40)),
              ]),
            ],
          ),
          Positioned(top: 40, left: 15, right: 15, child: Column(children: [
            if (_route.isNotEmpty) Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue[900]!.withOpacity(0.8), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.flag, color: Colors.white),
                const SizedBox(width: 10),
                Text("Destination : ${(_remainingDist/1000).toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
          ])),
          Positioned(bottom: 120, right: 15, child: Column(children: [
            FloatingActionButton(heroTag: "gps", onPressed: () => setState(() => _followMe = true), backgroundColor: _followMe ? Colors.orange : Colors.grey[800], child: const Icon(Icons.gps_fixed)),
            const SizedBox(height: 10),
            FloatingActionButton(heroTag: "route", onPressed: () {
              final controller = TextEditingController();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Destination Off-Road"),
                content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Village, Lieu-dit...")),
                actions: [TextButton(onPressed: () => _calculateRoute(controller.text).then((_) => Navigator.pop(ctx)), child: const Text("Tracer"))],
              ));
            }, child: const Icon(Icons.map)),
          ])),
          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat("Vitesse", "${_speed.toStringAsFixed(0)} km/h"),
              _stat("Altitude", "${_altitude.toStringAsFixed(0)} m"),
              _stat("Trip", "${_totalTripDistance.toStringAsFixed(1)} km"),
            ]),
          )),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
  Widget _stat(String label, String val) => Column(children: [Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)), Text(label, style: const TextStyle(color: Colors.grey))]);
}
