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

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;

    final String lonLats = waypoints.map((p) => '${p.longitude},${p.latitude}').join('|');

    // PROFIL REVISITÉ : Base "Trekking" (cherche les chemins par défaut)
    // Mais on pénalise les "footway" (piétons) pour rester sur du carrossable
    const customProfile = '''
--- context:global ---
assign track_priority = 0.001
--- context:way ---
assign is_paved = if surface=asphalt|paved|concrete then 1 else 0
assign is_forbidden_for_4x4 = if highway=footway|path|steps then 1 else 0

assign costfactor
  if is_forbidden_for_4x4 then 9999
  else if highway=track then 1.0
  else if is_paved then 5000
  else 2.0
''';

    final url = Uri.parse('https://brouter.de/brouter').replace(queryParameters: {
      'lonlats': lonLats,
      'profile': 'trekking', // LE CHANGEMENT MAJEUR EST ICI
      'alternativeidx': '0',
      'format': 'geojson',
      'customprofile': customProfile,
    });
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feature = data['features'][0];
        final coords = feature['geometry']['coordinates'] as List;
        final double dist = double.tryParse(feature['properties']['track-length'].toString()) ?? 0.0;
        return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
      }
    } catch (e) { print('Erreur: $e'); }
    return null;
  }
}
