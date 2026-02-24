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
  LatLng _currentPos = const LatLng(43.5478, 3.7388); // Cournonterral
  double _speed = 0, _alt = 0, _head = 0, _remDist = 0;
  bool _follow = true, _isSat = false, _isRec = false, _loading = false;
  
  List<LatLng> _route = [];
  final List<LatLng> _trace = [];
  List<POI> _pois = [];
  
  late RoutingService _routing;
  late POIService _poiService;
  List<String> _sosContacts = [];

  @override
  void initState() {
    super.initState();
    _routing = RoutingService('');
    _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
    _loadData();
    _startTracking();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _sosContacts = prefs.getStringList('sos_contacts') ?? []);
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
        _mapController.move(_currentPos, _mapController.camera.zoom);
        if (_speed > 3) _mapController.rotate(-_head);
      }
    });
  }

  Future<void> _calculateRoute(LatLng dest) async {
    setState(() => _loading = true);
    final data = await _routing.getOffRoadRoute(_currentPos, dest);
    if (data != null) setState(() { _route = data.points; _remDist = data.distance; _follow = true; });
    setState(() => _loading = false);
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
    if (_sosContacts.isEmpty) { _showSettings(); return; }
    final msg = "URGENT 4X4 - Aide demandée ! Position : http://maps.google.com/?q=${_currentPos.latitude},${_currentPos.longitude}";
    for (var c in _sosContacts) {
      final uri = Uri.parse("sms:$c?body=${Uri.encodeComponent(msg)}");
      await launchUrl(uri);
    }
  }

  Future<void> _saveTrace() async {
    if (_trace.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/trace_${DateTime.now().millisecondsSinceEpoch}.gpx");
    String gpx = '<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="Trail4x4"><trk><trkseg>';
    for (var p in _trace) { gpx += '<trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>'; }
    gpx += '</trkseg></trk></gpx>';
    await file.writeAsString(gpx);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trace sauvegardée !"), backgroundColor: Colors.green));
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
              onLongPress: (tp, ll) => _calculateRoute(ll),
            ),
            children: [
              TileLayer(
                userAgentPackageName: 'com.trail4x4.app',
                urlTemplate: _isSat 
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.cyanAccent, strokeWidth: 8)]),
              if (_trace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _trace, color: Colors.orange, strokeWidth: 4)]),
              MarkerLayer(markers: [
                ..._pois.map((p) => Marker(point: p.position, child: Icon(_poiIcon(p.type), color: _poiColor(p.type)))),
                Marker(point: _currentPos, width: 60, height: 60, child: const Icon(Icons.navigation, color: Colors.orange, size: 50)),
              ]),
            ],
          ),
          // HUD HAUT
          Positioned(top: 40, left: 10, right: 10, child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _btnIcon(Icons.warning, Colors.red, _sendSOS, "sos"),
              if (_route.isNotEmpty) Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.cyanAccent)),
                child: Text("${(_remDist/1000).toStringAsFixed(1)} KM", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              ),
              _btnIcon(_isRec ? Icons.stop : Icons.fiber_manual_record, _isRec ? Colors.red : Colors.grey[800], () { setState(() => _isRec = !_isRec); if(!_isRec) _saveTrace(); }, "rec"),
            ],
          )),
          // POI BARRE (Gauche)
          Positioned(left: 10, top: 120, child: Column(children: [
            _poiBtn("fuel", Icons.local_gas_station, Colors.yellow),
            _poiBtn("water", Icons.water_drop, Colors.blue),
            _poiBtn("camp", Icons.terrain, Colors.green),
          ])),
          // BOUTONS (Droite)
          Positioned(bottom: 120, right: 15, child: Column(children: [
            _btnIcon(_isSat ? Icons.map : Icons.satellite_alt, Colors.black87, () => setState(() => _isSat = !_isSat), "sat"),
            const SizedBox(height: 10),
            _btnIcon(Icons.gps_fixed, _follow ? Colors.orange : Colors.grey[800], () => setState(() => _follow = true), "gps"),
            const SizedBox(height: 10),
            _btnIcon(Icons.settings, Colors.black87, _showSettings, "set"),
          ])),
          // DASHBOARD BAS
          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            height: 100, color: Colors.black,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _dash("${_speed.toStringAsFixed(0)}", "KM/H", Colors.orange),
              _dash("${_alt.toStringAsFixed(0)}", "ALT (M)", Colors.white),
              _dash(_getDir(_head), "CAP", Colors.cyanAccent),
            ]),
          )),
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        ],
      ),
    );
  }

  Widget _btnIcon(IconData i, Color b, VoidCallback o, String h) => FloatingActionButton(mini: true, heroTag: h, backgroundColor: b, onPressed: o, child: Icon(i, color: Colors.white));

  Widget _poiBtn(String t, IconData i, Color c) => Padding(padding: const EdgeInsets.only(bottom: 8), 
    child: FloatingActionButton(mini: true, heroTag: t, backgroundColor: _pois.any((p) => p.type == t) ? c : Colors.black87, 
    onPressed: () => _togglePOI(t), child: Icon(i, color: Colors.white)));

  IconData _poiIcon(String t) => t == 'fuel' ? Icons.local_gas_station : (t == 'water' ? Icons.water_drop : Icons.terrain);
  Color _poiColor(String t) => t == 'fuel' ? Colors.yellow : (t == 'water' ? Colors.blue : Colors.green);

  String _getDir(double h) {
    if (h < 22.5 || h >= 337.5) return "N"; if (h < 67.5) return "NE"; if (h < 112.5) return "E"; if (h < 157.5) return "SE";
    if (h < 202.5) return "S"; if (h < 247.5) return "SO"; if (h < 292.5) return "O"; return "NO";
  }
  Widget _dash(String v, String l, Color c) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(v, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);

  void _showSettings() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Contact SOS"),
      content: TextField(controller: c, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: "0612345678")),
      actions: [TextButton(onPressed: () async {
        if(c.text.isEmpty) return;
        _sosContacts = [c.text];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('sos_contacts', _sosContacts);
        Navigator.pop(ctx);
      }, child: const Text("Sauvegarder"))],
    ));
  }
}
