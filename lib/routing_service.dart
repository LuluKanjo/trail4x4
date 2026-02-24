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

    // OSRM demande la longitude en premier : lon,lat;lon,lat
    final String coordinates = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');

    // MOTEUR OSRM - Profil VÉLO (bike)
    // Il est d'une stabilité à toute épreuve et s'engouffre dans tous les pointillés marrons.
    final url = 'https://router.project-osrm.org/route/v1/bike/$coordinates?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;
          final double dist = (route['distance'] as num).toDouble();

          // OSRM renvoie [longitude, latitude], on convertit pour Flutter
          final List<LatLng> points = geometry.map((p) => LatLng(p[1], p[0])).toList();
          return RouteData(points, dist);
        }
      } else {
        debugPrint("Erreur OSRM: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Erreur réseau: $e");
    }
    
    return null;
  }
}
