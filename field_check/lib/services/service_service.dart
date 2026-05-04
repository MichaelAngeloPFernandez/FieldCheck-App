import 'package:field_check/config/api_config.dart';
import 'package:field_check/models/service_model.dart';
import 'package:field_check/services/user_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ServiceService {
  final UserService _userService = UserService();

  Future<String?> _getToken() async {
    return await _userService.getToken();
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Create a new service
  Future<Service> createService({
    required String name,
    String? description,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/services'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'description': description,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Service.fromJson(data['data'] ?? data);
      } else {
        throw Exception('Failed to create service: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating service: $e');
    }
  }

  /// Get all services for the company
  Future<List<Service>> getServices({
    bool? isActive,
    String? sort,
  }) async {
    try {
      final headers = await _getHeaders();
      final queryParams = <String, String>{};
      if (isActive != null) {
        queryParams['isActive'] = isActive.toString();
      }
      if (sort != null) {
        queryParams['sort'] = sort;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/services')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> services = data['data'] ?? data;
        return services
            .map((s) => Service.fromJson(s as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to fetch services: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching services: $e');
    }
  }

  /// Get a specific service by ID
  Future<Service> getServiceById(String serviceId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/services/$serviceId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Service.fromJson(data['data'] ?? data);
      } else {
        throw Exception('Failed to fetch service: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching service: $e');
    }
  }

  /// Update a service
  Future<Service> updateService({
    required String serviceId,
    required String name,
    String? description,
    bool? isActive,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/services/$serviceId'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'description': description,
          'isActive': isActive,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Service.fromJson(data['data'] ?? data);
      } else {
        throw Exception('Failed to update service: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating service: $e');
    }
  }

  /// Delete a service
  Future<void> deleteService(String serviceId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/services/$serviceId'),
        headers: headers,
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete service: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting service: $e');
    }
  }
}
