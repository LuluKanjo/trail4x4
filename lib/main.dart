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
  
  // GPS DIRECT (Filtre supprimé pour réactivité instantanée)
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  LatLng? _lastPos; 

  // ÉTATS
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  int _followMode = 2; // 0=Libre, 1=Centré, 2=Centré+Rotation
  bool _loading = false;
  bool _isNavigating = false;
  bool _isExpeditionMode = false; // Mode Route par défaut
  bool _isRec = false;
  int _mapMode = 0; 
  double _tripPartial = 0.0, _tripTotal = 0.0;
  double _pitch = 0.0, _roll = 0.0, _pitchOffset = 0.0, _rollOffset = 0.0;
  String _weather = "--°C";
  
  // LISTES DE DONNÉES
  final List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  final List<LatLng> _trace = []; // Enregistrement live
  final List<LatLng> _importedTrace = []; // Traces GPX
  final List<LatLng> _forbiddenZones = []; // Chemins interdits
  final List<POI> _pois = []; // Essence / Eau
  List<Map<String, dynamic>> _personalWaypoints = [];
  List<String> _sosContacts = [];
  
  HiveCacheStore? _cacheStore;
  late RoutingService _routing;
  late WeatherService _weatherService;
  late POIService _poiService;

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
    _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
    _loadStoredData();
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
      
      final savedZones = prefs.getStringList('forbidden_zones') ?? [];
      _forbiddenZones.addAll(savedZones.map((s) {
        final p = s.split(','); return LatLng(double.parse(p[0]), double.parse(p[1]));
      }));
    });
    final w = await _weatherService.getCurrentWeather(_currentPos.latitude, _currentPos.longitude);
    if (mounted) setState(() => _weather = w);
  }

  // --- ACTIONS DE SAUVEGARDE ---

  void _saveWaypoint(String name) async {
    final wp = {'name': name, 'lat': _currentPos.latitude, 'lon': _currentPos.longitude};
    setState(() => _personalWaypoints.add(wp));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('personal_waypoints', _personalWaypoints.map((w) => json.encode(w)).toList());
  }

  void _markForbidden() async {
    setState(() => _forbiddenZones.add(_currentPos));
    final prefs = await SharedPreferences.getInstance();
    List<String> zonesStr = _forbiddenZones.map((z) => '${z.latitude},${z.longitude}').toList();
    await prefs.setStringList('forbidden_zones', zonesStr);
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chemin bloqué ! Le GPS l'évitera.")));
      if (_route.isNotEmpty) _updateRoute(); // Recalcule la route sans ce chemin
    }
  }

  // --- MOTEUR GPS ULTRA-RÉACTIF ---

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0))
    .listen((pos) {
      if (!mounted) return;
      setState(() {
        // POSITION DIRECTE (Fini la saccade)
        _currentPos = LatLng(pos.latitude, pos.longitude);
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
      
      // ROTATION ET CENTRAGE AUTO
      if (_followMode > 0) {
        _mapController.move(_currentPos, _mapController.camera.zoom);
        // Si Mode 2 et qu'on avance (même en marchant), la carte tourne
        if (_followMode == 2 && _speed > 1.0) {
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
    // On envoie les zones interdites au moteur pour qu'il les contourne
    final data = await _routing.getOffRoadRoute([_currentPos, ..._waypoints], _forbiddenZones, profile: profile);
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
        setState(() { _importedTrace.clear(); _importedTrace.addAll(newTrace); _followMode = 0; }); 
        _mapController.move(newTrace.first, 13); 
      }
    }
  }

  void _togglePOI(String type) async {
    if (_pois.any((p) => p.type == type)) {
      setState(() => _pois.removeWhere((p) => p.type == type));
    } else {
      setState(() => _loading = true);
      try {
        final newPois = await _poiService.fetchPOIs(_currentPos.latitude, _currentPos.longitude, type);
        setState(() => _pois.addAll(newPois));
      } catch (e) { debugPrint("POI Error"); }
      setState(() => _loading = false);
    }
  }

  void _sendSOS() async {
    if (_sosContacts.isEmpty) return;
    final msg = "SOS 4X4 ! Position : http://maps.google.com/?q=${_currentPos.latitude},${_currentPos.longitude}";
    launchUrl(Uri.parse("sms:${_sosContacts.first}?body=${Uri.encodeComponent(msg)}"));
  }

  String _getMapUrl() {
    if (_mapMode == 1) return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    if (_mapMode == 2) return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPos, initialZoom: 15,
            onPositionChanged: (p, g) { if (g) setState(() => _followMode = 0); }, // Coupe le suivi si on touche la carte
            onLongPress: (tp, ll) { setState(() { _waypoints.clear(); _waypoints.add(ll); }); _updateRoute(); },
          ),
          children: [
            TileLayer(
              urlTemplate: _getMapUrl(),
              userAgentPackageName: 'com.trail4x4.expedition.pro',
              tileProvider: _cacheStore != null ? CachedTileProvider(store: _cacheStore!) : null,
            ),
            if (_importedTrace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _importedTrace, color: Colors.purpleAccent, strokeWidth: 6)]),
            if (_trace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _trace, color: Colors.redAccent, strokeWidth: 5)]),
            if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: List<LatLng>.from(_route), color: Colors.orange, strokeWidth: _isNavigating ? 12 : 8)]),
            MarkerLayer(markers: [
              // Bivouacs persos
              ..._personalWaypoints.map((wp) => Marker(point: LatLng(wp['lat'], wp['lon']), child: const Icon(Icons.star, color: Colors.amber, size: 30))),
              // Chemins Interdits
              ..._forbiddenZones.map((z) => Marker(point: z, child: const Icon(Icons.do_not_disturb_on, color: Colors.red, size: 25))),
              // POIs (Essence, Eau)
              ..._pois.map((p) => Marker(point: p.position, child: Icon(p.type == 'gas' ? Icons.local_gas_station : Icons.water_drop, color: Colors.blueAccent, size: 30))),
              // La destination
              ..._waypoints.map((w) => Marker(point: w, child: const Icon(Icons.location_on, color: Colors.red, size: 40))),
              // NOUS (Defender)
              Marker(point: _currentPos, width: 100, height: 100, child: Transform.rotate(angle: (_followMode == 2) ? 0 : (_head * math.pi / 180), child: const Icon(Icons.navigation, color: Colors.orange, size: 50))),
            ]),
          ],
        ),

        // BARRE HAUTE
        Positioned(top: 40, left: 15, right: 15, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _glassBtn(Icons.warning, Colors.red, _sendSOS),
          Container(padding: const EdgeInsets.all(8), decoration: _glassDecoration(), child: Text(_weather, style: const TextStyle(fontWeight: FontWeight.bold))),
          _glassBtn(_isExpeditionMode ? Icons.terrain : Icons.directions_car, _isExpeditionMode ? Colors.green : Colors.blue, () { 
            setState(() => _isExpeditionMode = !_isExpeditionMode); _updateRoute(); 
          }),
        ])),

        // BOITE A OUTILS GAUCHE (GPX, REC, SPOT, INTERDIT)
        Positioned(top: 100, left: 15, child: Column(children: [
          _glassBtn(Icons.folder_open, Colors.white, _loadGPX), // DOSSIER GPX
          const SizedBox(height: 10),
          _glassBtn(_isRec ? Icons.stop : Icons.fiber_manual_record, _isRec ? Colors.red : Colors.white, () => setState(() => _isRec = !_isRec)), // ENREGISTREMENT
          const SizedBox(height: 10),
          _glassBtn(Icons.add_location_alt, Colors.amber, () { // SPOT DODO
            final c = TextEditingController();
            showDialog(context: context, builder: (ctx) => AlertDialog(
              title: const Text("Nouveau Spot"), content: TextField(controller: c),
              actions: [TextButton(onPressed: () { _saveWaypoint(c.text); Navigator.pop(ctx); }, child: const Text("OK"))],
            ));
          }),
          const SizedBox(height: 10),
          _glassBtn(Icons.do_not_disturb_on, Colors.redAccent, _markForbidden), // CHEMIN INTERDIT
        ])),

        // BOITE A OUTILS DROITE (POI, LAYERS, INCLINOMETRE)
        Positioned(top: 100, right: 15, child: Column(children: [
          _glassBtn(Icons.local_gas_station, _pois.any((p)=>p.type=='gas') ? Colors.blue : Colors.white, () => _togglePOI('gas')), // ESSENCE
          const SizedBox(height: 10),
          _glassBtn(Icons.water_drop, _pois.any((p)=>p.type=='water') ? Colors.lightBlueAccent : Colors.white, () => _togglePOI('water')), // EAU
          const SizedBox(height: 10),
          _glassBtn(Icons.layers, Colors.indigo, () => setState(() => _mapMode = (_mapMode + 1) % 3)), // CARTES
          const SizedBox(height: 20),
          _miniIncline("ROLL", _roll), // INCLINOMETRE
          const SizedBox(height: 5),
          _miniIncline("PITCH", _pitch),
        ])),

        // DASHBOARD BAS (VITESSE, TRIP, ALT, BOUSSOLE)
        Positioned(bottom: 0, left: 0, right: 0, child: Container(
          height: 90, color: Colors.black.withOpacity(0.9),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
            _stat((_tripPartial/1000).toStringAsFixed(1), "TRIP KM", Colors.cyan),
            _stat(_alt.toStringAsFixed(0), "ALT", Colors.white),
            
            // LE BOUTON MAGIQUE DU GPS (Libre -> Centré -> Boussole)
            _glassBtn(
              _followMode == 2 ? Icons.explore : (_followMode == 1 ? Icons.my_location : Icons.location_disabled), 
              _followMode == 2 ? Colors.red : (_followMode == 1 ? Colors.orange : Colors.grey), 
              () {
                setState(() {
                  _followMode = (_followMode + 1) % 3; // Fait tourner entre 0, 1 et 2
                  if (_followMode > 0) _mapController.move(_currentPos, 16);
                  if (_followMode != 2) _mapController.rotate(0); // Remet la carte droite
                });
              }
            ),
          ]),
        )),
        if (_loading) const Center(child: CircularProgressIndicator(color: Colors.orange)),
      ]),
    );
  }

  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey))]);
  Widget _miniIncline(String l, double a) => Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Column(children: [Text(l, style: const TextStyle(fontSize: 8)), Text("${a.abs().toStringAsFixed(0)}°", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: a.abs() > 30 ? Colors.red : Colors.orange))]));
  Widget _glassBtn(IconData i, Color c, VoidCallback o) => GestureDetector(onTap: o, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Icon(i, color: c, size: 24)));
}
