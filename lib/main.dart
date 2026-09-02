import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FmpcTrackerApp());
}

class FmpcTrackerApp extends StatelessWidget {
  const FmpcTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FMPC Parcel Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FMPC Parcel Tracker'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(IconData(0xe571, fontFamily: 'MaterialIcons')),
              label: const Text('Outbound Scanning (পাঠানো পার্সেল)', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen(isOutbound: true)),
              ),
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              icon: const Icon(IconData(0xe3ae, fontFamily: 'MaterialIcons')),
              label: const Text('Inbound Scanning (রিটার্ন পার্সেল)', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen(isOutbound: false)),
              ),
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              icon: const Icon(IconData(0xe3b7, fontFamily: 'MaterialIcons')),
              label: const Text('Excel Report ডাউনলোড করুন', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              onPressed: () => _exportToExcel(context),
            ),
            const SizedBox(height: 20),
            const Text('পার্সেল তালিকা (সর্বশেষ লাইভ ডাটা):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('parcels').orderBy('outbound_date', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Center(child: Text('কোনো ডাটা পাওয়া যায়নি'));
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final trackingId = docs[index].id;
                      final status = data['status'] ?? 'Unknown';
                      final outboundDate = (data['outbound_date'] as Timestamp?)?.toDate();
                      
                      bool isDelayed = false;
                      if (status == 'Outbound' && outboundDate != null) {
                        isDelayed = DateTime.now().difference(outboundDate).inDays > 7;
                      }

                      return Card(
                        color: status == 'Lost' ? Colors.red.shade100 : (isDelayed ? Colors.orange.shade100 : Colors.white),
                        child: ListTile(
                          title: Text('ID: $trackingId', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Status: $status ${isDelayed ? "(>7 দিন বিলম্ব)" : ""}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (status != 'Lost')
                                IconButton(
                                  icon: const Icon(Icons.warning, color: Colors.red),
                                  onPressed: () => _markAsLost(context, trackingId),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _markAsLost(BuildContext context, String trackingId) {
    FirebaseFirestore.instance.collection('parcels').doc(trackingId).update({
      'status': 'Lost',
      'updated_at': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$trackingId - চিহ্নিত করা হয়েছে "Lost" হিসেবে')));
  }

  static Future<void> _exportToExcel(BuildContext context) async {
    final snapshot = await FirebaseFirestore.instance.collection('parcels').get();
    var excel = excel_lib.Excel.createExcel();
    var sheet = excel['Sheet1'];

    sheet.appendRow([
      excel_lib.TextCellValue('Tracking ID'),
      excel_lib.TextCellValue('Status'),
      excel_lib.TextCellValue('Outbound Date'),
      excel_lib.TextCellValue('Inbound Date')
    ]);

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final outboundStr = data['outbound_date'] != null 
          ? DateFormat('yyyy-MM-dd HH:mm').format((data['outbound_date'] as Timestamp).toDate()) 
          : '';
      final inboundStr = data['inbound_date'] != null 
          ? DateFormat('yyyy-MM-dd HH:mm').format((data['inbound_date'] as Timestamp).toDate()) 
          : '';

      sheet.appendRow([
        excel_lib.TextCellValue(doc.id),
        excel_lib.TextCellValue(data['status'] ?? ''),
        excel_lib.TextCellValue(outboundStr),
        excel_lib.TextCellValue(inboundStr),
      ]);
    }

    final directory = await getTemporaryDirectory();
    final file = File("${directory.path}/FMPC_Parcel_Report.xlsx");
    await file.writeAsBytes(excel.save()!);

    await Share.shareXFiles([XFile(file.path)], text: 'FMPC Parcel Tracking Report');
  }
}

class ScanScreen extends StatefulWidget {
  final bool isOutbound;
  const ScanScreen({super.key, required this.isOutbound});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      setState(() => isProcessing = true);
      final code = barcodes.first.rawValue!;

      final docRef = FirebaseFirestore.instance.collection('parcels').doc(code);

      if (widget.isOutbound) {
        await docRef.set({
          'status': 'Outbound',
          'outbound_date': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await docRef.set({
          'status': 'Returned',
          'inbound_date': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('সফলভাবে রেকর্ড করা হয়েছে: $code')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOutbound ? 'Outbound Scan' : 'Inbound Scan'),
      ),
      body: MobileScanner(
        onDetect: _onDetect,
      ),
    );
  }
}
