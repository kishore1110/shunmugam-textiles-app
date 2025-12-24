import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';

class AddProductionPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const AddProductionPage({super.key, required this.userData});

  @override
  State<AddProductionPage> createState() => _AddProductionPageState();
}

class _AddProductionPageState extends State<AddProductionPage> {
  final _firestoreService = FirestoreService();
  final _weaverIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dateController;
  DateTime _selectedDate = DateTime.now();
  bool _suppressWeaverSearch = false;

  List<Map<String, dynamic>> _weavers = [];
  Map<String, dynamic>? _selectedWeaver;
  List<Map<String, dynamic>> _products = [];
  Map<String, List<_QuantityEntry>> _productQuantities = {}; // Store list of added quantities
  Map<String, TextEditingController> _quantityControllers = {}; // Input controllers for entering new quantities
  bool _isLoading = false;
  bool _isSearching = false;

  void _disposeAllQuantityEntryControllers() {
    for (final entries in _productQuantities.values) {
      for (final entry in entries) {
        entry.dispose();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _weaverIdController.addListener(_searchWeavers);
    _dateController = TextEditingController(text: _formatDate(_selectedDate));
  }

  @override
  void dispose() {
    _weaverIdController.removeListener(_searchWeavers);
    _weaverIdController.dispose();
    _dateController.dispose();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    _disposeAllQuantityEntryControllers();
    _productQuantities.clear();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final twoDigits = (int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
  }

  DateTime? _tryParseInputDate(String value) {
    final parts = value.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    // fallback for ISO or other parseable formats
    return DateTime.tryParse(value);
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
        );
        _dateController.text = _formatDate(_selectedDate);
      });
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final products = await _firestoreService.getAllProducts();
    products.sort((a, b) {
      final aSerial = (a['serialNo'] ?? 1e9) as num;
      final bSerial = (b['serialNo'] ?? 1e9) as num;
      return aSerial.compareTo(bSerial);
    });
    _disposeAllQuantityEntryControllers();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _productQuantities.clear();
    _quantityControllers.clear();
    setState(() {
      _products = products;
      for (var product in products) {
        final productId = product['id'];
        _productQuantities[productId] = []; // Initialize with empty list
        _quantityControllers[productId] = TextEditingController(text: ''); // Empty input field
      }
      _isLoading = false;
    });
  }

