import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';

class ChangeProductionPage extends StatefulWidget {
  const ChangeProductionPage({super.key});

  @override
  State<ChangeProductionPage> createState() => _ChangeProductionPageState();
}

class _ChangeProductionPageState extends State<ChangeProductionPage> {
  final _firestoreService = FirestoreService();
  final _receiptNoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _receipt;
  List<Map<String, dynamic>> _products = [];
  Map<String, int> _productQuantities = {};
  Map<String, TextEditingController> _quantityControllers = {};
  Map<String, dynamic>? _selectedWeaver;
  bool _isLoading = false;
  bool _isLoadingReceipt = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _receiptNoController.dispose();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final products = await _firestoreService.getAllProducts();
    setState(() {
      _products = products;
      _isLoading = false;
    });
  }

  Future<void> _loadReceipt() async {
    final receiptNo = _receiptNoController.text.trim();
    if (receiptNo.isEmpty) return;

    setState(() {
      _isLoadingReceipt = true;
      _receipt = null;
    });

    final receipt = await _firestoreService.getReceiptByNumber(receiptNo);
    
    if (receipt == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoadingReceipt = false);
      return;
    }

    // Load weaver
    final weaver = await _firestoreService.getWeaverById(receipt['weaverId'] ?? '');

    // Load product quantities
    final Map<String, int> quantities = {};
    if (receipt['products'] != null) {
      final products = receipt['products'] as Map;
      products.forEach((key, value) {
        if (value is Map) {
          quantities[key] = value['quantity'] ?? 0;
        }
      });
    }

    // Initialize controllers for all products
    for (var product in _products) {
      final productId = product['id'];
      final qty = quantities[productId] ?? 0;
      _quantityControllers[productId] = TextEditingController(text: qty.toString());
    }

    setState(() {
      _receipt = receipt;
      _selectedWeaver = weaver;
      _productQuantities = quantities;
      _isLoadingReceipt = false;
    });
  }

  void _incrementQuantity(String productId) {
    setState(() {
      final newQuantity = (_productQuantities[productId] ?? 0) + 1;
      _productQuantities[productId] = newQuantity;
      _quantityControllers[productId]?.text = newQuantity.toString();
    });
  }

  void _decrementQuantity(String productId) {
    setState(() {
      final current = _productQuantities[productId] ?? 0;
      if (current > 0) {
        final newQuantity = current - 1;
        _productQuantities[productId] = newQuantity;
        _quantityControllers[productId]?.text = newQuantity.toString();
      }
    });
  }

  int _getTotalQuantity() {
    return _productQuantities.values.fold(0, (sum, qty) => sum + qty);
  }

  Map<String, int> _getSelectedProducts() {
    return Map.fromEntries(
      _productQuantities.entries.where((entry) => entry.value > 0),
    );
  }

  Future<void> _updateReceipt() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receipt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a receipt first')),
      );
      return;
    }

    final selectedProducts = _getSelectedProducts();
    if (selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Prepare updated receipt data
    final receiptData = {
      'supervisorId': _receipt!['supervisorId'],
      'supervisorName': _receipt!['supervisorName'],
      'weaverId': _selectedWeaver!['weaverId'],
      'weaverName': _selectedWeaver!['name'],
      'products': selectedProducts.map((key, value) {
        final product = _products.firstWhere((p) => p['id'] == key);
        return MapEntry(key, {
          'productId': key,
          'productName': product['name'] ?? '',
          'quantity': value,
        });
      }),
      'totalQuantity': _getTotalQuantity(),
      'updatedAt': Timestamp.now(),
    };

    final success = await _firestoreService.updateReceipt(_receipt!['id'], receiptData);
    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadReceipt(); // Reload to show updated data
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update receipt'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Production'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Receipt Number Input
              Text(
                'Receipt Number',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _receiptNoController,
                      decoration: const InputDecoration(
                        hintText: 'Enter receipt number (e.g., ST1001)',
                        prefixIcon: Icon(Icons.receipt_long),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter receipt number';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoadingReceipt ? null : _loadReceipt,
                    child: _isLoadingReceipt
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load'),
                  ),
                ],
              ),

              if (_receipt != null) ...[
                const SizedBox(height: 32),

                // Receipt Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Receipt: ${_receipt!['receiptNo']}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Date: ${_formatDate(_receipt!['date'])}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        _buildInfoRow('Supervisor ID', _receipt!['supervisorId'] ?? 'N/A'),
                        _buildInfoRow('Supervisor Name', _receipt!['supervisorName'] ?? 'N/A'),
                        _buildInfoRow('Weaver ID', _receipt!['weaverId'] ?? 'N/A'),
                        _buildInfoRow('Weaver Name', _receipt!['weaverName'] ?? 'N/A'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Products Section
                Text(
                  'Products',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),

                ..._products.map((product) => _buildProductCard(product)),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: _receipt != null
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Quantity:',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${_getTotalQuantity()}',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _updateReceipt,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Update Receipt'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final productId = product['id'];
    final quantity = _productQuantities[productId] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (product['description'] != null)
                    Text(
                      product['description'],
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: quantity > 0 ? AppTheme.primaryBlue : Colors.grey,
                  onPressed: quantity > 0 ? () => _decrementQuantity(productId) : null,
                ),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    controller: _quantityControllers[productId],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final qty = int.tryParse(value) ?? 0;
                      setState(() {
                        _productQuantities[productId] = qty;
                      });
                    },
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppTheme.primaryBlue,
                  onPressed: () => _incrementQuantity(productId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
    return date.toString();
  }
}
