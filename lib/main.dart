import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  LatLng _currentPosition = const LatLng(46.603354, 1.888334);
  double _speed = 0;
  double _altitude = 0;
  double _distance = 0;
  LatLng? _lastPosition;
  List<String> _sosContacts = [];

  @override
  void initState() {
    super.initState();
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

  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

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
      });
      _mapController.move(_currentPosition, _mapController.camera.zoom);
    });
  }

  void _sendSOS() async {
    if (_sosContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun contact SOS. Ajoutez des contacts dans les paramètres.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final message =
        'URGENT - J\'ai besoin d\'aide ! Ma position GPS : https://maps.google.com/?q=${_currentPosition.latitude},${_currentPosition.longitude}';

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
                      decoration: const InputDecoration(
                          hintText: '+33612345678'),
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
              MarkerLayer(
                markers: [
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
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Trail 4x4',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.contacts, color: Colors.orange),
                    onPressed: _showContactsDialog,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 140,
            child: FloatingActionButton(
              onPressed: () =>
                  _mapController.move(_currentPosition, 15),
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
                      '${_distance.toStringAsFixed(2)} km', Icons.straighten),
                ],
              ),
            ),
          ),
        ],
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
}
