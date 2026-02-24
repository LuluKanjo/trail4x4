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
    // PROFIL RAID 4X4 : Inspiré des meilleurs fichiers OsmAnd
    // On favorise : tracktype grade1/2/3, surface=unpaved/gravel/earth
    // On pénalise lourdement : asphalt, concrete, et les axes principaux
    const customProfile = '''
--- context:global ---
assign track_priority = 0.05
--- context:way ---
assign is_unpaved = if surface=unpaved|gravel|dirt|earth|ground then 1 else 0
assign is_track = if highway=track then 1 else 0

assign costfactor
  if is_track then (if tracktype=grade1|grade2|grade3 then 1.0 else 1.5)
  else if surface=asphalt|paved|concrete then 100.0
  else if highway=motorway|trunk|primary then 500.0
  else if highway=secondary|tertiary then 50.0
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
        final double dist = double.tryParse(feature['properties']['track-length'].toString()) ?? 0.0;
        return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
      }
    } catch (e) { print('Erreur: $e'); }
    return null;
  }
}
