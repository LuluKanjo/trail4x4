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
  bool _followMe = true, _isSatellite = false, _loading = false;
  
  String _weatherText = "Météo...";
  final List<POI> _pois = [];
  List<LatLng> _route = [];
  double _remainingDist = 0;

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

  void _showLog(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), 
      backgroundColor: err ? Colors.red : Colors.blueGrey[800],
      duration: const Duration(seconds: 3),
    ));
  }

  void _startTracking() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2))
    .listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _speed = pos.speed * 3.6;
        _altitude = pos.altitude;
        _lastPos ??= _currentPosition;
        _totalDist += const Distance().as(LengthUnit.Kilometer, _lastPos!, _currentPosition);
        _lastPos = _currentPosition;
      });
      if (_followMe) _mapController.move(_currentPosition, _mapController.camera.zoom);
    });
  }

  Future<void> _updateWeather() async {
    try {
      final data = await _weatherService.getWeather(_currentPosition.latitude, _currentPosition.longitude);
      if (data != null) setState(() => _weatherText = "${data['main']['temp'].toStringAsFixed(0)}°C | ${data['weather'][0]['description']}");
    } catch (e) { debugPrint("Weather error"); }
  }

  Future<void> _togglePOI(String type) async {
    _showLog("Recherche $type à proximité...");
    setState(() => _loading = true);
    try {
      final results = await _poiService.fetchPOIs(_currentPosition.latitude, _currentPosition.longitude, type);
      setState(() { _pois.addAll(results); _loading = false; });
      _showLog("${results.length} points trouvés !");
    } catch (e) {
      setState(() => _loading = false);
      _showLog("Erreur POI : $e", err: true);
    }
  }

  Future<void> _calculateRoute(String destName) async {
    if (destName.isEmpty) return;
    _showLog("Recherche du village : $destName...");
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?q=$destName&format=json&limit=1'),
        headers: {'User-Agent': 'Trail4x4-Lulu-Diagnostic'}
      ).timeout(const Duration(seconds: 10));
      
      final data = json.decode(res.body);
      if (data.isEmpty) {
        _showLog("Village non trouvé sur la carte", err: true);
      } else {
        final dest = LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
        _showLog("Calcul de la trace Off-Road...");
        final routeData = await _routingService.getOffRoadRoute(_currentPosition, dest);
        
        if (routeData != null) {
          setState(() { _route = routeData.points; _remainingDist = routeData.distance; _followMe = true; });
          _mapController.fitCamera(CameraFit.coordinates(coordinates: [_currentPosition, dest], padding: const EdgeInsets.all(50)));
          _showLog("Trace générée avec succès !");
        }
      }
    } catch (e) {
      _showLog("Erreur calcul : $e", err: true);
    }
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
              MarkerLayer(markers: [
                ..._pois.map((p) => Marker(point: p.position, child: const Icon(Icons.place, color: Colors.yellow, size: 30))),
                Marker(point: _currentPosition, width: 50, height: 50, child: const Icon(Icons.navigation, color: Colors.orange, size: 45)),
              ]),
            ],
          ),
          // Interface
          Positioned(top: 50, left: 15, right: 15, child: Column(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)), child: Text(_weatherText)),
            if (_route.isNotEmpty) const SizedBox(height: 10),
            if (_route.isNotEmpty) Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.cyan[800], borderRadius: BorderRadius.circular(12)), child: Text("${(_remainingDist/1000).toStringAsFixed(1)} KM", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          ])),
          // Boutons
          Positioned(bottom: 110, right: 15, child: Column(children: [
            FloatingActionButton(heroTag: "sat", mini: true, onPressed: () => setState(() => _isSatellite = !_isSatellite), backgroundColor: Colors.black87, child: Icon(_isSatellite ? Icons.map : Icons.satellite_alt)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "gps", onPressed: () => setState(() => _followMe = true), backgroundColor: _followMe ? Colors.orange : Colors.grey[900], child: const Icon(Icons.gps_fixed)),
            const SizedBox(height: 12),
            FloatingActionButton(heroTag: "dest", onPressed: () {
              final c = TextEditingController();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Destination"),
                content: TextField(controller: c, decoration: const InputDecoration(hintText: "Nom du village")),
                actions: [TextButton(onPressed: () { Navigator.pop(ctx); _calculateRoute(c.text); }, child: const Text("LANCER"))],
              ));
            }, backgroundColor: Colors.cyan[700], child: const Icon(Icons.search)),
          ])),
          Positioned(bottom: 110, left: 15, child: Column(children: [
            _poiBtn("Essence", "fuel", Icons.local_gas_station),
            const SizedBox(height: 10),
            _poiBtn("Bivouac", "camp", Icons.cabin),
          ])),
          // Stats
          Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 90, color: Colors.black, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _dash("KM/H", _speed.toStringAsFixed(0)),
            _dash("ALTITUDE", _altitude.toStringAsFixed(0)),
            _dash("TRIP", _totalDist.toStringAsFixed(1)),
          ]))),
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.cyan)),
        ],
      ),
    );
  }
  Widget _dash(String l, String v) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.orange)), Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey))]);
  Widget _poiBtn(String l, String t, IconData i) => FloatingActionButton(heroTag: t, mini: true, onPressed: () => _togglePOI(t), backgroundColor: Colors.black87, child: Icon(i, size: 20));
}
