import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';

class ProductionReportPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProductionReportPage({super.key, required this.userData});

  @override
  State<ProductionReportPage> createState() => _ProductionReportPageState();
}

class _ProductionReportPageState extends State<ProductionReportPage> {
  final _firestoreService = FirestoreService();
  final _loomNoController = TextEditingController();
  final _receiptIdController = TextEditingController();
  final _supervisorIdController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = false;
  bool _showFilters = true;

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      if (_endDate != null) {
        _loadReceipts();
      }
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      if (_startDate != null) {
        _loadReceipts();
      }
    }
  }

  @override
  void dispose() {
    _loomNoController.dispose();
    _receiptIdController.dispose();
    _supervisorIdController.dispose();
    super.dispose();
  }

  Future<void> _loadReceipts() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both start and end dates')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final supervisorId = _supervisorIdController.text.trim();
    final loomNo = _loomNoController.text.trim();
    final receiptId = _receiptIdController.text.trim();

    final receipts = await _firestoreService.getReceiptsByDateRange(
      _startDate!,
      _endDate!,
      supervisorId: supervisorId.isEmpty ? null : supervisorId,
      weaverId: loomNo.isEmpty ? null : loomNo,
      receiptNo: receiptId.isEmpty ? null : receiptId,
    );

    setState(() {
      _receipts = receipts;
      _isLoading = false;
    });
  }

  Future<void> _printSingleReceipt(Map<String, dynamic> receipt) async {
    try {
      final pdfBytes = await _generatePdf(receipt);
      final receiptNo = receipt['receiptNo']?.toString() ?? 'N/A';

      try {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
        );
      } catch (printError) {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'receipt_$receiptNo.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing receipt: $e')),
        );
      }
    }
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return DateFormat('dd/MM/yyyy').format(dateTime);
    }
    return date.toString();
  }

  String _formatProducts(Map<String, dynamic>? products) {
    if (products == null) return '-';
    final List<String> productList = [];
    products.forEach((key, value) {
      if (value is Map) {
        final name = value['productName'] ?? 'Unknown';
        final qty = value['quantity'] ?? 0;
        productList.add('$name ($qty)');
      }
    });
    return productList.join(', ');
  }

  List<Map<String, dynamic>> _getProductList(Map<String, dynamic>? products) {
    if (products == null) return [];
    final List<Map<String, dynamic>> productList = [];
    products.forEach((key, value) {
      if (value is Map) {
        productList.add({
          'name': value['productName'] ?? 'Unknown',
          'quantity': value['quantity'] ?? 0,
        });
      }
    });
    return productList;
  }

  String _formatDateForPrint(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return DateFormat('dd-MM-yyyy').format(dateTime);
    }
    return date.toString();
  }

  Future<void> _printAllReceipts() async {
    if (_receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipts to print')),
      );
      return;
    }

    try {
      // Generate PDF with all receipts, one per page
      final pdf = pw.Document();

      for (var receipt in _receipts) {
        final products = _getProductList(receipt['products']);
        final totalQuantity = receipt['totalQuantity'] ?? 0;
        final receiptNo = receipt['receiptNo']?.toString() ?? 'N/A';
        final date = _formatDateForPrint(receipt['date']);
        final supervisorId = receipt['supervisorId']?.toString() ?? 'N/A';
        final loomNo = receipt['weaverId']?.toString() ?? 'N/A';
        final name = receipt['weaverName']?.toString() ?? 'N/A';

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(40),
            build: (pw.Context context) {
              return _buildReceiptPage(
                  products, totalQuantity, receiptNo, date, supervisorId, loomNo, name);
            },
          ),
        );
      }

      final pdfBytes = await pdf.save();

      try {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
        );
      } catch (printError) {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'all_receipts.pdf',
        );
      }
    } catch (e, stackTrace) {
      print('Print error: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  pw.Widget _buildReceiptPage(
    List<Map<String, dynamic>> products,
    int totalQuantity,
    String receiptNo,
    String date,
    String supervisorId,
    String loomNo,
    String name,
  ) {
    final tableRows = <pw.TableRow>[];

    // Info Section - DATE and RECIEPT NO
    tableRows.add(
      pw.TableRow(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('DATE'),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(date),
          ),
        ],
      ),
    );
    tableRows.add(
      pw.TableRow(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('RECIEPT NO'),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(receiptNo),
          ),
        ],
      ),
    );
    tableRows.add(
      pw.TableRow(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('SUPERVISOR ID'),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(supervisorId),
          ),
        ],
      ),
    );
    tableRows.add(
      pw.TableRow(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('LOOM NO'),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(loomNo),
          ),
        ],
      ),
    );
    tableRows.add(
      pw.TableRow(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('NAME'),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(name),
          ),
        ],
      ),
    );
    tableRows.add(
      pw.TableRow(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('PRODUCT'),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('PCS'),
          ),
        ],
      ),
    );

    // Product rows
    if (products.isEmpty) {
      tableRows.add(
        pw.TableRow(
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('No products'),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('0'),
            ),
          ],
        ),
      );
    } else {
      for (var product in products) {
        tableRows.add(
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(product['name']?.toString().toUpperCase() ?? ''),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('${product['quantity'] ?? 0}'),
              ),
            ],
          ),
        );
      }
    }

    // Total row with thicker top border
    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.black, width: 2),
          ),
        ),
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            alignment: pw.Alignment.center,
            child: pw.Text(
              'TOTAL',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '$totalQuantity',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    // Combine header and table
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          alignment: pw.Alignment.center,
          child: pw.Text(
            'SHUNMUGAM TEXTILES',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          child: pw.Text(
            'KOMARAPALAYAM',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 2),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1),
          },
          children: tableRows,
        ),
      ],
    );
  }

  Future<Uint8List> _generatePdf(Map<String, dynamic> receipt) async {
    try {
      final pdf = pw.Document();
      final products = _getProductList(receipt['products']);
      final totalQuantity = receipt['totalQuantity'] ?? 0;
      final receiptNo = receipt['receiptNo']?.toString() ?? 'N/A';
      final date = _formatDateForPrint(receipt['date']);
      final supervisorId = receipt['supervisorId']?.toString() ?? 'N/A';
      final loomNo = receipt['weaverId']?.toString() ?? 'N/A';
      final name = receipt['weaverName']?.toString() ?? 'N/A';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return _buildReceiptPage(
                products, totalQuantity, receiptNo, date, supervisorId, loomNo, name);
          },
        ),
      );

      return pdf.save();
    } catch (e) {
      print('PDF generation error: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Production Report'),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: _showFilters ? 'Hide Filters' : 'Show Filters',
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ],
      ),
      floatingActionButton: _receipts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _printAllReceipts,
              backgroundColor: AppTheme.primaryBlue,
              icon: const Icon(Icons.print),
              label: const Text('Print All'),
            )
          : null,
      body: Column(
        children: [
          // Date Filter Card
          if (_showFilters)
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filter by Date Range',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildDatePickerField(
                          placeholder: 'Start Date',
                          value: _startDate,
                          onTap: _selectStartDate,
                        ),
                        const SizedBox(width: 12),
                        _buildDatePickerField(
                          placeholder: 'End Date',
                          value: _endDate,
                          onTap: _selectEndDate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Supervisor ID Filter
                    Text(
                      'Supervisor ID',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _supervisorIdController,
                      decoration: InputDecoration(
                        hintText: 'Enter Supervisor ID (optional)',
                        prefixIcon: const Icon(Icons.person_outline),
                        suffixIcon: _supervisorIdController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _supervisorIdController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // Loom No Filter
                    Text(
                      'Loom No (Weaver ID)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _loomNoController,
                      decoration: InputDecoration(
                        hintText: 'Enter Loom No (optional)',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        suffixIcon: _loomNoController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _loomNoController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // Receipt ID Filter
                    Text(
                      'Receipt ID',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _receiptIdController,
                      decoration: InputDecoration(
                        hintText: 'Enter Receipt ID (optional)',
                        prefixIcon: const Icon(Icons.receipt_long_outlined),
                        suffixIcon: _receiptIdController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _receiptIdController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _loadReceipts,
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

          // Report Summary
          if (_receipts.isNotEmpty)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16).copyWith(
                top: _showFilters ? 0 : 16,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Receipts: ${_receipts.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Total Quantity: ${_receipts.fold<int>(0, (sum, r) => sum + ((r['totalQuantity'] ?? 0) as num).toInt())}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),

          // Receipts List
          if (!_showFilters) const SizedBox(height: 12),

          Expanded(
            child: _receipts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assessment_outlined,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isLoading
                              ? 'Loading...'
                              : _startDate == null || _endDate == null
                                  ? 'Select date range to view report'
                                  : 'No receipts found',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _receipts.length,
                    itemBuilder: (context, index) {
                      final receipt = _receipts[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                          title: Text(
                            receipt['receiptNo'] ?? 'N/A',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(_formatDate(receipt['date'])),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildReportRow('Receipt No', receipt['receiptNo'] ?? 'N/A'),
                                  _buildReportRow('Date', _formatDate(receipt['date'])),
                                  _buildReportRow('Supervisor ID', receipt['supervisorId'] ?? 'N/A'),
                                  _buildReportRow('Supervisor Name', receipt['supervisorName'] ?? 'N/A'),
                                  _buildReportRow('Weaver ID', receipt['weaverId'] ?? 'N/A'),
                                  _buildReportRow('Weaver Name', receipt['weaverName'] ?? 'N/A'),
                                  const Divider(height: 24),
                                  Text(
                                    'Products:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _formatProducts(receipt['products']),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total Quantity:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        '${receipt['totalQuantity'] ?? 0}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppTheme.primaryBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _printSingleReceipt(receipt),
                                      icon: const Icon(Icons.print),
                                      label: const Text('Print This Receipt'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryBlue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField({
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
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
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
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
