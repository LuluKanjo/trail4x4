import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'routing_service.dart';
import 'poi_service.dart';

void main() => runApp(const Trail4x4App());

class Trail4x4App extends StatelessWidget {
  const Trail4x4App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(), home: const MapScreen());
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _isSat = false, _loading = false;
  
  List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  final List<LatLng> _forbiddenPoints = [];
  
  late RoutingService _routing;
  late POIService _poiService;

  @override
  void initState() {
    super.initState();
    _routing = RoutingService('');
    _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
    _loadForbidden();
    _startTracking();
  }

  void _loadForbidden() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('forbidden_zones');
    if (saved != null) {
      setState(() {
        _forbiddenPoints.addAll(saved.map((s) {
          final parts = s.split(',');
          return LatLng(double.parse(parts[0]), double.parse(parts[1]));
        }));
      });
    }
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2))
    .listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPos = LatLng(pos.latitude, pos.longitude);
        _speed = pos.speed * 3.6;
        _alt = pos.altitude;
        _head = pos.heading;
        if (_route.isNotEmpty) _remDist = const Distance().as(LengthUnit.Meter, _currentPos, _route.last);
      });
      if (_follow) {
        _mapController.move(_currentPos, _mapController.camera.zoom);
        if (_speed > 3) _mapController.rotate(-_head);
      }
    });
  }

  Future<void> _updateRoute() async {
    if (_waypoints.isEmpty) return;
    setState(() => _loading = true);
    final data = await _routing.getOffRoadRoute([_currentPos, ..._waypoints], _forbiddenPoints);
    if (data != null) setState(() { _route = data.points; _remDist = data.distance; });
    setState(() => _loading = false);
  }

  void _recenter() {
    setState(() => _follow = true);
    _mapController.move(_currentPos, 15);
    _mapController.rotate(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPos, initialZoom: 15,
              onPositionChanged: (p, g) { if(g) setState(() => _follow = false); },
              onLongPress: (tp, ll) { setState(() => _waypoints.add(ll)); _updateRoute(); },
            ),
            children: [
              TileLayer(
                userAgentPackageName: 'com.trail4x4.app',
                urlTemplate: _isSat 
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.cyanAccent, strokeWidth: 8)]),
              MarkerLayer(markers: [
                ..._forbiddenPoints.map((p) => Marker(point: p, child: const Icon(Icons.block, color: Colors.red, size: 30))),
                ..._waypoints.map((p) => Marker(point: p, child: const Icon(Icons.location_on, color: Colors.cyanAccent, size: 30))),
                Marker(point: _currentPos, width: 60, height: 60, child: const Icon(Icons.navigation, color: Colors.orange, size: 50)),
              ]),
            ],
          ),
          Positioned(top: 40, left: 10, right: 10, child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _btn(Icons.block, Colors.red, () { setState(() => _forbiddenPoints.add(_currentPos)); _updateRoute(); }),
              if (_route.isNotEmpty) _navInfo(),
              _btn(Icons.delete_sweep, Colors.grey[800]!, () { setState(() { _route = []; _waypoints.clear(); }); }),
            ],
          )),
          Positioned(bottom: 120, right: 15, child: Column(children: [
            _btn(_isSat ? Icons.map : Icons.satellite_alt, Colors.black87, () => setState(() => _isSat = !_isSat)),
            const SizedBox(height: 10),
            _btn(Icons.my_location, _follow ? Colors.orange : Colors.grey[800]!, _recenter),
          ])),
          Positioned(bottom: 0, left: 0, right: 0, child: _dash()),
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        ],
      ),
    );
  }

  Widget _btn(IconData i, Color b, VoidCallback o) => FloatingActionButton(mini: true, backgroundColor: b, onPressed: o, child: Icon(i, color: Colors.white));
  Widget _navInfo() => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.cyanAccent)), child: Text("${(_remDist/1000).toStringAsFixed(1)} KM"));
  Widget _dash() => Container(height: 90, color: Colors.black, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
    _stat(_alt.toStringAsFixed(0), "ALT", Colors.white),
    _stat(_getDir(_head), "CAP", Colors.cyanAccent),
  ]));
  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
  String _getDir(double h) { if (h < 22.5 || h >= 337.5) return "N"; if (h < 67.5) return "NE"; if (h < 112.5) return "E"; if (h < 157.5) return "SE"; if (h < 202.5) return "S"; if (h < 247.5) return "SO"; if (h < 292.5) return "O"; return "NO"; }
}
