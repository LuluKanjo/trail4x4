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
  
  // GPS & LISSAGE (Filtre Passe-Bas : $Pos_{lisse} = \alpha \cdot Pos_{brute} + (1 - \alpha) \cdot Pos_{prec}$)
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  LatLng? _lastPos; 
  double _smoothLat = 0, _smoothLon = 0;
  final double _alpha = 0.18; 

  // INSTRUMENTS
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _loading = false, _isNavigating = false;
  bool _isExpeditionMode = false; // FALSE = Route (Autoroute), TRUE = Piste (Plus court)
  int _mapMode = 0; 
  double _tripPartial = 0.0, _tripTotal = 0.0;
  double _pitch = 0.0, _roll = 0.0, _pitchOffset = 0.0, _rollOffset = 0.0;
  String _weather = "--°C";
  
  final List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  HiveCacheStore? _cacheStore;
  late RoutingService _routing;
  late WeatherService _weatherService;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _initServices();
    _startTracking();
  }

  void _initServices() async {
    final dir = await getApplicationDocumentsDirectory();
    _cacheStore = HiveCacheStore(dir.path);
    _routing = RoutingService('');
    _weatherService = WeatherService();
    _loadData();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rollOffset = prefs.getDouble('roll_offset') ?? 0.0;
      _pitchOffset = prefs.getDouble('pitch_offset') ?? 0.0;
      _tripTotal = prefs.getDouble('trip_total') ?? 0.0;
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
      });
      if (_follow) _mapController.move(_currentPos, _mapController.camera.zoom);
    });
  }

  Future<void> _updateRoute() async {
    if (_waypoints.isEmpty) return;
    setState(() => _loading = true);
    // On passe le profil à 'car' pour les liaisons (autoroutes) ou 'driving' pour le plus court
    final profile = _isExpeditionMode ? 'driving' : 'car';
    final data = await _routing.getOffRoadRoute([_currentPos, ..._waypoints], [], profile: profile);
    if (data != null) {
      setState(() { _route.clear(); _route.addAll(data.points); _remDist = data.distance; });
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isTablet = constraints.maxWidth > 900;
          return Row(
            children: [
              if (isTablet) _buildControlPanel(),
              Expanded(child: Stack(children: [
                _buildMap(),
                _buildOverlays(isTablet),
                if (_loading) const Center(child: CircularProgressIndicator(color: Colors.orange)),
              ])),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPos, initialZoom: 15,
        onPositionChanged: (p, g) { if (g) setState(() => _follow = false); },
        onLongPress: (tp, ll) { setState(() => _waypoints.add(ll)); _updateRoute(); },
      ),
      children: [
        TileLayer(
          urlTemplate: _mapMode == 1 ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}' : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trail4x4.expedition.pro',
          tileProvider: _cacheStore != null ? CachedTileProvider(store: _cacheStore!) : null,
        ),
        if (_route.isNotEmpty) PolylineLayer(polylines: [
          Polyline(points: List<LatLng>.from(_route), color: Colors.orange, strokeWidth: 8)
        ]),
        MarkerLayer(markers: [
          Marker(point: _currentPos, width: 80, height: 80, child: Transform.rotate(angle: _head * math.pi / 180, child: const Icon(Icons.navigation, color: Colors.orange, size: 45))),
        ]),
      ],
    );
  }

  Widget _buildOverlays(bool isTablet) {
    return Stack(children: [
      Positioned(top: 40, left: 15, right: 15, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _btn(Icons.warning, Colors.red, () {}),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _isExpeditionMode ? Colors.green : Colors.blue),
          onPressed: () { setState(() => _isExpeditionMode = !_isExpeditionMode); _updateRoute(); },
          icon: Icon(_isExpeditionMode ? Icons.terrain : Icons.directions_car),
          label: Text(_isExpeditionMode ? "MODE PISTE" : "MODE ROUTE"),
        ),
        _btn(Icons.layers, Colors.indigo, () => setState(() => _mapMode = (_mapMode + 1) % 2)),
      ])),
      if (!isTablet) Positioned(bottom: 0, left: 0, right: 0, child: _buildMobileDashboard()),
    ]);
  }

  Widget _buildMobileDashboard() {
    return Container(height: 100, color: Colors.black.withOpacity(0.9), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
      _stat((_tripPartial/1000).toStringAsFixed(1), "TRIP", Colors.cyan),
      _btn(Icons.my_location, _follow ? Colors.orange : Colors.white, () => setState(() => _follow = true)),
    ]));
  }

  Widget _buildControlPanel() {
    return Container(width: 300, color: Colors.black, padding: const EdgeInsets.all(20), child: Column(children: [
      const Text("TRAIL 4X4 PRO", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
      const Spacer(),
      _stat(_speed.toStringAsFixed(0), "VITESSE", Colors.orange),
      const SizedBox(height: 20),
      _stat((_tripPartial/1000).toStringAsFixed(2), "TRIP PARTIEL", Colors.cyan),
      const SizedBox(height: 10),
      _stat((_tripTotal/1000).toStringAsFixed(2), "TOTAL KM", Colors.white),
      const Spacer(),
      ElevatedButton(onPressed: () => setState(() => _tripPartial = 0.0), child: const Text("RESET TRIP")),
    ]));
  }

  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
  Widget _btn(IconData i, Color b, VoidCallback o) => FloatingActionButton(heroTag: null, mini: true, backgroundColor: b, onPressed: o, child: Icon(i, color: Colors.white));
}
