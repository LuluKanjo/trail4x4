import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  RoutingService(String _); 

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints, List<LatLng> forbiddenZones) async {
    if (waypoints.length < 2) return null;

    final String lonLats = waypoints.map((p) => '${p.longitude},${p.latitude}').join('|');
    final String noGo = forbiddenZones.map((p) => '${p.longitude},${p.latitude},50').join('|');

    // LE SECRET : Le profil "bicycle" passe sur tous les chemins de terre, même "interdits" aux moteurs.
    String url = 'https://brouter.de/brouter?lonlats=$lonLats&profile=bicycle&alternativeidx=0&format=geojson';
    if (noGo.isNotEmpty) url += '&nogo=$noGo';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final coords = feature['geometry']['coordinates'] as List;
          final double dist = double.tryParse(feature['properties']['track-length'].toString()) ?? 0.0;
          return RouteData(coords.map((p) => LatLng(p[1], p[0])).toList(), dist);
        }
      } else {
        debugPrint("Erreur BRouter: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Erreur réseau: $e");
    }
    return null; 
  }
}
