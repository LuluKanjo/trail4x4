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
import 'weather_service.dart';
import 'poi_service.dart';
import 'routing_service.dart';

void main() => runApp(const Trail4x4App());

class Trail4x4App extends StatelessWidget {
  const Trail4x4App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MapScreen(
        weatherKey: '40ec667fbf278cf67533b2c70d799dd1',
        tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso',
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  final String weatherKey;
  final String tomtomKey;
  const MapScreen({super.key, required this.weatherKey, required this.tomtomKey});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(46.603354, 1.888334);
  double _speed = 0, _altitude = 0, _totalDist = 0;
  LatLng? _lastPos;
  bool _followMe = true, _isSatellite = false, _isRecording = false;
  
  String _weatherText = "Météo...";
  final List<POI> _pois = [];
  final List<LatLng> _trace = [];
  List<LatLng> _route = [];
  double _remainingDist = 0;
  bool _loading = false;

  late WeatherService _weatherService;
  late POIService _poiService;
  late RoutingService _routingService;

  @override
  void initState() {
    super.initState();
    _weatherService = WeatherService(widget.weatherKey);
    _poiService = POIService(tomtomKey: widget.tomtomKey);
    _routingService = RoutingService('');
    _startTracking();
    _updateWeather();
  }

  void _startTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2))
    .listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _speed = pos.speed * 3.6;
        _altitude = pos.altitude;
        if (_lastPos != null) {
          _totalDist += const Distance().as(LengthUnit.Kilometer, _lastPos!, _currentPosition);
        }
        _lastPos = _currentPosition;
        if (_isRecording) _trace.add(_currentPosition);
        if (_route.isNotEmpty) {
          _remainingDist = const Distance().as(LengthUnit.Meter, _currentPosition, _route.last);
        }
      });
      if (_followMe) _mapController.move(_currentPosition, _mapController.camera.zoom);
    });
  }

  Future<void> _updateWeather() async {
    final data = await _weatherService.getWeather(_currentPosition.latitude, _currentPosition.longitude);
    if (data != null) {
      setState(() => _weatherText = "${data['main']['temp'].toStringAsFixed(0)}°C | ${data['weather'][0]['description']}");
    }
  }

  Future<void> _togglePOI(String type) async {
    setState(() => _loading = true);
    final results = await _poiService.fetchPOIs(_currentPosition.latitude, _currentPosition.longitude, type);
    setState(() { _pois.addAll(results); _loading = false; });
  }

  Future<void> _sendSOS() async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = prefs.getStringList('sos_contacts') ?? [];
    for (var c in contacts) {
      final uri = Uri.parse('sms:$c?body=URGENCE 4x4! Ma position: https://www.google.com/maps?q=${_currentPosition.latitude},${_currentPosition.longitude}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }
  }

  Future<void> _saveGPX() async {
    if (_trace.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/trace_${DateTime.now().millisecondsSinceEpoch}.gpx');
    final buffer = StringBuffer()..writeln('<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1"><trk><trkseg>');
    for (final p in _trace) { buffer.writeln('<trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>'); }
    buffer.writeln('</trkseg></trk></gpx>');
    await file.writeAsString(buffer.toString());
  }

  Future<void> _calculateRoute(String destName) async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/search?q=$destName&format=json&limit=1'), headers: {'User-Agent': 'Trail4x4-Lulu'});
      final data = json.decode(res.body);
      if (data.isNotEmpty) {
        final dest = LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
        final routeData = await _routingService.getOffRoadRoute(_currentPosition, dest);
        if (routeData != null) {
          setState(() { _route = routeData.points; _remainingDist = routeData.distance; _followMe = true; });
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
            options: MapOptions(initialCenter: _currentPosition, initialZoom: 15, onPositionChanged: (p, g) { if(g) setState(() => _followMe = false); }),
            children: [
              TileLayer(
                userAgentPackageName: 'com.trail4x4.app',
                urlTemplate: _isSatellite 
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (_route.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _route, color: Colors.cyan, strokeWidth: 6)]),
              if (_trace.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _trace, color: Colors.orange, strokeWidth: 4)]),
              MarkerLayer(markers: [
                ..._pois.map((p) => Marker(point: p.position, child: const Icon(Icons.place, color: Colors.yellow, size: 30))),
                Marker(point: _currentPosition, width: 50, height: 50, child: const Icon(Icons.navigation, color: Colors.orange, size: 45)),
              ]),
            ],
          ),
          Positioned(top: 50, left: 15, right: 15, child: Column(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.cloud, size: 18, color: Colors.cyan),
                const SizedBox(width: 8),
                Text(_weatherText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
            ),
            if (_route.isNotEmpty) const SizedBox(height: 10),
            if (_route.isNotEmpty) Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
              child: Text("${(_remainingDist/1000).toStringAsFixed(1)} KM", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ])),
          Positioned(bottom: 110, right: 15, child: Column(children: [
            FloatingActionButton(heroTag: "reset", mini: true, onPressed: () => setState(() { _trace.clear(); _route = []; _remainingDist = 0; }), backgroundColor: Colors.black87, child: const Icon(Icons.delete_sweep, color: Colors.white)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "rec", mini: true, onPressed: () { setState(() => _isRecording = !_isRecording); if(!_isRecording) _saveGPX(); }, backgroundColor: _isRecording ? Colors.red : Colors.black87, child: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "sat", mini: true, onPressed: () => setState(() => _isSatellite = !_isSatellite), backgroundColor: Colors.black87, child: Icon(_isSatellite ? Icons.map : Icons.satellite_alt)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "gps", onPressed: () => setState(() => _followMe = true), backgroundColor: _followMe ? Colors.orange : Colors.grey[900], child: const Icon(Icons.gps_fixed)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "dest", onPressed: () {
              final c = TextEditingController();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Destination"),
                content: TextField(controller: c, decoration: const InputDecoration(hintText: "Ville")),
                actions: [TextButton(onPressed: () { _calculateRoute(c.text); Navigator.pop(ctx); }, child: const Text("GO"))],
              ));
            }, backgroundColor: Colors.cyan[700], child: const Icon(Icons.search)),
          ])),
          Positioned(bottom: 110, left: 15, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FloatingActionButton(heroTag: "sos", mini: true, onPressed: _sendSOS, backgroundColor: Colors.red[900], child: const Text("SOS")),
            const SizedBox(height: 12),
            _poiBtn("Essence", "fuel", Icons.local_gas_station),
            const SizedBox(height: 8),
            _poiBtn("Bivouac", "camp", Icons.cabin),
          ])),
          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            height: 90, color: Colors.black,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _dash("VITESSE", _speed.toStringAsFixed(0), "km/h"),
              _dash("ALTITUDE", _altitude.toStringAsFixed(0), "m"),
              _dash("TRIP", _totalDist.toStringAsFixed(1), "km"),
            ]),
          )),
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.cyan)),
        ],
      ),
    );
  }
  Widget _dash(String l, String v, String u) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.orange)),
    Text("$l ($u)", style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
  Widget _poiBtn(String l, String t, IconData i) => ElevatedButton.icon(
    onPressed: () => _togglePOI(t),
    icon: Icon(i, size: 16), label: Text(l, style: const TextStyle(fontSize: 12)),
    style: ElevatedButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.6)),
  );
}
