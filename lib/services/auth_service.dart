import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> login(String supervisorId, String password) async {
    try {
      // Trim inputs to remove any whitespace
      final trimmedSupervisorId = supervisorId.trim();
      final trimmedPassword = password.trim();

      print('Attempting login with Supervisor ID: "$trimmedSupervisorId"');
      print('Firestore instance: ${_firestore.app.name}');
      print('Project ID: ${_firestore.app.options.projectId}');

      // First, try to verify Firestore connection by checking if we can access the collection
      try {
        // Try to get all documents first to check permissions
        print('Checking Firestore connection and permissions...');
        final allDocs = await _firestore
            .collection('supervisors')
            .get();
        
        print('Total supervisors in collection: ${allDocs.docs.length}');
        
        if (allDocs.docs.isEmpty) {
          print('⚠️ WARNING: No supervisors found in collection!');
          print('This could mean:');
          print('  1. Firestore security rules are blocking access');
          print('  2. The collection is empty');
          print('  3. Network/permission issue');
          return null;
        }

        // List all supervisor IDs found
        print('Supervisors found in database:');
        for (var doc in allDocs.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final storedId = data['supervisorId']?.toString().trim() ?? '';
          print('  - "$storedId" (name: ${data['name']})');
        }

        // Now search for matching supervisorId
        DocumentSnapshot? foundDoc;
        for (var doc in allDocs.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final storedId = data['supervisorId']?.toString().trim() ?? '';
          
          print('Checking supervisor: "$storedId" against "$trimmedSupervisorId"');
          
          // Compare as string (case-sensitive)
          if (storedId == trimmedSupervisorId) {
            foundDoc = doc;
            print('✓ Found matching supervisor!');
            break;
          }
        }

        if (foundDoc == null) {
          print('Supervisor not found: "$trimmedSupervisorId"');
          return null;
        }

        // Use the found document
        final doc = foundDoc;
        final data = doc.data() as Map<String, dynamic>;

        // Debug logging
        print('Document data:');
        print('  supervisorId: "${data['supervisorId']}" (type: ${data['supervisorId'].runtimeType})');
        print('  password: "${data['password']}" (type: ${data['password'].runtimeType})');
        print('  status: "${data['status']}" (type: ${data['status'].runtimeType})');
        print('  name: "${data['name']}"');

        // Get stored values
        final storedPassword = data['password']?.toString().trim() ?? '';
        final storedStatus = data['status']?.toString().trim().toLowerCase() ?? '';
        final enteredPassword = trimmedPassword;

        print('Password comparison:');
        print('  Stored: "$storedPassword" (length: ${storedPassword.length})');
        print('  Entered: "$enteredPassword" (length: ${enteredPassword.length})');
        print('  Match: ${storedPassword == enteredPassword}');

        print('Status check:');
        print('  Stored: "$storedStatus"');
        print('  Required: "active"');
        print('  Match: ${storedStatus == 'active'}');

        // Check password and status
        if (storedPassword == enteredPassword && storedStatus == 'active') {
          print('Login successful!');
          return {
            'id': doc.id,
            'supervisorId': data['supervisorId']?.toString() ?? '',
            'name': data['name']?.toString() ?? '',
            'status': data['status']?.toString() ?? '',
            'createdAt': data['createdAt']?.toString() ?? '',
          };
        }

        print('Login failed!');
        print('  Password match: ${storedPassword == enteredPassword}');
        print('  Status match: ${storedStatus == 'active'}');
        return null; // Invalid password or inactive status
      } catch (e) {
        print('Error accessing Firestore: $e');
        print('This might be a permissions issue. Check Firestore security rules.');
        return null;
      }
    } catch (e, stackTrace) {
      print('Login error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }
}

