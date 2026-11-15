import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/plant.dart';
import 'cache_service.dart';

class ApiService {
  static const String _baseUrl = 'https://plantsage-backend-production.up.railway.app';

  /// True when the last data load fell back to the local cache.
  static bool isOffline = false;

  /// Public base URL for widgets that need to build URLs directly.
  static String get baseUrl => _baseUrl;

  /// Returns an HTTP client that bypasses any system proxy for loopback requests.
  static http.Client _directClient() {
    final ioClient = HttpClient()..findProxy = (_) => 'DIRECT';
    return IOClient(ioClient);
  }

  /// Public accessor for widgets that need a direct client.
  static http.Client directClient() => _directClient();

  /// Returns a tuple: (Plant model, raw JSON map for chat)
  static Future<(Plant, Map<String, dynamic>)> identifyPlant(
    File imageFile, {
    String imagePath = '',
    bool forceRescan = false,
    List<Map<String, String>> additionalImages = const [],  // [{image: base64, type: 'leaf|stem|flower'}]
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final client = _directClient();
    final http.Response response;
    try {
      final body = <String, dynamic>{
        'image': base64Image,
        'image_path': imagePath,
        if (forceRescan) 'force_rescan': true,
        if (additionalImages.isNotEmpty)
          'additional_images': additionalImages,
      };
      response = await client.post(
        Uri.parse('$_baseUrl/identify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } finally {
      client.close();
    }

    if (response.statusCode == 200) {
      final raw = jsonDecode(response.body) as Map<String, dynamic>;
      return (Plant.fromJson(raw), raw);
    } else {
      // Show status code + first 200 chars for debugging
      final preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      try {
        final error = jsonDecode(response.body);
        throw Exception('${response.statusCode}: ${error['detail'] ?? 'Server error ${response.statusCode}'}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('HTTP ${response.statusCode}: $preview');
      }
    }
  }

  static Future<String> chatWithExpert({
    required Map<String, dynamic> plantData,
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final client = _directClient();
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'plant_data': plantData,
          'message': message,
          'history': history,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['reply'] as String;
      }
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Chat error ${response.statusCode}');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> getGardenProfile() async {
    final client = _directClient();
    try {
      final response = await client.get(Uri.parse('$_baseUrl/garden-profile'));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<void> saveGardenProfile(Map<String, dynamic> profile) async {
    final client = _directClient();
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/garden-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(profile),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to save profile: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<List<dynamic>> getHistory() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/history'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await CacheService.save('history', data);
        isOffline = false;
        return data;
      }
    } catch (_) {
      final cached = await CacheService.load('history');
      if (cached != null) {
        isOffline = true;
        // Normalize stale cached entries: derive suitability_score from the JSON
        // gardenability_score (the single enforced source of truth), so even old cache
        // data shows the correct score and band rather than a pre-enforcement value.
        _normalizeHistoryScores(cached);
        return cached;
      }
    } finally {
      client.close();
    }
    isOffline = false;
    return [];
  }

  /// For every history item, replace [suitability_score] with the
  /// [gardenability_score] found inside the [details] JSON blob (if available),
  /// and re-derive [pet_safety_status] from the stored health object.
  /// This prevents stale cache values appearing after the backend DB is patched.
  static void _normalizeHistoryScores(List<dynamic> items) {
    for (final item in items) {
      if (item is! Map) continue;
      final raw = item['details'];
      if (raw == null) continue;
      try {
        final d = jsonDecode(raw as String);
        if (d is Map) {
          // Score normalization
          final gs = d['gardenability_score'];
          if (gs != null) {
            item['suitability_score'] = gs;
            item['gardenability_score'] = gs;
          }
          // Pet safety normalization — use the value stored in the JSON blob
          // so stale cache never shows "Not Verified" for a plant that was
          // patched in the DB after the cache was written.
          final health = d['health'];
          if (health is Map) {
            final storedStatus = health['pet_safety_status'];
            final storedSource = health['pet_safety_source'];
            if (storedStatus != null) item['pet_safety_status'] = storedStatus;
            if (storedSource != null) item['pet_safety_source'] = storedSource;
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> deleteHistory(int id) async {
    final client = _directClient();
    try {
      final response = await client
          .delete(Uri.parse('$_baseUrl/history/$id'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 404) {
        // Remove the deleted item from cache so stale data never comes back
        final cached = await CacheService.load('history');
        if (cached is List) {
          final updated = cached.where((e) => e['id'] != id).toList();
          await CacheService.save('history', updated);
        }
      } else {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<void> clearAllHistory() async {
    final client = _directClient();
    try {
      final response = await client
          .delete(Uri.parse('$_baseUrl/history'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await CacheService.save('history', <dynamic>[]);
      } else {
        throw Exception('Clear failed: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/stats'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        await CacheService.save('stats', data);
        return data;
      }
    } catch (_) {
      final cached = await CacheService.load('stats');
      if (cached != null) return Map<String, dynamic>.from(cached);
    } finally {
      client.close();
    }
    return {'garden_count': 0, 'wishlist_count': 0, 'scan_count': 0,
            'avg_score': 0, 'top_pick': 0, 'good': 0, 'careful': 0, 'risky': 0};
  }

  static Future<Map<String, dynamic>> diagnoseDisease(
    File imageFile, {
    String? plantName,
    String? scientificName,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final client = _directClient();
    final body = <String, dynamic>{'image': base64Image};
    if (plantName != null && plantName.isNotEmpty) body['plant_name'] = plantName;
    if (scientificName != null && scientificName.isNotEmpty) body['scientific_name'] = scientificName;
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/diagnose'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      try {
        final err = jsonDecode(response.body);
        throw Exception(err['detail'] ?? 'Disease check failed');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('HTTP ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<List<dynamic>> getMyGarden() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/my-garden'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await CacheService.save('my_garden', data);
        return data;
      }
    } catch (_) {
      final cached = await CacheService.load('my_garden');
      if (cached != null) return cached;
    } finally {
      client.close();
    }
    return [];
  }

  static Future<List<dynamic>> getDueForWatering() async {
    final client = _directClient();
    try {
      final response = await client.get(Uri.parse('$_baseUrl/my-garden/due'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    finally { client.close(); }
    return [];
  }

  static Future<void> markWatered(int id) async {
    final client = _directClient();
    try {
      final response = await client
          .patch(Uri.parse('$_baseUrl/my-garden/$id/water'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        try {
          final body = jsonDecode(response.body);
          throw Exception(body['detail'] ?? 'Server error ${response.statusCode}');
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('HTTP ${response.statusCode}');
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<void> setWateringSchedule(int id, int intervalDays) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/my-garden/$id/schedule'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'interval_days': intervalDays}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        try {
          final body = jsonDecode(response.body);
          throw Exception(body['detail'] ?? 'Server error ${response.statusCode}');
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('HTTP ${response.statusCode}');
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> comparePlants(int id1, int id2) async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/compare?id1=$id1&id2=$id2'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Compare failed');
    } finally {
      client.close();
    }
  }

  /// Returns null on success, or an error message string on failure.
  static Future<String?> addToMyGarden(Map<String, dynamic> plantData) async {
    final client = _directClient();
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/my-garden'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(plantData),
      );
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to add plant.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> removeFromMyGarden(int plantId) async {
    final client = _directClient();
    try {
      final response = await client.delete(Uri.parse('$_baseUrl/my-garden/$plantId'));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to remove plant.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> updatePlantNotes(int plantId, String notes) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/my-garden/$plantId/notes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'notes': notes}),
      );
      if (response.statusCode == 200) return null;
      return 'Failed to save notes.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  // ─── Wishlist ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWishlist() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/wishlist'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await CacheService.save('wishlist', data);
        return data;
      }
    } catch (_) {
      final cached = await CacheService.load('wishlist');
      if (cached != null) return cached;
    } finally {
      client.close();
    }
    return [];
  }

  /// Returns null on success, or an error message string.
  static Future<String?> addToWishlist(Map<String, dynamic> plantData) async {
    final client = _directClient();
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/wishlist'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(plantData),
      );
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to add to wishlist.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> removeFromWishlist(int plantId) async {
    final client = _directClient();
    try {
      final response = await client.delete(Uri.parse('$_baseUrl/wishlist/$plantId'));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to remove.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> updateWishlistNotes(int plantId, String notes) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/wishlist/$plantId/notes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'notes': notes}),
      );
      if (response.statusCode == 200) return null;
      return 'Failed to save notes.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> moveWishlistToGarden(int plantId) async {
    final client = _directClient();
    try {
      final response = await client.post(Uri.parse('$_baseUrl/wishlist/$plantId/move-to-garden'));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to move.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  // ─── Health Status ──────────────────────────────────────────────────────────

  static Future<String?> updateHealthStatus(int plantId, String? status) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/my-garden/$plantId/health'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'health_status': status}),
      );
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to update health status.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  // ─── Watering History ───────────────────────────────────────────────────────

  static Future<List<dynamic>> getWateringHistory(int plantId) async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/my-garden/$plantId/watering-history'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    finally { client.close(); }
    return [];
  }

  // ─── Disease History ────────────────────────────────────────────────────────

  static Future<List<dynamic>> getDiseaseHistory() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/diagnose/history'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    finally { client.close(); }
    return [];
  }

  static Future<List<dynamic>> getActiveDiseases() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/diagnose/active'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    finally { client.close(); }
    return [];
  }

  static Future<String?> linkDiseaseScan(int scanId, int plantId, String plantName) async {
    final client = _directClient();
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/diagnose/$scanId/link'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'plant_id': plantId, 'plant_name': plantName}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to link.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> updateDiseaseStatus(
      int scanId, String status, {String? notes}) async {
    final client = _directClient();
    try {
      final body = <String, dynamic>{'status': status};
      if (notes != null) body['follow_up_notes'] = notes;
      final response = await client.patch(
        Uri.parse('$_baseUrl/diagnose/$scanId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final resp = jsonDecode(response.body);
      return resp['detail'] ?? 'Failed to update.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> deleteDiagnoseScan(int scanId) async {
    final client = _directClient();
    try {
      final response = await client
          .delete(Uri.parse('$_baseUrl/diagnose/$scanId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to delete.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  // ─── Export Garden CSV ──────────────────────────────────────────────────────

  static Future<List<int>?> exportGardenCsv() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/my-garden/export/csv'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return response.bodyBytes.toList();
    } catch (_) {}
    finally { client.close(); }
    return null;
  }

  static Future<Map<String, dynamic>> getAboutStats() async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/stats/about'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (_) {}
    finally { client.close(); }
    return {'db_size_mb': 0.0, 'garden_count': 0, 'scan_count': 0,
            'wishlist_count': 0, 'disease_resolved_count': 0, 'days_gardening': 0};
  }

  /// Backs up the database then truncates all user-generated tables.
  /// Returns the result map from the API (success, backup path, deleted counts).
  static Future<Map<String, dynamic>> resetAllData() async {
    final client = _directClient();
    try {
      final response = await client
          .post(Uri.parse('$_baseUrl/dev/reset'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return {'success': false, 'message': 'Server error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    } finally {
      client.close();
    }
  }

  // ─── Care Tasks ─────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getCareTasks({int? plantId}) async {
    final client = _directClient();
    try {
      final uri = plantId != null
          ? Uri.parse('$_baseUrl/care-tasks?plant_id=$plantId')
          : Uri.parse('$_baseUrl/care-tasks');
      final response = await client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    finally { client.close(); }
    return [];
  }

  static Future<void> completeCareTask(int taskId) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/care-tasks/$taskId/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw Exception(body['detail'] ?? 'Server error ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  static Future<String?> createCareTask(Map<String, dynamic> data) async {
    final client = _directClient();
    try {
      final response = await client.post(
        Uri.parse('$_baseUrl/care-tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to create task.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> deleteCareTask(int taskId) async {
    final client = _directClient();
    try {
      final response = await client
          .delete(Uri.parse('$_baseUrl/care-tasks/$taskId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to remove task.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> backfillCareTasks() async {
    final client = _directClient();
    try {
      // Backfill missing tasks, then patch any NULLs left from old data
      await client
          .post(Uri.parse('$_baseUrl/care-tasks/backfill'),
              headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 30));
      await client
          .post(Uri.parse('$_baseUrl/care-tasks/fix-nulls'),
              headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 15));
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  // ─── Care Task History ───────────────────────────────────────────────────────

  static Future<List<dynamic>> getCareHistory(int taskId) async {
    final client = _directClient();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/care-tasks/$taskId/history'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {} finally {
      client.close();
    }
    return [];
  }

  static Future<String?> updateCareSchedule(int taskId, int intervalDays) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/care-tasks/$taskId/schedule'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'interval_days': intervalDays}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to update schedule.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }

  static Future<String?> renamePlant(int plantId, String gardenName, {String? currentNotes}) async {
    final client = _directClient();
    try {
      final response = await client.patch(
        Uri.parse('$_baseUrl/my-garden/$plantId/notes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'garden_name': gardenName, 'notes': currentNotes}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      return body['detail'] ?? 'Failed to rename plant.';
    } catch (e) {
      return e.toString();
    } finally {
      client.close();
    }
  }
}