  Future<void> _searchWeavers() async {
    if (_suppressWeaverSearch) return;
    final query = _weaverIdController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _weavers = [];
        _selectedWeaver = null;
      });
      return;
    }

    // Reset selection when user edits the input
    setState(() => _selectedWeaver = null);

    setState(() => _isSearching = true);
    final weavers = await _firestoreService.searchWeavers(query);
    setState(() {
      _weavers = weavers;
      _isSearching = false;
    });
  }

  void _selectWeaver(Map<String, dynamic> weaver) {
    _suppressWeaverSearch = true;
    setState(() {
      _selectedWeaver = weaver;
      _weaverIdController.text = weaver['weaverId'] ?? '';
      _weavers = [];
    });
    // Re-enable search after this tick to avoid re-querying while we set text
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressWeaverSearch = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _addQuantity(String productId) {
    final controller = _quantityControllers[productId];
    if (controller == null) return;
    
    final inputValue = controller.text.trim();
    if (inputValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a quantity')),
      );
      return;
    }

    final quantity = int.tryParse(inputValue);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive number')),
      );
      return;
    }

    setState(() {
      if (!_productQuantities.containsKey(productId)) {
        _productQuantities[productId] = [];
      }
      _productQuantities[productId]!.add(_QuantityEntry(quantity));
      controller.text = ''; // Clear input after adding
    });
  }

  int _getTotalQuantity() {
    return _productQuantities.values.fold(0, (sum, quantities) {
      return sum + quantities.fold(0, (subSum, entry) => subSum + entry.value);
    });
  }

  int _getProductTotal(String productId) {
    final quantities = _productQuantities[productId] ?? [];
    return quantities.fold(0, (sum, entry) => sum + entry.value);
  }

  String _getProductBreakdown(String productId) {
    final quantities = _productQuantities[productId] ?? [];
    if (quantities.isEmpty) return '';
    return quantities.map((entry) => entry.value.toString()).join('+');
  }

  Map<String, int> _getSelectedProducts() {
    return Map.fromEntries(
      _productQuantities.entries.where((entry) => entry.value.isNotEmpty).map((entry) {
        final total = entry.value.fold(0, (sum, qtyEntry) => sum + qtyEntry.value);
        return MapEntry(entry.key, total);
      }),
    );
  }

  Future<void> _saveReceipt() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWeaver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a weaver')),
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
    final receiptNo = await _firestoreService.generateReceiptNumber();
    setState(() => _isLoading = false);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmationDialog(
        receiptNo: receiptNo,
        supervisorId: widget.userData['supervisorId'] ?? '',
        supervisorName: widget.userData['name'] ?? '',
        selectedDate: _selectedDate,
        weaverId: _selectedWeaver!['weaverId'] ?? '',
        weaverName: _selectedWeaver!['name'] ?? '',
        products: _products,
        productQuantities: selectedProducts,
        totalQuantity: _getTotalQuantity(),
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      
      // Prepare receipt data
      final receiptData = {
        'receiptNo': receiptNo,
        'supervisorId': widget.userData['supervisorId'],
        'supervisorName': widget.userData['name'],
        'weaverId': _selectedWeaver!['weaverId'],
        'weaverName': _selectedWeaver!['name'],
        'date': Timestamp.fromDate(_selectedDate),
        'products': selectedProducts.map((key, value) {
          final product = _products.firstWhere((p) => p['id'] == key);
          return MapEntry(key, {
            'productId': key,
            'productName': product['name'] ?? '',
            'quantity': value,
          });
        }),
        'totalQuantity': _getTotalQuantity(),
        'createdAt': Timestamp.now(),
      };

      final success = await _firestoreService.saveReceipt(receiptData);
      setState(() => _isLoading = false);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Receipt saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save receipt'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Production'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calendar_today_rounded,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _dateController,
                              decoration: const InputDecoration(
                                hintText: 'Select date',
                                prefixIcon: Icon(Icons.event),
                                suffixIcon: Icon(Icons.edit_calendar_rounded),
                              ),
                              readOnly: false,
                              onTap: _pickDate,
                              keyboardType: TextInputType.datetime,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select a date';
                                }
                  final parsed = _tryParseInputDate(value);
                  if (parsed == null) {
                                  return 'Invalid date';
                                }
                                return null;
                              },
                              onChanged: (value) {
                  final parsed = _tryParseInputDate(value);
                                if (parsed != null) {
                                  setState(() {
                                    _selectedDate = DateTime(
                                      parsed.year,
                                      parsed.month,
                                      parsed.day,
                                    );
                      _dateController.value = _dateController.value.copyWith(
                        text: _formatDate(_selectedDate),
                        selection: TextSelection.collapsed(
                          offset: _formatDate(_selectedDate).length,
                        ),
                      );
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Weaver ID Input
              Text(
                'Weaver ID',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _weaverIdController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'Enter weaver ID',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_selectedWeaver != null || _weaverIdController.text.isNotEmpty)
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _weaverIdController.clear();
                                  _selectedWeaver = null;
                                  _weavers = [];
                                });
                              },
                            )
                          : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter weaver ID';
                  }
                  if (_selectedWeaver == null) {
                    return 'Weaver not found';
                  }
                  return null;
                },
              ),

              // Weaver Search Results
              if (_weavers.isNotEmpty && _selectedWeaver == null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _weavers.length,
                    itemBuilder: (context, index) {
                      final weaver = _weavers[index];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(weaver['name'] ?? ''),
                        subtitle: Text('ID: ${weaver['weaverId'] ?? ''}'),
                        onTap: () => _selectWeaver(weaver),
                      );
                    },
                  ),
                ),

              // Selected Weaver Info
              if (_selectedWeaver != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weaver ID - ${_selectedWeaver!['weaverId']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Weaver Name - ${_selectedWeaver!['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_weavers.isEmpty &&
                  _weaverIdController.text.isNotEmpty &&
                  !_isSearching &&
                  _selectedWeaver == null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red),
                      SizedBox(width: 12),
                      Text('No weaver found'),
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              // Products Section
              Text(
                'Products',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              if (_isLoading && _products.isEmpty)
                const Center(child: CircularProgressIndicator())
              else
                ..._products.map((product) => _buildProductCard(product)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
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
                  onPressed: _isLoading ? null : _saveReceipt,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Receipt'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final productId = product['id'];
    final quantityEntries = _productQuantities[productId] ?? [];
    final total = _getProductTotal(productId);
    final breakdown = _getProductBreakdown(productId);
    final controller = _quantityControllers.putIfAbsent(
      productId,
      () => TextEditingController(text: ''),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name
            Text(
              product['name'] ?? 'Unknown',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (quantityEntries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Added quantities',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _buildEditableQuantityExpression(quantityEntries),
            ],
            const SizedBox(height: 12),
            // Quantity input row
            Row(
              children: [
                // Left: Qty label and input line
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Qty',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: controller,
                        textAlign: TextAlign.left,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppTheme.primaryBlue),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Middle: Blue circular + button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: () => _addQuantity(productId),
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 16),
                // Right: Total quantity display
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$total',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (breakdown.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          breakdown,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableQuantityExpression(List<_QuantityEntry> entries) {
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          _buildEditableQuantityBox(entries[i]),
          if (i < entries.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildEditableQuantityBox(_QuantityEntry entry) {
    return SizedBox(
      width: 60,
      child: TextField(
        controller: entry.controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryBlue),
          ),
        ),
        onChanged: (value) => _handleQuantityEdit(entry, value),
      ),
    );
  }

  void _handleQuantityEdit(_QuantityEntry entry, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) return;
    if (entry.value == parsed) return;
    setState(() {
      entry.value = parsed;
    });
  }
}

class _ConfirmationDialog extends StatelessWidget {
  final String receiptNo;
  final String supervisorId;
  final String supervisorName;
  final DateTime selectedDate;
  final String weaverId;
  final String weaverName;
  final List<Map<String, dynamic>> products;
  final Map<String, int> productQuantities;
  final int totalQuantity;

  const _ConfirmationDialog({
    required this.receiptNo,
    required this.supervisorId,
    required this.supervisorName,
    required this.selectedDate,
    required this.weaverId,
    required this.weaverName,
    required this.products,
    required this.productQuantities,
    required this.totalQuantity,
  });

  String _formatDate(DateTime date) {
    final twoDigits = (int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirm Receipt',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildInfoRow('Receipt No', receiptNo),
              _buildInfoRow('Date', _formatDate(selectedDate)),
              _buildInfoRow('Supervisor ID', supervisorId),
              _buildInfoRow('Supervisor Name', supervisorName),
              _buildInfoRow('Weaver ID', weaverId),
              _buildInfoRow('Weaver Name', weaverName),
              const Divider(height: 32),
              const Text(
                'Products:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ...productQuantities.entries.map((entry) {
                final product = products.firstWhere((p) => p['id'] == entry.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(product['name'] ?? '')),
                      Text(
                        'Qty: ${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Quantity:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$totalQuantity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: const Text('Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
}

class _QuantityEntry {
  _QuantityEntry(int initialValue)
      : value = initialValue,
        controller = TextEditingController(text: initialValue.toString());

  int value;
  final TextEditingController controller;

  void dispose() {
    controller.dispose();
  }
}
