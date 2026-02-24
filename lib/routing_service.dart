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

  Future<RouteData?> getOffRoadRoute(LatLng start, LatLng dest, List<LatLng> forbiddenZones) async {
    // Formatage de tes zones interdites (rayon de 50 mètres)
    final String noGo = forbiddenZones.map((p) => '${p.longitude},${p.latitude},50').join('|');

    // PROFIL 4X4 ROAD TRIP STRICT
    // On cherche les pistes (track) larges. On limite le goudron aux liaisons.
    const customProfile = '''
--- context:global ---
assign track_priority = 0.1
--- context:way ---
assign is_track = if highway=track then 1 else 0
assign is_liaison = if highway=unclassified|tertiary|secondary then 1 else 0
assign is_bad_idea = if highway=motorway|trunk|primary|path|footway then 1 else 0

assign costfactor
  if is_bad_idea then 10000.0
  else if is_track then 1.0
  else if is_liaison then 50.0
  else 100.0
''';

    final queryParams = {
      'lonlats': '${start.longitude},${start.latitude}|${dest.longitude},${dest.latitude}',
      'profile': 'car-eco', // Base voiture pour le respect du gabarit et de la loi
      'alternativeidx': '0',
      'format': 'geojson',
      'customprofile': customProfile,
    };
    
    // Ajout de tes interdictions manuelles
    if (noGo.isNotEmpty) queryParams['nogo'] = noGo;

    try {
      final response = await http.get(Uri.parse('https://brouter.de/brouter').replace(queryParameters: queryParams));
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
