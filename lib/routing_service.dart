import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  RoutingService(String _); 

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints, List<LatLng> avoidPoints) async {
    if (waypoints.length < 2) return null;

    final String lonLats = waypoints.map((p) => '${p.longitude},${p.latitude}').join('|');
    final String blocks = avoidPoints.map((p) => '${p.longitude},${p.latitude},50').join('|');

    // SCRIPT DEFENDER 110 : 
    // On accepte tout ce qui est 'track' (piste) mais on fuit les 'path' (sentiers étroits).
    const customProfile = '''
--- context:global ---
assign track_priority = 0.1
--- context:way ---

# Définition d'une piste praticable pour un 4x4
assign is_4x4_track = if highway=track then 1 else 0
# On évite les sentiers de randonnée (trop étroits)
assign is_too_narrow = if highway=path|footway|bridleway then 1 else 0

assign costfactor
  if is_too_narrow then 1000
  else if is_4x4_track then 1.0
  else if highway=motorway|motorway_link|trunk|trunk_link then 500
  else if highway=primary|secondary then 200
  else if highway=tertiary|unclassified then 10
  else 2.0
''';

    final queryParams = {
      'lonlats': lonLats,
      'profile': 'moped', 
      'alternativeidx': '0',
      'format': 'geojson',
      'customprofile': customProfile,
    };
    
    if (blocks.isNotEmpty) queryParams['bookings'] = blocks; 

    final url = Uri.parse('https://brouter.de/brouter').replace(queryParameters: queryParams);
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feature = data['features'][0];
        final coords = feature['geometry']['coordinates'] as List;
        final double dist = double.tryParse(feature['properties']['track-length'].toString()) ?? 0.0;
        return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
      }
    } catch (e) { print('Erreur BRouter: $e'); }
    return null;
  }
}
