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

// LES DEUX NOUVELLES OPTIONS
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';

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
  LatLng _currentPos = const LatLng(43.5478, 3.7388); 
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _isSat = false, _isRec = false, _loading = false;
  bool _isNavigating = false; 
  String _weather = "--°C";
  
  List<LatLng> _route = [];
  final List<LatLng> _waypoints = [];
  final List<LatLng> _trace = [];
  List<LatLng> _importedTrace = []; // LA NOUVELLE TRACE IMPORTÉE
  final List<LatLng> _forbiddenZones = [];
  final List<POI> _pois = [];
  
  late RoutingService _routing;
  late POIService _poiService;
  late WeatherService _weatherService;
  List<String> _sosContacts = [];

  @override
  void initState() {
    super.initState();
    // OPTION 1 : ANTI-VEILLE ACTIVÉ 🔋
    WakelockPlus.enable(); 

    _routing = RoutingService('');
    _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
    _weatherService = WeatherService();
    _loadData();
    _startTracking();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _sosContacts = prefs.getStringList('sos_contacts') ?? []);
    final savedZones = prefs.getStringList('forbidden_zones') ?? [];
    if (savedZones.isNotEmpty) {
      setState(() {
        _forbiddenZones.addAll(savedZones.map((s) {
          final parts = s.split(',');
          return LatLng(double.parse(parts[0]), double.parse(parts[1]));
        }));
      });
    }
    _weather = await _weatherService.getCurrentWeather(_currentPos.latitude, _currentPos.longitude);
    if (mounted) setState(() {});
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
        if (_isRec) _trace.add(_currentPos);
        if (_route.isNotEmpty) _remDist = const Distance().as(LengthUnit.Meter, _currentPos, _route.last);
      });
      
      if (_follow) {
        if (_isNavigating) {
          _mapController.move(_currentPos, 17.5);
          if (_speed > 1.0) _mapController.rotate(360 - _head);
        } else {
          _mapController.move(_currentPos, _mapController.camera.zoom);
          _mapController.rotate(0);
        }
      }
    });
  }

  Future<void> _updateRoute() async {
    if (_waypoints.isEmpty) return;
    setState(() => _loading = true);
    final data = await _routing.getOffRoadRoute([_currentPos, ..._waypoints], _forbiddenZones);
    if (data != null) {
      setState(() { _route = data.points; _remDist = data.distance; _follow = true; });
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trace impossible à calculer.")));
      setState(() { _route = []; _remDist = 0; _isNavigating = false; });
    }
    setState(() => _loading = false);
  }

  Future<void> _searchAddress(String address) async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/search?q=$address&format=json&limit=1'), headers: {'User-Agent': 'Trail4x4'});
      final data = json.decode(res.body);
      if (data.isNotEmpty) {
        final dest = LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
        setState(() => _waypoints.add(dest));
        await _updateRoute();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lieu introuvable")));
      }
    } catch (e) { 
      debugPrint(e.toString()); 
    }
    setState(() => _loading = false);
  }

  // OPTION 2 : LE LECTEUR DE FICHIER GPX 🗺️
  Future<void> _loadGPX() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String contents = await file.readAsString();
        
        // On scanne le fichier pour trouver toutes les coordonnées
        RegExp tagExp = RegExp(r'<trkpt([^>]+)>');
        Iterable<RegExpMatch> matches = tagExp.allMatches(contents);
        
        List<LatLng> newTrace = [];
        for (var m in matches) {
          String attrs = m.group(1) ?? '';
          RegExp latExp = RegExp(r'lat="([^"]+)"');
          RegExp lonExp = RegExp(r'lon="([^"]+)"');
          String? latStr = latExp.firstMatch(attrs)?.group(1);
          String? lonStr = lonExp.firstMatch(attrs)?.group(1);
          
          if (latStr != null && lonStr != null) {
            newTrace.add(LatLng(double.parse(latStr), double.parse(lonStr)));
          }
        }
        
        if (newTrace.isNotEmpty) {
          setState(() {
            _importedTrace = newTrace;
            _follow = false; // On lâche la caméra pour que tu puisses voir la trace
          });
          _mapController.move(newTrace.first, 13); // On zoome sur le départ de la trace
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Trace chargée (${newTrace.length} points) !"), backgroundColor: Colors.green));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aucun point valide trouvé dans ce fichier.")));
        }
      }
    } catch (e) {
      debugPrint("Erreur GPX: $e");
    }
  }

  void _addForbiddenZone() async {
    setState(() => _forbiddenZones.add(_currentPos));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('forbidden_zones', _forbiddenZones.map((p) => '${p.latitude},${p.longitude}').toList());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mur invisible créé ! Recalcul..."), backgroundColor: Colors.red));
    if (_waypoints.isNotEmpty) _updateRoute();
  }

  void _togglePOI(String type) async {
    if (_pois.any((p) => p.type == type)) {
      setState(() => _pois.removeWhere((p) => p.type == type));
    } else {
      setState(() => _loading = true);
      final newPois = await _poiService.fetchPOIs(_currentPos.latitude, _currentPos.longitude, type);
      setState(() { _pois.addAll(newPois); _loading = false; });
    }
  }

  void _sendSOS() async {
    if (_sosContacts.isEmpty) return;
    final msg = "SOS 4X4 ! Aide demandée ici : http://googleusercontent.com/maps.google.com/?q=${_currentPos.latitude},${_currentPos.longitude}";
    final uri = Uri.parse("sms:${_sosContacts.first}?body=${Uri.encodeComponent(msg)}");
    await launchUrl(uri);
  }

  Future<void> _saveTraceGPX() async {
    if (_trace.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/trace_${DateTime.now().millisecondsSinceEpoch}.gpx");
    String gpx = '<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1"><trk><trkseg>';
    for (var p in _trace) { gpx += '<trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>'; }
    gpx += '</trkseg></trk></gpx>';
    await file.writeAsString(gpx);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trace GPX sauvegardée !"), backgroundColor: Colors.green));
  }

  Widget _btn(IconData i, Color b, VoidCallback o) => FloatingActionButton(heroTag: null, mini: true, backgroundColor: b, onPressed: o, child: Icon(i, color: Colors.white));
  Widget _poiBtn(String t, IconData i, Color c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: FloatingActionButton(heroTag: null, mini: true, backgroundColor: _pois.any((p) => p.type == t) ? c : Colors.black87, onPressed: () => _togglePOI(t), child: Icon(i, color: Colors.white)));
  Widget _stat(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
  String _getDir(double h) { if (h < 22.5 || h >= 337.5) return "N"; if (h < 67.5) return "NE"; if (h < 112.5) return "E"; if (h < 157.5) return "SE"; if (h < 202.5) return "S"; if (h < 247.5) return "SO"; if (h < 292.5) return "O"; return "NO"; }

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
                userAgentPackageName: 'com.trail4x4',
                urlTemplate: _isSat 
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              // TRACE DU COPAIN (VIOLET)
              if (_importedTrace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _importedTrace, color: Colors.purpleAccent, strokeWidth: 6)]),
              // LIGNE DE GUIDAGE (CYAN)
              if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.cyanAccent, strokeWidth: _isNavigating ? 12 : 8)]),
              // TA PROPRE TRACE ENREGISTRÉE (ORANGE)
              if (_trace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _trace, color: Colors.orange, strokeWidth: 4)]),
              
              MarkerLayer(markers: [
                ..._forbiddenZones.map((p) => Marker(point: p, child: const Icon(Icons.do_not_disturb, color: Colors.red))),
                ..._pois.map((p) => Marker(point: p.position, child: Icon(p.type == 'fuel' ? Icons.local_gas_station : (p.type == 'water' ? Icons.water_drop : Icons.terrain), color: p.type == 'fuel' ? Colors.yellow : (p.type == 'water' ? Colors.blue : Colors.green)))),
                ..._waypoints.map((p) => Marker(point: p, child: const Icon(Icons.location_on, color: Colors.cyanAccent))),
                Marker(
                  point: _currentPos, 
                  width: 60, height: 60, 
                  child: Transform.rotate(
                    angle: _isNavigating ? 0 : (_head * math.pi / 180),
                    child: const Icon(Icons.navigation, color: Colors.orange, size: 50),
                  )
                ),
              ]),
            ],
          ),
          
          Positioned(top: 40, left: 10, right: 10, child: _isNavigating ? _buildNavHud() : _buildStandardHud()),

          if (!_isNavigating) Positioned(left: 10, top: 120, child: Column(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)), child: Text(_weather, style: const TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 15),
            _poiBtn("fuel", Icons.local_gas_station, Colors.yellow),
            _poiBtn("water", Icons.water_drop, Colors.blue),
            _poiBtn("camp", Icons.terrain, Colors.green),
          ])),

          if (_isNavigating) Positioned(left: 10, top: 120, child: FloatingActionButton(
            backgroundColor: Colors.red, onPressed: _addForbiddenZone, child: const Icon(Icons.block, color: Colors.white, size: 30)
          )),

          Positioned(bottom: 120, right: 15, child: Column(children: [
            if (!_isNavigating) ...[
              _btn(Icons.search, Colors.cyan.shade700, () {
                final c = TextEditingController();
                showDialog(context: context, builder: (ctx) => AlertDialog(
                  title: const Text("Naviguer vers :"),
                  content: TextField(controller: c, decoration: const InputDecoration(hintText: "Pignan, Adresse...")),
                  actions: [TextButton(onPressed: () { final nav = Navigator.of(ctx); _searchAddress(c.text); nav.pop(); }, child: const Text("GO"))],
                ));
              }),
              const SizedBox(height: 10),
              // LE BOUTON DOSSIER POUR OUVRIR UN FICHIER GPX
              _btn(Icons.folder_open, Colors.blueAccent, _loadGPX),
              const SizedBox(height: 10),
            ],
            _btn(_isSat ? Icons.map : Icons.satellite_alt, Colors.black87, () => setState(() => _isSat = !_isSat)),
            const SizedBox(height: 10),
            _btn(Icons.my_location, _follow ? Colors.orange : Colors.grey.shade800, () { 
              setState(() => _follow = true); 
              _mapController.move(_currentPos, _isNavigating ? 17.5 : 15); 
              if (!_isNavigating) _mapController.rotate(0);
            }),
            const SizedBox(height: 10),
            if (!_isNavigating) _btn(Icons.settings, Colors.black87, _showSettings),
          ])),

          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            height: 90, color: Colors.black,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _stat(_speed.toStringAsFixed(0), "KM/H", Colors.orange),
              _stat(_alt.toStringAsFixed(0), "ALT", Colors.white),
              _stat(_getDir(_head), "CAP", Colors.cyanAccent),
            ]),
          )),
          
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        ],
      ),
    );
  }

  Widget _buildStandardHud() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _btn(Icons.warning, Colors.red, _sendSOS),
        if (_route.isNotEmpty) Row(children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            label: const Text("DÉMARRER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => setState(() { _isNavigating = true; _follow = true; }),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.cyanAccent)),
            child: Row(children: [
              Text("${(_remDist/1000).toStringAsFixed(1)} KM", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() { _route = []; _waypoints.clear(); _remDist = 0; })),
            ]),
          ),
        ]),
        if (_route.isEmpty) Row(children: [
          if (_importedTrace.isNotEmpty) IconButton(icon: const Icon(Icons.clear_all, color: Colors.purpleAccent), onPressed: () => setState(() => _importedTrace = [])),
          _btn(_isRec ? Icons.stop : Icons.fiber_manual_record, _isRec ? Colors.red : Colors.grey.shade800, () {
            setState(() => _isRec = !_isRec);
            if (!_isRec) _saveTraceGPX();
          }),
        ]),
      ],
    );
  }

  Widget _buildNavHud() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange, width: 2)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.navigation, color: Colors.orange, size: 30),
          Text("${(_remDist/1000).toStringAsFixed(1)} KM Restants", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.red, size: 35),
            onPressed: () => setState(() { _isNavigating = false; _mapController.rotate(0); }),
          )
        ],
      ),
    );
  }

  void _showSettings() {
    final c = TextEditingController(text: _sosContacts.isNotEmpty ? _sosContacts.first : "");
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Tél SOS"), 
      content: TextField(controller: c, keyboardType: TextInputType.phone), 
      actions: [TextButton(onPressed: () async { 
        if(c.text.isEmpty) return; 
        final nav = Navigator.of(ctx);
        final prefs = await SharedPreferences.getInstance(); 
        await prefs.setStringList('sos_contacts', [c.text]);
        if (mounted) setState(() => _sosContacts = [c.text]);
        nav.pop(); 
      }, child: const Text("OK"))]
    ));
  }
}
