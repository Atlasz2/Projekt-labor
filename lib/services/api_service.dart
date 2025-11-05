import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip.dart';
import '../models/point_of_interest.dart';
import '../models/point_content.dart';
import '../models/review.dart';
import '../models/user.dart';

class ApiService {
  final String baseUrl;
  ApiService(this.baseUrl);

  Future<List<Trip>> getTrips() async {
    final response = await http.get(Uri.parse('$baseUrl/api/trips'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => Trip.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load trips');
    }
  }

  Future<List<PointOfInterest>> getPointsOfInterest(int tripId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/points-of-interest?tripId=$tripId'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => PointOfInterest.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load points of interest');
    }
  }

  Future<List<PointContent>> getPointContents(int pointId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/point-contents?pointId=$pointId'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => PointContent.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load point contents');
    }
  }

  Future<List<Review>> getReviews(int pointId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/reviews?pointId=$pointId'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => Review.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load reviews');
    }
  }

  Future<User> getUser(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/users/$userId'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return User.fromJson(data);
    } else {
      throw Exception('Failed to load user');
    }
  }
}
