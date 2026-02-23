import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';

class RoutingService {
  final String apiKey;
  RoutingService(this.apiKey);

  Future<List<LatLng>?> getOffRoadRoute(LatLng start, LatLng end) async {
    try {
      final url = 'https://graphhopper.com/api/1/route'
          '?point=${start.latitude},${start.longitude}'
          '&point=${end.latitude},${end.longitude}'
          '&vehicle=car'
          '&weighting=short_fastest'
          '&locale=fr'
          '&points_encoded=false'
          '&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['paths'][0]['points']['coordinates'] as List;
        return coords
            .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
