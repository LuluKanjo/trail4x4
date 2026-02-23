import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'weather_service.dart';
import 'poi_service.dart';

void main() {
  runApp(const Trail4x4App());
}

class Trail4x4App extends StatelessWidget {
  const Trail4x4App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trail 4x4',
      theme: ThemeData.dark(),
      home: const MapScreen(weatherKey: '40ec667fbf278cf67533b2c70d799dd1'),
    );
  }
}

class MapScreen extends StatefulWidget {
  final String weatherKey;
  const MapScreen({super.key, required this.weatherKey});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(46.603354, 1.888334);
  double _speed = 0;
  double _altitude = 0;
  double _distance = 0;
  LatLng? _lastPosition;
  List<String> _sosContacts = [];
  bool _isRecording = false;
  List<LatLng> _trace = [];
  List<LatLng> _tracePoints = [];
  String _weatherDesc = '';
  double _weatherTemp = 0;
  double _windSpeed = 0;
  late WeatherService _weatherService;
  final POIService _poiService = POIService(tomtomKey: 'kjkV5wefMwSb5teOLQShx23C6wnmygso');
  List<POI> _pois = [];
  bool _showFuel = false;
  bool _showWater = false;
  bool _showCamp = false;
  bool _loadingPOI = false;

  @override
  void initState() {
    super.initState();
    _weatherService = WeatherService(widget.weatherKey);
    _startTracking();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sosContacts = prefs.getStringList('sos_contacts') ?? [];
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sos_contacts', _sosContacts);
  }

  Future<void> _updateWeather() async {
    final data = await _weatherService.getWeather(
        _currentPosition.latitude, _currentPosition.longitude);
    if (data != null) {
      setState(() {
        _weatherDesc = data['weather'][0]['description'];
        _weatherTemp = data['main']['temp'].toDouble();
        _windSpeed = data['wind']['speed'].toDouble();
      });
    }
  }

