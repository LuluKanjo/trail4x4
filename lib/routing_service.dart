import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RouteData {
  final List<LatLng> points;
  final double distance;
  RouteData(this.points, this.distance);
}

class RoutingService {
  final String apiKey;
  RoutingService(this.apiKey);

  Future<RouteData?> getOffRoadRoute(List<LatLng> waypoints, List<LatLng> avoid, {String profile = 'car'}) async {
    try {
      final coords = waypoints.map((w) => '${w.longitude},${w.latitude}').join(';');
      final url = 'https://router.project-osrm.org/route/v1/$profile/$coords?overview=full&geometries=polyline';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] == null || data['routes'].isEmpty) return null;
        final String encodedPoly = data['routes'][0]['geometry'];
        final double dist = data['routes'][0]['distance'].toDouble();
        return RouteData(_decodePolyline(encodedPoly), dist);
      }
    } catch (e) {
      print("Erreur routage: $e");
    }
    return null;
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1)); lat += dlat;
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1)); lng += dlng;
      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }
}
