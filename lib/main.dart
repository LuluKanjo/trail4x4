import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';

import 'routing_service.dart';
import 'poi_service.dart';
import 'weather_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Trail4x4App());
}

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
  
  // GPS & LISSAGE
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  LatLng? _lastPos; 
  double _smoothLat = 0, _smoothLon = 0;
  final double _alpha = 0.18; 

  // ETATS
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _loading = false, _isNavigating = false;
  
  // MODES DE CARTE (L'Overlander en a 2, on en a 3 !)
  int _mapMode = 0; // 0: Standard, 1: Satellite, 2: Topographie
  bool _isNightMode = false;

  // TRIPMASTERS
  double _tripPartial = 0.0;
  double _tripTotal = 0.0;

  // INCLINOMETRE
  double _rawPitch = 0.0, _rawRoll = 0.0, _pitchOffset = 0.0, _rollOffset = 0.0, _pitch = 0.0, _roll = 0.0;
  String _weather = "--°C";
  
  // DONNEES
  final List<LatLng> _route = [];
  final List<LatLng> _waypoints = []; 
  final List<LatLng> _trace = [];
  final List<LatLng> _forbiddenZones = [];
  final List<LatLng> _importedTrace = []; 
  List<Map<String, dynamic>> _personalWaypoints = [];
  final List<POI> _pois = [];
  
  HiveCacheStore? _cacheStore;
  late RoutingService _routing;
  late POIService _poiService;
  late WeatherService _weatherService;
  List<String> _sosContacts = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _initCache(); 
    _routing = RoutingService('');
    _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
    _weatherService = WeatherService();

    accelerometerEventStream().listen((event) {
      if (!mounted) return;
      setState(() {
        _rawRoll = math.atan2(event.x, event.y) * -180 / math.pi;
        _rawPitch = math.atan2(event.z, event.y) * 180 / math.pi;
        _roll = _rawRoll - _rollOffset;
        _pitch = _rawPitch - _pitchOffset;
      });
    });

    _loadData();
    _startTracking();
  }

  Future<void> _initCache() async {
    final dir = await getApplicationDocumentsDirectory();
    if (mounted) setState(() => _cacheStore = HiveCacheStore(dir.path));
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rollOffset = prefs.getDouble('roll_offset') ?? 0.0;
      _pitchOffset = prefs.getDouble('pitch_offset') ?? 0.0;
      _sosContacts = prefs.getStringList('sos_contacts') ?? [];
      final savedWps = prefs.getStringList('personal_waypoints') ?? [];
      _personalWaypoints = savedWps.map((s) => json.decode(s) as Map<String, dynamic>).toList();
      _tripTotal = prefs.getDouble('trip_total') ?? 0.0;
    });
    final w = await _weatherService.getCurrentWeather(_currentPos.latitude, _currentPos.longitude);
    if (mounted) setState(() => _weather = w);
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    const settings = LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);

    Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (!mounted) return;
      if (_smoothLat == 0) { _smoothLat = pos.latitude; _smoothLon = pos.longitude; }
      else {
        _smoothLat = (_alpha * pos.latitude) + ((1 - _alpha) * _smoothLat);
        _smoothLon = (_alpha * pos.longitude) + ((1 - _alpha) * _smoothLon);
      }
      setState(() {
        _currentPos = LatLng(_smoothLat, _smoothLon);
        _speed = pos.speed * 3.6;
        _alt = pos.altitude;
        _head = pos.heading;
        if (_lastPos != null) {
          double dist = const Distance().as(LengthUnit.Meter, _lastPos!, _currentPos);
          _tripPartial += dist;
          _tripTotal += dist;
        }
        _lastPos = _currentPos;
        if (_route.isNotEmpty) _remDist = const Distance().as(LengthUnit.Meter, _currentPos, _route.last);
      });
      if (_follow) {
        _mapController.move(_currentPos, _isNavigating ? 17.5 : _mapController.camera.zoom);
        if (_isNavigating && _speed > 1.0) _mapController.rotate(360 - _head);
      }
    });
  }

  String _getMapUrl() {
    if (_mapMode == 1) return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    if (_mapMode == 2) return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    return _isNightMode ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png' : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  void _calibrate() async {
    setState(() { _rollOffset = _rawRoll; _pitchOffset = _rawPitch; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('roll_offset', _rollOffset);
    await prefs.setDouble('pitch_offset', _pitchOffset);
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
            ),
            children: [
              TileLayer(
                urlTemplate: _getMapUrl(),
                userAgentPackageName: 'com.trail4x4.app',
                tileProvider: _cacheStore != null ? CachedTileProvider(store: _cacheStore!) : null,
              ),
              if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.cyanAccent, strokeWidth: 8)]),
              MarkerLayer(markers: [
                ..._personalWaypoints.map((wp) => Marker(point: LatLng(wp['lat'], wp['lon']), child: const Icon(Icons.star, color: Colors.amber, size: 30))),
                Marker(
                  point: _currentPos, width: 120, height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // COMPAS VISUEL "OVERLANDER"
                      Transform.rotate(angle: -_head * math.pi / 180, child: Opacity(opacity: 0.6, child: Image.network('https://cdn-icons-png.flaticon.com/512/1160/1160100.png', width: 100))),
                      Transform.rotate(angle: _head * math.pi / 180, child: const Icon(Icons.navigation, color: Colors.orange, size: 40)),
                    ],
                  ),
                ),
              ]),
            ],
          ),
          
          // HUD HAUT : NAVIGATION
          Positioned(top: 40, left: 10, right: 10, child: _isNavigating ? _buildNavHud() : _buildTopHud()),

          // BARRE LATERALE DROITE : INSTRUMENTS
          Positioned(top: 100, right: 10, child: Column(children: [
            _inclineBox("ROLL", _roll, Icons.screen_rotation),
            const SizedBox(height: 8),
            _inclineBox("PITCH", _pitch, Icons.swap_vert),
            const SizedBox(height: 8),
            _btn(Icons.exposure_zero, Colors.blueGrey, _calibrate),
            const SizedBox(height: 15),
            _btn(_mapMode == 2 ? Icons.terrain : (_mapMode == 1 ? Icons.satellite : Icons.map), Colors.indigo, () => setState(() => _mapMode = (_mapMode + 1) % 3)),
            const SizedBox(height: 8),
            _btn(_isNightMode ? Icons.light_mode : Icons.dark_mode, Colors.black87, () => setState(() => _isNightMode = !_isNightMode)),
          ])),

          // TRIPMASTER DOUBLE (EN BAS A GAUCHE)
          Positioned(bottom: 100, left: 10, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _tripBox("PARTIEL", _tripPartial, () => setState(() => _tripPartial = 0.0), Colors.cyanAccent),
            const SizedBox(height: 5),
            _tripBox("TOTAL", _tripTotal, () {}, Colors.white),
          ])),

          // DASHBOARD INFÉRIEUR
          Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 90, color: Colors.black, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
            _stat(_alt.toStringAsFixed(0), "ALT", Colors.white),
            _stat(_getDir(_head), "CAP", Colors.cyanAccent),
          ]))),
        ],
      ),
    );
  }

  Widget _buildTopHud() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    _btn(Icons.warning, Colors.red, () {}),
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15)), child: Text(_weather, style: const TextStyle(fontWeight: FontWeight.bold))),
    _btn(Icons.my_location, _follow ? Colors.orange : Colors.white, () => setState(() { _follow = true; _mapController.move(_currentPos, 15); })),
  ]);

  Widget _buildNavHud() => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Icon(Icons.navigation, color: Colors.orange), Text("${(_remDist/1000).toStringAsFixed(1)} KM RESTANTS", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), IconButton(icon: const Icon(Icons.stop_circle, color: Colors.red), onPressed: () => setState(() => _isNavigating = false))]));

  Widget _tripBox(String l, double v, VoidCallback r, Color c) => GestureDetector(onLongPress: r, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.5))), child: Row(children: [Text("$l: ", style: const TextStyle(fontSize: 10, color: Colors.grey)), Text("${(v/1000).toStringAsFixed(2)} KM", style: TextStyle(fontWeight: FontWeight.bold, color: c))])));
  Widget _inclineBox(String l, double a, IconData i) => Container(width: 60, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: a.abs() > 30 ? Colors.red : Colors.orange)), child: Column(children: [Transform.rotate(angle: a * math.pi / 180, child: Icon(i, size: 20)), Text("${a.abs().toStringAsFixed(0)}°", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]));
  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
  Widget _btn(IconData i, Color b, VoidCallback o) => FloatingActionButton(heroTag: null, mini: true, backgroundColor: b, onPressed: o, child: Icon(i, color: Colors.white));
  String _getDir(double h) { if (h < 22.5 || h >= 337.5) return "N"; if (h < 67.5) return "NE"; if (h < 112.5) return "E"; if (h < 157.5) return "SE"; if (h < 202.5) return "S"; if (h < 247.5) return "SO"; if (h < 292.5) return "O"; return "NO"; }
}
