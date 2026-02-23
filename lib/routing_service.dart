import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  final String apiKey;
  
  RoutingService(this.apiKey);

  Future<List<LatLng>?> getOffRoadRoute(LatLng start, LatLng dest) async {
    final url = 'https://graphhopper.com/api/1/route?point=${start.latitude},${start.longitude}&point=${dest.latitude},${dest.longitude}&profile=car&weighting=short_fastest&key=$apiKey&points_encoded=false';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final paths = data['paths'][0];
          final points = paths['points']['coordinates'] as List;
          return points.map((p) => LatLng(p[1], p[0])).toList();
        }
      } else {
        print('Erreur API GraphHopper: ${response.statusCode}');
      }
    } catch (e) {
      print('Erreur Routing: $e');
    }
    return null;
  }
}
