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
    // SCRIPT RADICAL : On force le passage sur piste (highway=track)
    // On ignore les pénalités de surface pour ne pas bloquer le 4x4
    const customProfile = '''
--- context:global ---
assign track_priority = 0.1
--- context:way ---
assign costfactor
  if highway=track then 1.0
  else if highway=motorway|motorway_link|trunk|trunk_link then 80
  else if highway=primary|primary_link|secondary|secondary_link then 40
  else if highway=tertiary|tertiary_link|unclassified then 10
  else if highway=service|residential then 5
  else 2.0
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
        final rawDist = feature['properties']['track-length'];
        final double dist = double.tryParse(rawDist.toString()) ?? 0.0;
        return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
      }
    } catch (e) { print('Erreur BRouter: $e'); }
    return null;
  }
}
