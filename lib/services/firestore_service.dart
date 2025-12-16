import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Search weavers by ID
  Future<List<Map<String, dynamic>>> searchWeavers(String query) async {
    try {
      if (query.isEmpty) return [];
      
      final querySnapshot = await _firestore
          .collection('weavers')
          .where('weaverId', isGreaterThanOrEqualTo: query)
          .where('weaverId', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10)
          .get();

      return querySnapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('Error searching weavers: $e');
      return [];
    }
  }

  // Get weaver by ID
  Future<Map<String, dynamic>?> getWeaverById(String weaverId) async {
    try {
      final querySnapshot = await _firestore
          .collection('weavers')
          .where('weaverId', isEqualTo: weaverId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return null;

      final doc = querySnapshot.docs.first;
      return {
        'id': doc.id,
        ...doc.data(),
      };
    } catch (e) {
      print('Error getting weaver: $e');
      return null;
    }
  }

  // Get all products
  Future<List<Map<String, dynamic>>> getAllProducts() async {
    try {
      final querySnapshot = await _firestore
          .collection('products')
          .orderBy('name')
          .get();

      return querySnapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('Error getting products: $e');
      return [];
    }
  }

  // Generate next receipt number
  Future<String> generateReceiptNumber() async {
    try {
      // Get all receipts to find the highest receipt number
      final querySnapshot = await _firestore
          .collection('receipts')
          .get();

      if (querySnapshot.docs.isEmpty) {
        return '1';
      }

      int maxReceiptNo = 0;

      // Parse all receipt numbers and find the maximum
      for (var doc in querySnapshot.docs) {
        final receiptNo = doc.data()['receiptNo'];
        int? receiptNumber;

        if (receiptNo is String) {
          // Handle string formats like "ST1001" or "1"
          final cleaned = receiptNo.replaceAll(RegExp(r'[^0-9]'), '');
          if (cleaned.isNotEmpty) {
            receiptNumber = int.tryParse(cleaned);
          }
        } else if (receiptNo is int) {
          receiptNumber = receiptNo;
        } else if (receiptNo is num) {
          receiptNumber = receiptNo.toInt();
        }

        if (receiptNumber != null && receiptNumber > maxReceiptNo) {
          maxReceiptNo = receiptNumber;
        }
      }

      // Return the next number as a simple string
      return '${maxReceiptNo + 1}';
    } catch (e) {
      print('Error generating receipt number: $e');
      // Fallback: try to get the last receipt by date
      try {
        final querySnapshot = await _firestore
            .collection('receipts')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          return '1';
        }

        final lastReceiptNo = querySnapshot.docs.first.data()['receiptNo'];
        int? receiptNumber;

        if (lastReceiptNo is String) {
          final cleaned = lastReceiptNo.replaceAll(RegExp(r'[^0-9]'), '');
          if (cleaned.isNotEmpty) {
            receiptNumber = int.tryParse(cleaned);
          }
        } else if (lastReceiptNo is int) {
          receiptNumber = lastReceiptNo;
        } else if (lastReceiptNo is num) {
          receiptNumber = lastReceiptNo.toInt();
        }

        return '${(receiptNumber ?? 0) + 1}';
      } catch (e2) {
        print('Error in fallback receipt number generation: $e2');
        return '1';
      }
    }
  }

  // Save receipt
  Future<bool> saveReceipt(Map<String, dynamic> receiptData) async {
    try {
      await _firestore.collection('receipts').add(receiptData);
      return true;
    } catch (e) {
      print('Error saving receipt: $e');
      return false;
    }
  }

  // Get receipt by receipt number
  Future<Map<String, dynamic>?> getReceiptByNumber(String receiptNo) async {
    try {
      final querySnapshot = await _firestore
          .collection('receipts')
          .where('receiptNo', isEqualTo: receiptNo)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return null;

      final doc = querySnapshot.docs.first;
      return {
        'id': doc.id,
        ...doc.data(),
      };
    } catch (e) {
      print('Error getting receipt: $e');
      return null;
    }
  }

  // Update receipt
  Future<bool> updateReceipt(String receiptId, Map<String, dynamic> receiptData) async {
    try {
      await _firestore.collection('receipts').doc(receiptId).update(receiptData);
      return true;
    } catch (e) {
      print('Error updating receipt: $e');
      return false;
    }
  }

  // Get receipts by date range with optional filters
  Future<List<Map<String, dynamic>>> getReceiptsByDateRange(
    DateTime startDate,
    DateTime endDate, {
    String? supervisorId,
    String? weaverId,
    String? receiptNo,
  }) async {
    try {
      // Set time to start and end of day
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

      final startTimestamp = Timestamp.fromDate(start);
      final endTimestamp = Timestamp.fromDate(end);

      Query<Map<String, dynamic>> query = _firestore
          .collection('receipts')
          .where('date', isGreaterThanOrEqualTo: startTimestamp)
          .where('date', isLessThanOrEqualTo: endTimestamp);

      // Filter by supervisor ID if provided
      if (supervisorId != null && supervisorId.isNotEmpty) {
        query = query.where('supervisorId', isEqualTo: supervisorId);
      }

      // Filter by weaver ID if provided
      if (weaverId != null && weaverId.isNotEmpty) {
        query = query.where('weaverId', isEqualTo: weaverId);
      }

      // Filter by receipt number if provided
      if (receiptNo != null && receiptNo.isNotEmpty) {
        query = query.where('receiptNo', isEqualTo: receiptNo);
      }

      final querySnapshot = await query.orderBy('date', descending: true).get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error getting receipts by date range: $e');
      // Fallback: Get all and filter in memory if index issue
      try {
        final querySnapshot = await _firestore
            .collection('receipts')
            .orderBy('date', descending: true)
            .get();

        final start = DateTime(startDate.year, startDate.month, startDate.day);
        final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

        var filteredReceipts = querySnapshot.docs
            .map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                ...data,
              };
            })
            .where((receipt) {
              // Filter by date
              if (receipt['date'] is Timestamp) {
                final date = (receipt['date'] as Timestamp).toDate();
                if (!date.isAfter(start.subtract(const Duration(days: 1))) ||
                    !date.isBefore(end.add(const Duration(days: 1)))) {
                  return false;
                }
              } else {
                return false;
              }

              // Filter by supervisor ID
              if (supervisorId != null && supervisorId.isNotEmpty) {
                if (receipt['supervisorId'] != supervisorId) {
                  return false;
                }
              }

              // Filter by weaver ID
              if (weaverId != null && weaverId.isNotEmpty) {
                if (receipt['weaverId'] != weaverId) {
                  return false;
                }
              }

              // Filter by receipt number
              if (receiptNo != null && receiptNo.isNotEmpty) {
                if (receipt['receiptNo'] != receiptNo) {
                  return false;
                }
              }

              return true;
            })
            .toList();
        
        return filteredReceipts;
      } catch (e2) {
        print('Error in fallback query: $e2');
        return [];
      }
    }
  }
}
