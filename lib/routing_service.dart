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
    // SCRIPT 4X4 SUR MESURE : On baisse le coût des pistes (track) 
    // et on augmente celui des routes (primary/secondary)
    const customProfile = '''
--- context:global ---
assign track_priority = 1.0
--- context:way ---
assign costfactor
  if highway=motorway|motorway_link then 100
  else if highway=trunk|trunk_link then 50
  else if highway=primary|primary_link then 20
  else if highway=secondary|secondary_link then 10
  else if highway=tertiary|tertiary_link then 5
  else if highway=track then 1.1
  else if highway=service|residential|unclassified then 2.0
  else 1000
''';

    final url = Uri.parse('https://brouter.de/brouter')
        .replace(queryParameters: {
      'lonlats': '${start.longitude},${start.latitude}|${dest.longitude},${dest.latitude}',
      'profile': 'moped', // On part du moped mais on injecte nos règles :
      'alternativeidx': '0',
      'format': 'geojson',
    }).toString() + '&customprofile=${Uri.encodeComponent(customProfile)}';
    
    try {
      final response = await http.get(Uri.parse(url));
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
