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

  Future<RouteData?> getOffRoadRoute(LatLng start, LatLng dest) async {
    // SCRIPT DE COÛT PERSONNALISÉ
    // On pénalise l'asphalte (coût 50) et on favorise les pistes (coût 1.1)
    const customProfile = '''
--- context:global ---
assign track_priority = 1.0
--- context:way ---
assign costfactor
  if highway=motorway|motorway_link then 100
  else if highway=trunk|trunk_link then 50
  else if highway=primary|primary_link then 30
  else if highway=secondary|secondary_link then 15
  else if highway=track then 1.1
  else if highway=service|residential|unclassified then 2.5
  else 100
''';

    final url = Uri.parse('https://brouter.de/brouter')
        .replace(queryParameters: {
      'lonlats': '${start.longitude},${start.latitude}|${dest.longitude},${dest.latitude}',
      'profile': 'moped', 
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
        
        // FIX : Erreur toDouble() - On transforme tout en String avant de parser
        final rawDist = feature['properties']['track-length'];
        final double dist = double.tryParse(rawDist.toString()) ?? 0.0;
        
        final points = coords.map((p) => LatLng(p[1], p[0])).toList();
        return RouteData(points, dist);
      }
    } catch (e) {
      print('Erreur BRouter: $e');
    }
    return null;
  }
}
