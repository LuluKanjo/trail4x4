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

    // Formatage des points pour BRouter
    final String lonLats = waypoints.map((p) => '${p.longitude},${p.latitude}').join('|');

    // Profil simplifié mais efficace : moped (cyclomoteur) est le plus proche du 4x4
    // car il accepte les pistes sans les restrictions trop dures des voitures.
    final url = Uri.parse('https://brouter.de/brouter?lonlats=$lonLats&profile=moped&alternativeidx=0&format=geojson');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final coords = feature['geometry']['coordinates'] as List;
          final double dist = double.tryParse(feature['properties']['track-length']?.toString() ?? '0') ?? 0.0;
          return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
        }
      }
    } catch (e) {
      print('Erreur BRouter: $e');
    }
    return null;
  }
}
