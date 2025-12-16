import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class DateRangeReportPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const DateRangeReportPage({super.key, required this.userData});

  @override
  State<DateRangeReportPage> createState() => _DateRangeReportPageState();
}

class _DateRangeReportPageState extends State<DateRangeReportPage> {
  final _firestoreService = FirestoreService();
  final List<String> _productColumns = [];
  List<_RowData> _rows = [];
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;
  bool _showFilters = true;

  @override
  void initState() {
    super.initState();
    _startDate = null;
    _endDate = null;
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await _firestoreService.getAllProducts();
    setState(() {
      _productColumns
        ..clear()
        ..addAll(products.map((p) => (p['name'] ?? '').toString()));
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
        const SnackBar(content: Text('Please select start and end dates')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final receipts = await _firestoreService.getReceiptsByDateRange(
      _startDate!,
      _endDate!,
    );

    final grouped = <String, _RowData>{};

    for (final receipt in receipts) {
      final weaverName = receipt['weaverName']?.toString() ?? '-';
      final loom = receipt['weaverId']?.toString() ?? '-';
      final products = receipt['products'] as Map<String, dynamic>?;
      final key = '$loom|$weaverName';

      grouped.putIfAbsent(
        key,
        () => _RowData(loom: loom, weaver: weaverName, quantities: {
          for (final title in _productColumns) title: 0,
        }),
      );

      final row = grouped[key]!;

      if (products != null) {
        for (final entry in products.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            final name = value['productName']?.toString() ?? '';
            final qty = value['quantity'];
            if (_productColumns.contains(name) && qty is num) {
              row.quantities[name] = (row.quantities[name] ?? 0) + qty.toInt();
            }
          }
        }
      }
    }

    setState(() {
      _rows = grouped.values.toList();
      _isLoading = false;
    });
  }

  int _rowTotal(_RowData row) {
    return row.quantities.values.fold<int>(0, (sum, value) => sum + value);
  }

  int _grandTotal() {
    return _rows.fold<int>(0, (sum, row) => sum + _rowTotal(row));
  }

  List<DataRow> _buildDataRows() {
    final rows = _rows.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;
      return DataRow(
        cells: [
          DataCell(Text('${index + 1}')),
          DataCell(Text(row.loom)),
          DataCell(Text(row.weaver)),
          ..._productColumns.map(
            (title) => DataCell(
              Text(
                row.quantities[title]?.toString() ?? '0',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          DataCell(
            Text(
              '${_rowTotal(row)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }).toList();

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
      ..._productColumns.map((_) => const DataCell(Text(''))),
      DataCell(
        Text(
          '${_grandTotal()}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Date to Date Report'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => setState(() => _showFilters = !_showFilters),
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
                        'Filter by Date Range',
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
              child: _rows.isEmpty
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
                                columns: [
                                  const DataColumn(
                                    label: Text(
                                      'Sno',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      'Loom',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      'Weaver',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ..._productColumns.map(
                                    (title) => DataColumn(
                                      label: SizedBox(
                                        width: 120,
                                        child: Text(
                                          title,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      'Total',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                          rows: _buildDataRows(),
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

class _RowData {
  final String loom;
  final String weaver;
  final Map<String, int> quantities;

  _RowData({
    required this.loom,
    required this.weaver,
    required this.quantities,
  });
}