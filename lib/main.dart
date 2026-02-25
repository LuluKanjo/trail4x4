import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
      ),
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
  
  // GPS & STABILITÉ
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  LatLng? _lastPos; 
  double _smoothLat = 0, _smoothLon = 0;
  final double _alpha = 0.18; 

  // INSTRUMENTS
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _loading = false, _isNavigating = false;
  int _mapMode = 0; // 0: OSM, 1: Sat, 2: Topo
  double _tripPartial = 0.0, _tripTotal = 0.0;
  double _pitch = 0.0, _roll = 0.0, _pitchOffset = 0.0, _rollOffset = 0.0;
  double _rawPitch = 0.0, _rawRoll = 0.0;
  String _weather = "--°C";
  
  // DONNÉES
  final List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  List<Map<String, dynamic>> _personalWaypoints = [];
  HiveCacheStore? _cacheStore;
  late RoutingService _routing;
  late POIService _poiService;
  late WeatherService _weatherService;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _initServices();
    _startSensors();
    _startTracking();
  }

  void _initServices() async {
    final dir = await getApplicationDocumentsDirectory();
    _cacheStore = HiveCacheStore(dir.path);
    _routing = RoutingService('');
    _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
    _weatherService = WeatherService();
    _loadStoredData();
  }

  void _startSensors() {
    accelerometerEventStream().listen((event) {
      if (!mounted) return;
      setState(() {
        _rawRoll = math.atan2(event.x, event.y) * -180 / math.pi;
        _rawPitch = math.atan2(event.z, event.y) * 180 / math.pi;
        _roll = _rawRoll - _rollOffset;
        _pitch = _rawPitch - _pitchOffset;
      });
    });
  }

  void _loadStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rollOffset = prefs.getDouble('roll_offset') ?? 0.0;
      _pitchOffset = prefs.getDouble('pitch_offset') ?? 0.0;
      _tripTotal = prefs.getDouble('trip_total') ?? 0.0;
      final savedWps = prefs.getStringList('personal_waypoints') ?? [];
      _personalWaypoints = savedWps.map((s) => json.decode(s) as Map<String, dynamic>).toList();
    });
    final w = await _weatherService.getCurrentWeather(_currentPos.latitude, _currentPos.longitude);
    if (mounted) setState(() => _weather = w);
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0))
    .listen((pos) {
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
          double d = const Distance().as(LengthUnit.Meter, _lastPos!, _currentPos);
          _tripPartial += d; _tripTotal += d;
        }
        _lastPos = _currentPos;
        if (_route.isNotEmpty) _remDist = const Distance().as(LengthUnit.Meter, _currentPos, _route.last);
      });
      if (_follow) _mapController.move(_currentPos, _isNavigating ? 17.5 : _mapController.camera.zoom);
    });
  }

  String _getMapUrl() {
    if (_mapMode == 1) return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    if (_mapMode == 2) return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  @override
  Widget build(BuildContext context) {
    // DÉTECTION DU TYPE D'ÉCRAN
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isTablet = constraints.maxWidth > 900;
          return Row(
            children: [
              if (isTablet) _buildControlPanel(), // Colonne instruments dédiée
              Expanded(
                child: Stack(
                  children: [
                    _buildMap(),
                    if (!isTablet) _buildMobileOverlays(),
                    if (_loading) const Center(child: CircularProgressIndicator(color: Colors.orange)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- COMPOSANTS UI ---

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPos,
        initialZoom: 15,
        onPositionChanged: (p, g) { if (g) setState(() => _follow = false); },
      ),
      children: [
        TileLayer(
          urlTemplate: _getMapUrl(),
          userAgentPackageName: 'com.trail4x4.pro',
          tileProvider: _cacheStore != null ? CachedTileProvider(store: _cacheStore!) : null,
        ),
        if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.orange, strokeWidth: 10, isPolylineId: true)]),
        MarkerLayer(markers: [
          Marker(
            point: _currentPos, width: 150, height: 150,
            child: Transform.rotate(
              angle: _head * math.pi / 180,
              child: const Icon(Icons.navigation, color: Colors.orange, size: 50),
            ),
          ),
        ]),
      ],
    );
  }

  // PANNEAU LATÉRAL TABLETTE
  Widget _buildControlPanel() {
    return Container(
      width: 300,
      color: Colors.black,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text("TRAIL 4X4 PRO", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
          const Divider(color: Colors.grey),
          const SizedBox(height: 20),
          _statBox(_speed.toStringAsFixed(0), "KM/H", Colors.orange, 50),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statBox(_alt.toStringAsFixed(0), "ALTITUDE", Colors.white, 20),
              _statBox(_getCap(_head), "CAP", Colors.cyan, 20),
            ],
          ),
          const Spacer(),
          _instrumentTile("INCLINOMÈTRE", Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _miniIncline("ROLL", _roll),
              _miniIncline("PITCH", _pitch),
            ],
          )),
          const SizedBox(height: 15),
          _instrumentTile("TRIPMASTER", Column(
            children: [
              _tripLine("PARTIEL", _tripPartial, true),
              _tripLine("TOTAL", _tripTotal, false),
            ],
          )),
          const SizedBox(height: 20),
          _btnLarge("CHANGER CARTE", Icons.layers, () => setState(() => _mapMode = (_mapMode + 1) % 3)),
          const SizedBox(height: 10),
          _btnLarge("CENTRER GPS", Icons.my_location, () => setState(() { _follow = true; _mapController.move(_currentPos, 15); })),
        ],
      ),
    );
  }

  Widget _buildMobileOverlays() {
    return Stack(
      children: [
        // Infos rapides haut
        Positioned(top: 40, left: 15, right: 15, child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _glassBtn(Icons.warning, Colors.red, () {}),
            Container(padding: const EdgeInsets.all(10), decoration: _glassDecoration(), child: Text(_weather, style: const TextStyle(fontWeight: FontWeight.bold))),
            _glassBtn(Icons.layers, Colors.indigo, () => setState(() => _mapMode = (_mapMode + 1) % 3)),
          ],
        )),
        // Tripmaster flottant
        Positioned(bottom: 110, left: 15, child: Container(padding: const EdgeInsets.all(10), decoration: _glassDecoration(), child: _tripLine("TRIP", _tripPartial, true))),
        // Dashboard bas
        Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 90, color: Colors.black.withOpacity(0.8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statBox(_speed.toStringAsFixed(0), "KM/H", Colors.orange, 30),
          _statBox(_alt.toStringAsFixed(0), "ALT", Colors.white, 20),
          _statBox(_getCap(_head), "CAP", Colors.cyan, 20),
        ]))),
      ],
    );
  }

  // --- WIDGETS DE STYLE ---

  Widget _statBox(String v, String l, Color c, double size) => Column(children: [Text(v, style: TextStyle(fontSize: size, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
  
  Widget _instrumentTile(String title, Widget child) => Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 10, color: Colors.orange)), const SizedBox(height: 10), child]));

  Widget _miniIncline(String l, double a) => Column(children: [Text(l, style: const TextStyle(fontSize: 9)), Text("${a.abs().toStringAsFixed(0)}°", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: a.abs() > 30 ? Colors.red : Colors.white))]);

  Widget _tripLine(String l, double v, bool reset) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text("${(v/1000).toStringAsFixed(2)} KM", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), if(reset) IconButton(icon: const Icon(Icons.refresh, size: 18, color: Colors.orange), onPressed: () => setState(() => _tripPartial = 0.0))]);

  Widget _btnLarge(String l, IconData i, VoidCallback o) => SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black), onPressed: o, icon: Icon(i), label: Text(l, style: const TextStyle(fontWeight: FontWeight.bold))));

  Widget _glassBtn(IconData i, Color c, VoidCallback o) => GestureDetector(onTap: o, child: Container(padding: const EdgeInsets.all(10), decoration: _glassDecoration(), child: Icon(i, color: c)));

  BoxDecoration _glassDecoration() => BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10));

  String _getCap(double h) { if (h < 22.5 || h >= 337.5) return "N"; if (h < 67.5) return "NE"; if (h < 112.5) return "E"; if (h < 157.5) return "SE"; if (h < 202.5) return "S"; if (h < 247.5) return "SO"; if (h < 292.5) return "O"; return "NO"; }
}