  Future<void> _togglePOI(String type) async {
    bool current = false;
    if (type == 'fuel') current = _showFuel;
    if (type == 'water') current = _showWater;
    if (type == 'camp') current = _showCamp;
    if (current) {
      setState(() {
        _pois.removeWhere((p) => p.type == type);
        if (type == 'fuel') _showFuel = false;
        if (type == 'water') _showWater = false;
        if (type == 'camp') _showCamp = false;
      });
      return;
    }
    setState(() => _loadingPOI = true);
    final pois = await _poiService.fetchPOIs(
        _currentPosition.latitude, _currentPosition.longitude, type);
    setState(() {
      _pois.addAll(pois);
      if (type == 'fuel') _showFuel = true;
      if (type == 'water') _showWater = true;
      if (type == 'camp') _showCamp = true;
      _loadingPOI = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${pois.length} points trouves !'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    _updateWeather();
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _speed = position.speed * 3.6;
        _altitude = position.altitude;
        if (_lastPosition != null) {
          final Distance calculator = Distance();
          _distance += calculator.as(
            LengthUnit.Kilometer,
            _lastPosition!,
            _currentPosition,
          );
        }
        _lastPosition = _currentPosition;
        if (_isRecording) {
          _tracePoints.add(_currentPosition);
          _trace.add(_currentPosition);
        }
      });
      _mapController.move(_currentPosition, _mapController.camera.zoom);
    });
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _saveGPX();
      setState(() => _isRecording = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Trace enregistree !'),
              backgroundColor: Colors.green),
        );
      }
    } else {
      setState(() {
        _isRecording = true;
        _tracePoints = [];
        _distance = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Enregistrement demarre !'),
              backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _saveGPX() async {
    if (_tracePoints.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final filename =
        'trace_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.gpx';
    final file = File('${dir.path}/$filename');
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="Trail4x4">');
    buffer.writeln('<trk><name>Trail 4x4</name><trkseg>');
    for (final point in _tracePoints) {
      buffer.writeln(
          '<trkpt lat="${point.latitude}" lon="${point.longitude}"></trkpt>');
    }
    buffer.writeln('</trkseg></trk></gpx>');
    await file.writeAsString(buffer.toString());
  }

  void _sendSOS() async {
    if (_sosContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ajoutez des contacts SOS.'),
            backgroundColor: Colors.red),
      );
      return;
    }
    final message =
        'URGENT - besoin aide ! Position : https://maps.google.com/?q=${_currentPosition.latitude},${_currentPosition.longitude}';
    for (final contact in _sosContacts) {
      final uri = Uri(
        scheme: 'sms',
        path: contact,
        queryParameters: {'body': message},
      );
      await launchUrl(uri);
    }
  }

  void _showContactsDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Contacts SOS'),
          backgroundColor: Colors.brown[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._sosContacts.map((c) => ListTile(
                    title: Text(c),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setDialogState(() => _sosContacts.remove(c));
                        setState(() {});
                        _saveContacts();
                      },
                    ),
                  )),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(hintText: '+33612345678'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.orange),
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        setDialogState(
                            () => _sosContacts.add(controller.text));
                        setState(() {});
                        _saveContacts();
                        controller.clear();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer',
                  style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poiMarker(POI poi) {
    IconData icon;
    Color color;
    switch (poi.type) {
      case 'fuel':
        icon = Icons.local_gas_station;
        color = Colors.yellow;
        break;
      case 'water':
        icon = Icons.water_drop;
        color = Colors.blue;
        break;
      case 'camp':
        icon = Icons.cabin;
        color = Colors.green;
        break;
      default:
        icon = Icons.place;
        color = Colors.white;
    }
    return Icon(icon, color: color, size: 28);
  }

  Widget _poiButton(String label, String type, bool active) {
    return GestureDetector(
      onTap: () => _togglePOI(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.orange : Colors.white30,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.orange : Colors.white70,
                fontSize: 12)),
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.orange, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trail4x4.app',
              ),
              if (_trace.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trace,
                      color: Colors.orange,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  ..._pois.map((poi) => Marker(
                        point: poi.position,
                        width: 30,
                        height: 30,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(poi.name),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: _poiMarker(poi),
                        ),
                      )),
                  Marker(
                    point: _currentPosition,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.navigation,
                        color: Colors.orange, size: 40),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.brown[900]!.withValues(alpha: 0.9),
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Trail 4x4',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _isRecording
                                  ? Icons.stop_circle
                                  : Icons.fiber_manual_record,
                              color: _isRecording
                                  ? Colors.red
                                  : Colors.orange,
                            ),
                            onPressed: _toggleRecording,
                          ),
                          IconButton(
                            icon: const Icon(Icons.contacts,
                                color: Colors.orange),
                            onPressed: _showContactsDialog,
                          ),
                          IconButton(
                            icon: const Icon(Icons.cloud,
                                color: Colors.orange),
                            onPressed: _updateWeather,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_weatherDesc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('${_weatherTemp.toStringAsFixed(0)}C',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          Text('${_windSpeed.toStringAsFixed(0)} m/s',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          Text(_weatherDesc,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _poiButton('Essence', 'fuel', _showFuel),
                      _poiButton('Eau', 'water', _showWater),
                      _poiButton('Bivouac', 'camp', _showCamp),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loadingPOI)
            const Center(child: CircularProgressIndicator()),
          Positioned(
            right: 16,
            bottom: 140,
            child: FloatingActionButton(
              onPressed: () => _mapController.move(_currentPosition, 15),
              backgroundColor: Colors.brown[800],
              child: const Icon(Icons.gps_fixed),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 140,
            child: FloatingActionButton(
              onPressed: _sendSOS,
              backgroundColor: Colors.red[800],
              child: const Text('SOS',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.brown[900]!.withValues(alpha: 0.9),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Vitesse',
                      '${_speed.toStringAsFixed(0)} km/h', Icons.speed),
                  _buildStat('Altitude',
                      '${_altitude.toStringAsFixed(0)} m', Icons.terrain),
                  _buildStat('Distance',
                      '${_distance.toStringAsFixed(2)} km',
                      Icons.straighten),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
