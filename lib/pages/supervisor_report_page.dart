import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class SupervisorReportPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const SupervisorReportPage({super.key, required this.userData});

  @override
  State<SupervisorReportPage> createState() => _SupervisorReportPageState();
}

class _SupervisorReportPageState extends State<SupervisorReportPage> {
  final _firestoreService = FirestoreService();
  final _supervisorController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;
  bool _showFilters = true;
  List<Map<String, dynamic>> _receipts = [];
  List<String> _productColumns = [];

  @override
  void initState() {
    super.initState();
    _supervisorController.clear();
    _loadProducts();
  }


  @override
  void dispose() {
    _supervisorController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await _firestoreService.getAllProducts();
    setState(() {
      _productColumns = products.map((p) => (p['name'] ?? '').toString()).toList();
    });
  }

  Future<void> _selectDate({required bool isStart}) async {
    final initialDate = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _loadReport() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both start and end dates')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final receipts = await _firestoreService.getReceiptsByDateRange(
      _startDate!,
      _endDate!,
      supervisorId: _supervisorController.text.trim().isEmpty
          ? null
          : _supervisorController.text.trim(),
    );

    setState(() {
      _receipts = receipts;
      _isLoading = false;
    });
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(date.toDate());
    }
    return date?.toString() ?? '-';
  }

  int _getProductQuantity(Map<String, dynamic>? products, String productName) {
    if (products == null) return 0;
    for (final value in products.values) {
      if (value is Map<String, dynamic>) {
        final name = value['productName']?.toString() ?? '';
        if (name.toLowerCase() == productName.toLowerCase()) {
          final quantity = value['quantity'];
          if (quantity is num) return quantity.toInt();
        }
      }
    }
    return 0;
  }

  List<DataColumn> _buildColumns() {
    final leadingColumns = [
      'Receipt No',
      'Supervisor ID',
      'Loom No',
      'Weaver Name',
      'Date',
    ];

    return [
      ...leadingColumns.map(
        (title) => DataColumn(
          label: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
      ..._productColumns.map(
        (title) => DataColumn(
          label: SizedBox(
            width: 120,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
      const DataColumn(
        label: Text(
          'Total',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    ];
  }

  List<DataRow> _buildRows() {
    return _receipts.map((receipt) {
      final products = receipt['products'] as Map<String, dynamic>?;
      final cells = <DataCell>[
        DataCell(Text(receipt['receiptNo']?.toString() ?? '-')),
        DataCell(Text(receipt['supervisorId']?.toString() ?? '-')),
        DataCell(Text(receipt['weaverId']?.toString() ?? '-')),
        DataCell(Text(receipt['weaverName']?.toString() ?? '-')),
        DataCell(Text(_formatDate(receipt['date']))),
      ];

      for (final productTitle in _productColumns) {
        final qty = _getProductQuantity(products, productTitle);
        cells.add(
          DataCell(
            Text(
              qty.toString(),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }

      cells.add(
        DataCell(
          Text(
            '${receipt['totalQuantity'] ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );

      return DataRow(cells: cells);
    }).toList();
  }

  List<DataRow> _buildRowsWithTotal() {
    final rows = _buildRows();
    rows.add(_buildGrandTotalRow());
    return rows;
  }

  DataRow _buildGrandTotalRow() {
    final cells = <DataCell>[
      DataCell(
        Text(
          'Grand Total',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      const DataCell(Text('')),
      const DataCell(Text('')),
      const DataCell(Text('')),
      const DataCell(Text('')),
      ..._productColumns.map(
        (_) => const DataCell(Text('')),
      ),
      DataCell(
        Text(
          '${_getGrandTotal()}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryBlue,
          ),
        ),
      ),
    ];

    return DataRow(
      color: MaterialStateProperty.all(AppTheme.primaryBlue.withOpacity(0.08)),
      cells: cells,
    );
  }

  int _getGrandTotal() {
    return _receipts.fold<int>(
      0,
      (sum, receipt) => sum + ((receipt['totalQuantity'] ?? 0) as num).toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Report'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            icon: Icon(_showFilters ? Icons.filter_alt_off : Icons.filter_alt),
            label: Text(_showFilters ? 'Hide Filters' : 'Show Filters'),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildDatePickerInput(
                              placeholder: 'Start Date',
                              value: _startDate,
                              onTap: () => _selectDate(isStart: true),
                            ),
                            const SizedBox(width: 12),
                            _buildDatePickerInput(
                              placeholder: 'End Date',
                              value: _endDate,
                              onTap: () => _selectDate(isStart: false),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _supervisorController,
                        decoration: const InputDecoration(
                          labelText: 'Supervisor ID',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _loadReport,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Load Report'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: const [
                          Icon(Icons.screen_rotation, size: 18, color: AppTheme.textSecondary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tip: Rotate your phone for a wider view or drag horizontally to scroll.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            secondChild: const SizedBox(height: 12),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _receipts.isEmpty
                  ? Center(
                      child: Text(
                        _isLoading ? 'Loading report...' : 'Load a report to see data.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: InteractiveViewer(
                            constrained: false,
                            minScale: 0.8,
                            maxScale: 2.5,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                          child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  AppTheme.primaryBlue.withOpacity(0.1),
                                ),
                                border: TableBorder.all(
                                  color: Colors.grey.shade300,
                                  width: 1,
                                ),
                          columns: _buildColumns(),
                          rows: _buildRowsWithTotal(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

  Widget _buildDatePickerInput({
    required String placeholder,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value == null ? placeholder : DateFormat('dd/MM/yyyy').format(value),
                  style: TextStyle(
                    color: value == null ? AppTheme.textSecondary : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

