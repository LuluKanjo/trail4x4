import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherService {
  Future<String> getCurrentWeather(double lat, double lon) async {
    final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current_weather']['temperature'];
        return "${(temp as num).round()}°C";
      }
    } catch (e) {
      debugPrint("Erreur météo: $e");
    }
    return "--°C";
  }
}
