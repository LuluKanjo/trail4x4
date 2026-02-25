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

  // ÉTATS NAVIGATION
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _loading = false, _isNavigating = false;
  bool _isExpeditionMode = false; 
  int _mapMode = 0; 
  double _tripPartial = 0.0, _tripTotal = 0.0;
  double _pitch = 0.0, _roll = 0.0, _pitchOffset = 0.0, _rollOffset = 0.0;
  String _weather = "--°C";
  
  // DONNÉES PERSISTANTES
  final List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  List<Map<String, dynamic>> _personalWaypoints = [];
  List<String> _sosContacts = [];
  
  HiveCacheStore? _cacheStore;
  late RoutingService _routing;
  late WeatherService _weatherService;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _initServices();
    _startTracking();
    _startSensors();
  }

  void _initServices() async {
    final dir = await getApplicationDocumentsDirectory();
    _cacheStore = HiveCacheStore(dir.path);
    _routing = RoutingService('');
    _weatherService = WeatherService();
    _loadStoredData();
  }

  // CHARGEMENT DE LA MÉMOIRE DU DEFENDER
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

  // SAUVEGARDE DES SPOTS
  void _saveWaypoint(String name) async {
    final wp = {'name': name, 'lat': _currentPos.latitude, 'lon': _currentPos.longitude};
    setState(() => _personalWaypoints.add(wp));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('personal_waypoints', _personalWaypoints.map((w) => json.encode(w)).toList());
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0))
    .listen((pos) {
      if (!mounted) return;
      // FILTRE PASSE-BAS : $Pos_{lisse} = \alpha \cdot Pos_{brute} + (1 - \alpha) \cdot Pos_{prec}$
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
      
      // LOGIQUE NAVIGATION : Suivi et Rotation
      if (_follow) {
        _mapController.move(_currentPos, _isNavigating ? 17.5 : _mapController.camera.zoom);
        if (_isNavigating && _speed > 2.0) {
          _mapController.rotate(360 - _head);
        }
      }
    });
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

  Future<void> _updateRoute() async {
    if (_waypoints.isEmpty) return;
    setState(() => _loading = true);
    final profile = _isExpeditionMode ? 'foot' : 'car';
    final data = await _routing.getOffRoadRoute([_currentPos, ..._waypoints], [], profile: profile);
    if (data != null) {
      setState(() { _route.clear(); _route.addAll(data.points); _remDist = data.distance; });
    }
    setState(() => _loading = false);
  }

  void _sendSOS() async {
    if (_sosContacts.isEmpty) {
      _showSettings(); // Si pas de contact, on ouvre les réglages
      return;
    }
    final msg = "SOS 4X4 ! Position : http://maps.google.com/?q=${_currentPos.latitude},${_currentPos.longitude}";
    launchUrl(Uri.parse("sms:${_sosContacts.first}?body=${Uri.encodeComponent(msg)}"));
  }

  void _showSettings() {
    final c = TextEditingController(text: _sosContacts.isNotEmpty ? _sosContacts.first : "");
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Réglages SOS"),
      content: TextField(controller: c, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "N° téléphone d'urgence")),
      actions: [TextButton(onPressed: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('sos_contacts', [c.text]);
        setState(() => _sosContacts = [c.text]);
        if(mounted) Navigator.pop(ctx);
      }, child: const Text("SAUVEGARDER"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPos, initialZoom: 15,
            onPositionChanged: (p, g) { if (g) setState(() => _follow = false); },
            onLongPress: (tp, ll) { setState(() { _waypoints.clear(); _waypoints.add(ll); }); _updateRoute(); },
          ),
          children: [
            TileLayer(
              urlTemplate: _mapMode == 1 ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}' : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trail4x4.expedition.pro',
              tileProvider: _cacheStore != null ? CachedTileProvider(store: _cacheStore!) : null,
            ),
            if (_route.isNotEmpty) PolylineLayer(polylines: [
              Polyline(points: List<LatLng>.from(_route), color: Colors.orange, strokeWidth: _isNavigating ? 12 : 8)
            ]),
            MarkerLayer(markers: [
              ..._personalWaypoints.map((wp) => Marker(point: LatLng(wp['lat'], wp['lon']), child: const Icon(Icons.star, color: Colors.amber, size: 30))),
              Marker(point: _currentPos, width: 100, height: 100, child: Transform.rotate(angle: _isNavigating ? 0 : (_head * math.pi / 180), child: const Icon(Icons.navigation, color: Colors.orange, size: 50))),
              ..._waypoints.map((w) => Marker(point: w, child: const Icon(Icons.location_on, color: Colors.red, size: 40))),
            ]),
          ],
        ),

        // BARRE HAUTE
        Positioned(top: 40, left: 15, right: 15, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _glassBtn(Icons.warning, Colors.red, _sendSOS),
          
          // BOUTON START NAVIGATION (Apparaît si tracé OK)
          if (_route.isNotEmpty && !_isNavigating)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () => setState(() { _isNavigating = true; _follow = true; }),
              icon: const Icon(Icons.play_arrow), label: const Text("DÉMARRER"),
            ),
          
          if (_isNavigating)
            _glassBtn(Icons.stop, Colors.red, () => setState(() { _isNavigating = false; _mapController.rotate(0); })),

          _glassBtn(_isExpeditionMode ? Icons.terrain : Icons.directions_car, _isExpeditionMode ? Colors.green : Colors.blue, () { 
            setState(() => _isExpeditionMode = !_isExpeditionMode); _updateRoute(); 
          }),
        ])),

        // INSTRUMENTS DROITE
        Positioned(top: 100, right: 15, child: Column(children: [
          _miniIncline("ROLL", _roll),
          const SizedBox(height: 10),
          _miniIncline("PITCH", _pitch),
          const SizedBox(height: 10),
          _glassBtn(Icons.exposure_zero, Colors.white, () { setState(() { _rollOffset += _roll; _pitchOffset += _pitch; }); }),
          const SizedBox(height: 10),
          _glassBtn(Icons.settings, Colors.grey, _showSettings),
        ])),

        // BOUTON ENREGISTRER SPOT (GAUCHE)
        Positioned(top: 100, left: 15, child: Column(children: [
          _glassBtn(Icons.add_location_alt, Colors.amber, () {
            final c = TextEditingController();
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: const Text("Nouveau Spot"),
              content: TextField(controller: c, decoration: const InputDecoration(hintText: "Nom du bivouac/point")),
              actions: [TextButton(onPressed: () { _saveWaypoint(c.text); Navigator.pop(ctx); }, child: const Text("OK"))],
            ));
          }),
        ])),

        // DASHBOARD BAS
        Positioned(bottom: 0, left: 0, right: 0, child: Container(
          height: 110, color: Colors.black.withOpacity(0.9),
          child: Column(children: [
            if (_isNavigating) Padding(padding: const EdgeInsets.only(top: 5), child: Text("${(_remDist/1000).toStringAsFixed(1)} KM RESTANTS", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
              _stat((_tripPartial/1000).toStringAsFixed(1), "TRIP KM", Colors.cyan),
              _stat(_alt.toStringAsFixed(0), "ALT", Colors.white),
              _glassBtn(Icons.my_location, _follow ? Colors.orange : Colors.white, () => setState(() => _follow = true)),
            ]),
          ]),
        )),
        if (_loading) const Center(child: CircularProgressIndicator(color: Colors.orange)),
      ]),
    );
  }

  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey))]);
  Widget _miniIncline(String l, double a) => Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(l, style: const TextStyle(fontSize: 8)), Text("${a.abs().toStringAsFixed(0)}°", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: a.abs() > 30 ? Colors.red : Colors.orange))]));
  Widget _glassBtn(IconData i, Color c, VoidCallback o) => GestureDetector(onTap: o, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Icon(i, color: c, size: 24)));
}
