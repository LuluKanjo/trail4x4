import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // INDISPENSABLE POUR LE FICHIER GPX
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
  
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  LatLng? _lastPos; 
  double _smoothLat = 0, _smoothLon = 0;
  final double _alpha = 0.18; 

  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _loading = false, _isNavigating = false;
  // ignore: prefer_final_fields
  bool _isRec = false;
  int _mapMode = 0; 
  bool _isNightMode = false;
  double _tripPartial = 0.0, _tripTotal = 0.0;
  double _pitch = 0.0, _roll = 0.0, _pitchOffset = 0.0, _rollOffset = 0.0;
  String _weather = "--°C";
  bool _isDownloading = false;
  
  final List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  final List<LatLng> _trace = [];
  final List<LatLng> _importedTrace = []; 
  List<Map<String, dynamic>> _personalWaypoints = [];
  HiveCacheStore? _cacheStore;
  late RoutingService _routing;
  late WeatherService _weatherService;
  List<String> _sosContacts = [];

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
    _weatherService = WeatherService();
    _loadStoredData();
  }

  void _startSensors() {
    accelerometerEventStream().listen((event) {
      if (!mounted) return;
      setState(() {
        double r = math.atan2(event.x, event.y) * -180 / math.pi;
        double p = math.atan2(event.z, event.y) * 180 / math.pi;
        _roll = r - _rollOffset;
        _pitch = p - _pitchOffset;
      });
    });
  }

  void _loadStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rollOffset = prefs.getDouble('roll_offset') ?? 0.0;
      _pitchOffset = prefs.getDouble('pitch_offset') ?? 0.0;
      _tripTotal = prefs.getDouble('trip_total') ?? 0.0;
      _sosContacts = prefs.getStringList('sos_contacts') ?? [];
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
        if (_isRec) _trace.add(_currentPos);
        if (_route.isNotEmpty) _remDist = const Distance().as(LengthUnit.Meter, _currentPos, _route.last);
      });
      if (_follow) _mapController.move(_currentPos, _mapController.camera.zoom);
    });
  }

  Future<void> _updateRoute() async {
    if (_waypoints.isEmpty) return;
    setState(() => _loading = true);
    // Switch de profil : 'car' pour Waze (autoroute) / 'foot' pour Piste (ville/court)
    final profile = _isNavigating ? 'car' : 'foot';
    final data = await _routing.getOffRoadRoute([_currentPos, ..._waypoints], [], profile: profile);
    if (data != null) {
      setState(() { _route.clear(); _route.addAll(data.points); _remDist = data.distance; });
    }
    setState(() => _loading = false);
  }

  Future<void> _loadGPX() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String contents = await file.readAsString();
      RegExp tagExp = RegExp(r'lat="([^"]+)" lon="([^"]+)"');
      Iterable<RegExpMatch> matches = tagExp.allMatches(contents);
      List<LatLng> newTrace = matches.map((m) => LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!))).toList();
      if (newTrace.isNotEmpty) { 
        setState(() { _importedTrace.clear(); _importedTrace.addAll(newTrace); _follow = false; }); 
        _mapController.move(newTrace.first, 13); 
      }
    }
  }

  String _getMapUrl() {
    if (_mapMode == 1) return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    if (_mapMode == 2) return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    return _isNightMode ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png' : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
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
              Expanded(
                child: Stack(
                  children: [
                    _buildMap(),
                    _buildFullOverlays(), // ON RESSORT TOUT LE MATOS
                    if (_isDownloading) Positioned(top: 100, left: 50, right: 50, child: Container(padding: const EdgeInsets.all(10), color: Colors.black87, child: const LinearProgressIndicator(color: Colors.orange))),
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

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPos, initialZoom: 15,
        onPositionChanged: (p, g) { if (g) setState(() => _follow = false); },
        onLongPress: (tp, ll) { setState(() { _waypoints.clear(); _waypoints.add(ll); }); _updateRoute(); },
      ),
      children: [
        TileLayer(
          urlTemplate: _getMapUrl(),
          userAgentPackageName: 'com.trail4x4.expedition.pro', // DÉBLOQUE LA CARTE
          tileProvider: _cacheStore != null ? CachedTileProvider(store: _cacheStore!) : null,
        ),
        if (_importedTrace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _importedTrace, color: Colors.purpleAccent, strokeWidth: 6)]),
        PolylineLayer(polylines: [
          if (_route.isNotEmpty) Polyline(points: List<LatLng>.from(_route), color: Colors.orange, strokeWidth: 8)
        ]),
        MarkerLayer(markers: [
          Marker(point: _currentPos, width: 80, height: 80, child: Transform.rotate(angle: _head * math.pi / 180, child: const Icon(Icons.navigation, color: Colors.orange, size: 45))),
          ..._waypoints.map((w) => Marker(point: w, child: const Icon(Icons.location_on, color: Colors.red, size: 40))),
        ]),
      ],
    );
  }

  Widget _buildFullOverlays() {
    return Stack(children: [
      // HAUT : SOS, METEO, SWITCH, OFFLINE
      Positioned(top: 40, left: 10, right: 10, child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _glassBtn(Icons.warning, Colors.red, () {
            if (_sosContacts.isNotEmpty) launchUrl(Uri.parse("sms:${_sosContacts.first}?body=SOS"));
          }),
          Container(padding: const EdgeInsets.all(8), decoration: _glassDecoration(), child: Text(_weather, style: const TextStyle(fontWeight: FontWeight.bold))),
          _glassBtn(_isNavigating ? Icons.directions_car : Icons.terrain, _isNavigating ? Colors.blue : Colors.green, () { setState(() => _isNavigating = !_isNavigating); _updateRoute(); }),
          _glassBtn(Icons.download_for_offline, Colors.greenAccent, () { setState(() => _isDownloading = true); Future.delayed(const Duration(seconds: 2), () => setState(() => _isDownloading = false)); }),
        ],
      )),

      // GAUCHE : GPX, WAYPOINT, REC
      Positioned(top: 100, left: 15, child: Column(children: [
        _glassBtn(Icons.folder_open, Colors.blueAccent, _loadGPX),
        const SizedBox(height: 8),
        _glassBtn(Icons.add_location_alt, Colors.amber, () {
           setState(() => _personalWaypoints.add({'lat': _currentPos.latitude, 'lon': _currentPos.longitude}));
        }),
        const SizedBox(height: 8),
        _glassBtn(_isRec ? Icons.stop : Icons.fiber_manual_record, _isRec ? Colors.red : Colors.grey, () => setState(() => _isRec = !_isRec)),
      ])),

      // DROITE : INCLINOMETRE, LAYERS
      Positioned(top: 100, right: 15, child: Column(children: [
        _miniIncline("ROLL", _roll),
        const SizedBox(height: 8),
        _miniIncline("PITCH", _pitch),
        const SizedBox(height: 15),
        _glassBtn(Icons.layers, Colors.indigo, () => setState(() => _mapMode = (_mapMode + 1) % 3)),
        const SizedBox(height: 8),
        _glassBtn(Icons.exposure_zero, Colors.white, () { setState(() { _rollOffset += _roll; _pitchOffset += _pitch; }); }),
      ])),

      // BAS : DASHBOARD COMPLET
      Positioned(bottom: 0, left: 0, right: 0, child: Container(
        height: 100, color: Colors.black.withOpacity(0.9),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
          _stat((_tripPartial/1000).toStringAsFixed(1), "TRIP KM", Colors.cyan),
          _stat(_alt.toStringAsFixed(0), "ALT", Colors.white),
          _glassBtn(Icons.my_location, _follow ? Colors.orange : Colors.white, () => setState(() { _follow = true; _mapController.move(_currentPos, 15); })),
        ]),
      )),
    ]);
  }

  Widget _buildControlPanel() {
    return Container(width: 320, color: Colors.black, padding: const EdgeInsets.all(20), child: Column(children: [
      const Text("TRAIL 4X4 PRO", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
      const Spacer(),
      _stat(_speed.toStringAsFixed(0), "VITESSE", Colors.orange),
      _stat((_tripPartial/1000).toStringAsFixed(2), "TRIP KM", Colors.cyan),
      const Spacer(),
      _miniIncline("ROLL", _roll),
      _miniIncline("PITCH", _pitch),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: () => setState(() => _tripPartial = 0.0), child: const Text("RESET TRIP")),
    ]));
  }

  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey))]);
  Widget _miniIncline(String l, double a) => Container(padding: const EdgeInsets.all(8), decoration: _glassDecoration(), child: Column(children: [Text(l, style: const TextStyle(fontSize: 8)), Text("${a.abs().toStringAsFixed(0)}°", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: a.abs() > 30 ? Colors.red : Colors.orange))]));
  Widget _glassBtn(IconData i, Color c, VoidCallback o) => GestureDetector(onTap: o, child: Container(padding: const EdgeInsets.all(10), decoration: _glassDecoration(), child: Icon(i, color: c, size: 24)));
  BoxDecoration _glassDecoration() => BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10));
}
