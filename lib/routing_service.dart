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
    final String noGo = forbiddenZones.map((p) => '${p.longitude},${p.latitude},50').join('|');

    // LE PROFIL "LIBERTÉ TOTALE"
    // On ignore les lois (grâce à la base vélo)
    // On détruit le score du goudron, on valorise la terre à 100%
    // On s'assure juste de ne pas finir sur un sentier piéton (footway/path)
    const customProfile = '''
--- context:global ---
assign track_priority = 1.0
--- context:way ---
assign is_paved = if surface=asphalt|paved|concrete then 1 else 0
assign is_too_small = if highway=path|footway|steps|pedestrian|cycleway then 1 else 0

assign costfactor
  if is_too_small then 10000.0
  else if highway=track then 1.0
  else if is_paved then 5000.0
  else if highway=motorway|trunk|primary|secondary then 10000.0
  else 10.0
''';

    final queryParams = {
      'lonlats': '${start.longitude},${start.latitude}|${dest.longitude},${dest.latitude}',
      // LE SECRET EST ICI : Le profil vélo voit TOUS les chemins forestiers
      'profile': 'bicycle', 
      'alternativeidx': '0',
      'format': 'geojson',
      'customprofile': customProfile,
    };
    
    // On intègre tes propres zones interdites posées à la main
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
    } catch (e) { print('Erreur BRouter: $e'); }
    return null;
  }
}
