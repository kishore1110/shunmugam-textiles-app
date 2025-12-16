import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorageService {
  static const String _keyUserData = 'user_data';
  static const String _keySupervisorId = 'supervisor_id';
  static const String _keyPassword = 'password';

  /// Save user data after successful login
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserData, jsonEncode(userData));
      await prefs.setString(_keySupervisorId, userData['supervisorId']?.toString() ?? '');
      // Note: We don't store password for security reasons
      // Password will be re-entered if auto-login fails
    } catch (e) {
      print('Error saving user data: $e');
    }
  }

  /// Get stored user data
  Future<Map<String, dynamic>?> getUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString(_keyUserData);
      if (userDataString != null) {
        return jsonDecode(userDataString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  /// Get stored supervisor ID
  Future<String?> getSupervisorId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keySupervisorId);
    } catch (e) {
      print('Error getting supervisor ID: $e');
      return null;
    }
  }

  /// Check if user is logged in (has stored data)
  Future<bool> isLoggedIn() async {
    final userData = await getUserData();
    return userData != null;
  }

  /// Clear all stored authentication data (logout)
  Future<void> clearUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUserData);
      await prefs.remove(_keySupervisorId);
      await prefs.remove(_keyPassword);
    } catch (e) {
      print('Error clearing user data: $e');
    }
  }
}

