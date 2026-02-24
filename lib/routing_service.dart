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
    final url = 'https://brouter.de/brouter?lonlats=${start.longitude},${start.latitude}|${dest.longitude},${dest.latitude}&profile=car-eco&alternativeidx=0&format=geojson';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final feature = data['features'][0];
        final coords = feature['geometry']['coordinates'] as List;
        
        // LA CORRECTION EST ICI : on force la transformation du texte en nombre
        final rawDist = feature['properties']['track-length'];
        final double dist = double.parse(rawDist.toString());
        
        final points = coords.map((p) => LatLng(p[1], p[0])).toList();
        return RouteData(points, dist);
      }
    } catch (e) {
      print('Erreur BRouter: $e');
    }
    return null;
  }
}
