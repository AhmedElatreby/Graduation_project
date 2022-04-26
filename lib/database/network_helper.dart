import 'package:http/http.dart' as http;
import 'dart:convert';


class NetworkHelper {
  NetworkHelper({required this.url, required this.auth, required this.id});
  final String url;
  final String auth;
  final String id;

  Future startTracing() async {
    http.Response response = await http.post('$url/devices/$id/start',
        body: null, headers: {'Authorization': auth});
    if (response.statusCode == 200) {
      String data = response.body;
      return jsonDecode(data);
    } else {
      print(response.statusCode);
    }
  }

  Future getData() async {
    http.Response response =
    await http.get('url/'devices'/$id', headers: {'Authorization': auth});
    if (response.statusCode == 200) {
      String data = response.body;
      return jsonDecode(data);
    } else {
      print(response.statusCode);
    }
  }

  Future endTracing() async {
    http.Response response = await http.post('$url/devices/$id/stop',
        body: null, headers: {'Authorization': auth});
    if (response.statusCode == 200) {
      String data = response.body;
      return jsonDecode(data);
    } else {
      print(response.statusCode);
    }
  }
}