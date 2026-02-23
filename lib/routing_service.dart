import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteData {
  final List<LatLng> points;
  final List<dynamic> instructions;
  RouteData(this.points, this.instructions);
}

class RoutingService {
  final String apiKey;
  
  RoutingService(this.apiKey);

  Future<RouteData?> getOffRoadRoute(LatLng start, LatLng dest) async {
    // Utilisation du profil "bike" (activé par défaut) pour forcer le hors-piste
    final url = 'https://graphhopper.com/api/1/route?point=${start.latitude},${start.longitude}&point=${dest.latitude},${dest.longitude}&profile=bike&key=$apiKey&instructions=true&points_encoded=false';

    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final paths = data['paths'][0];
          final coords = paths['points']['coordinates'] as List;
          final points = coords.map((p) => LatLng(p[1], p[0])).toList();
          final instructions = paths['instructions'] as List<dynamic>;
          return RouteData(points, instructions);
        }
      } else {
        // En cas d'erreur, on capture la réponse exacte de GraphHopper
        return RouteData([start, dest], [{'text': 'ERREUR ${response.statusCode}: ${response.body}', 'interval': [0, 1]}]);
      }
    } catch (e) {
      return RouteData([start, dest], [{'text': 'CRASH INTERNE: $e', 'interval': [0, 1]}]);
    }
    return null;
  }
}
