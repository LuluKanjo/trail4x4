import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'routing_service.dart';

void main() => runApp(const Trail4x4App());

class Trail4x4App extends StatelessWidget {
  const Trail4x4App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
  double _speed = 0, _altitude = 0, _heading = 0;
  bool _followMe = true;
  bool _isSatellite = false;
  
  List<LatLng> _route = [];
  double _remainingDist = 0;
  bool _loading = false;
  late RoutingService _routingService;

  @override
  void initState() {
    super.initState();
    _routingService = RoutingService('');
    _startTracking();
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high, 
      distanceFilter: 2
    )).listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _speed = pos.speed * 3.6;
        _altitude = pos.altitude;
        _heading = pos.heading; // Direction du véhicule

        if (_route.isNotEmpty) {
          _remainingDist = const Distance().as(LengthUnit.Meter, _currentPosition, _route.last);
        }
      });

      // MODE VRAI GPS : On centre ET on tourne la carte selon le cap
      if (_followMe) {
        _mapController.move(_currentPosition, _mapController.camera.zoom);
        // On ne fait tourner la carte que si on roule (évite les tremblements à l'arrêt)
        if (_speed > 2) {
          _mapController.rotate(-_heading); 
        }
      }
    });
  }

  Future<void> _calculateRoute(String destName) async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/search?q=$destName&format=json&limit=1'), 
      headers: {'User-Agent': 'Trail4x4-Lulu'});
      final data = json.decode(res.body);
      if (data.isNotEmpty) {
        final dest = LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
        final routeData = await _routingService.getOffRoadRoute(_currentPosition, dest);
        if (routeData != null) {
          setState(() { 
            _route = routeData.points; 
            _remainingDist = routeData.distance; 
            _followMe = true; 
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
            options: MapOptions(
              initialCenter: _currentPosition, 
              initialZoom: 15,
              onPositionChanged: (p, g) { if(g) setState(() => _followMe = false); }
            ),
            children: [
              TileLayer(
                userAgentPackageName: 'com.trail4x4.app',
                urlTemplate: _isSatellite 
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (_route.isNotEmpty) PolylineLayer(polylines: [
                Polyline(points: _route, color: Colors.cyanAccent, strokeWidth: 8, isPolylineGay: false)
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: _currentPosition, 
                  width: 60, height: 60, 
                  child: Transform.rotate(
                    angle: 0, // L'icône reste fixe car c'est la CARTE qui tourne
                    child: const Icon(Icons.navigation, color: Colors.orange, size: 50)
                  )
                ),
              ]),
            ],
          ),
          
          // BANNIÈRE NAVIGATION (Haut)
          if (_route.isNotEmpty) Positioned(top: 50, left: 10, right: 10, child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.cyanAccent, width: 2)
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.assistant_navigation, color: Colors.cyanAccent, size: 30),
                Text("${(_remainingDist/1000).toStringAsFixed(1)} KM", 
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text("RESTANT", style: TextStyle(fontSize: 12, color: Colors.cyanAccent)),
              ],
            ),
          )),

          // BOUTONS FLOTTANTS
          Positioned(bottom: 120, right: 15, child: Column(children: [
            FloatingActionButton(heroTag: "sat", mini: true, onPressed: () => setState(() => _isSatellite = !_isSatellite), 
              backgroundColor: Colors.black87, child: Icon(_isSatellite ? Icons.map : Icons.satellite_alt)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "gps", onPressed: () {
              setState(() => _followMe = true);
              _mapController.rotate(0); // Remet le Nord en haut si on veut
            }, backgroundColor: _followMe ? Colors.orange : Colors.grey[900], child: const Icon(Icons.gps_fixed)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "search", onPressed: () {
              final c = TextEditingController();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Destination"),
                content: TextField(controller: c, decoration: const InputDecoration(hintText: "Nom du lieu")),
                actions: [TextButton(onPressed: () { _calculateRoute(c.text); Navigator.pop(ctx); }, child: const Text("GO"))],
              ));
            }, backgroundColor: Colors.cyan[700], child: const Icon(Icons.search)),
          ])),

          // DASHBOARD (Bas)
          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            height: 100, color: Colors.black,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat("${_speed.toStringAsFixed(0)}", "KM/H", Colors.orange),
              _stat("${_altitude.toStringAsFixed(0)}", "ALT (M)", Colors.white),
              _stat(_getCompassDirection(_heading), "CAP", Colors.cyanAccent),
            ]),
          )),
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        ],
      ),
    );
  }

  String _getCompassDirection(double h) {
    if (h < 22.5 || h >= 337.5) return "N";
    if (h < 67.5) return "NE";
    if (h < 112.5) return "E";
    if (h < 157.5) return "SE";
    if (h < 202.5) return "S";
    if (h < 247.5) return "SO";
    if (h < 292.5) return "O";
    return "NO";
  }

  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(v, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}
