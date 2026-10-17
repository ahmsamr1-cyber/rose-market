import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';

const String marketName = "روز ماركت";
const String adminPin = "20011986";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if(!prefs.containsKey('usd_syp')) await prefs.setDouble('usd_syp', 15000);
  if(!prefs.containsKey('usd_try')) await prefs.setDouble('usd_try', 34);
  runApp(const RoseApp());
}

class RoseApp extends StatelessWidget {
  const RoseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0F0F0F)),
      home: const HomePage(),
    );
  }
}

class DBHelper {
  static Database? _db;
  static Future<Database> get db async {
    if(_db != null) return _db!;
    _db = await openDatabase(p.join(await getDatabasesPath(), 'rose.db'),
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE products(code TEXT PRIMARY KEY, barcode TEXT, name TEXT, unit TEXT, price_syp REAL)');
        await db.execute('CREATE INDEX idx_barcode ON products(barcode)');
      }, version: 1);
    return _db!;
  }
  static Future<void> upsert(Map<String, dynamic> prod) async {
    final d = await db;
    await d.insert('products', prod, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  static Future<Map?> byBarcode(String bc) async {
    final d = await db;
    var res = await d.query('products', where: 'barcode = ?', whereArgs: [bc.trim()]);
    if(res.isEmpty) res = await d.query('products', where: 'code = ?', whereArgs: [bc.trim()]);
    return res.isNotEmpty ? res.first : null;
  }
  static Future<List<Map>> all({String? q}) async {
    final d = await db;
    if(q==null || q.isEmpty) return await d.query('products', orderBy: 'name');
    return await d.query('products', where: 'name LIKE ? OR barcode LIKE ? OR code LIKE ?', whereArgs: ['%$q%','%$q%','%$q%'], orderBy: 'name');
  }
  static Future<void> delete(String code) async {
    final d = await db;
    await d.delete('products', where: 'code = ?', whereArgs: [code]);
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront, size: 80, color: Colors.white),
              const SizedBox(height: 12),
              const Text(marketName, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const Text('معرفة الأسعار', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 50),
              SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(icon: const Icon(Icons.qr_code_scanner, size: 28), label: const Text('وضع الزبون - مسح السعر', style: TextStyle(fontSize: 18)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: ()=> Navigator.push(ctx, MaterialPageRoute(builder: (_)=> const CustomerPage())))),
              const SizedBox(height: 16),
              TextButton.icon(icon: const Icon(Icons.lock, color: Colors.white30), label: const Text('إدارة 🔒', style: TextStyle(color: Colors.white30)), onPressed: ()=> _showPin(ctx))
            ],
          ),
        ),
      ),
    );
  }
  void _showPin(BuildContext ctx){
    final ctrl = TextEditingController();
    showDialog(context: ctx, builder: (_)=> AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('رمز الإدارة'),
      content: TextField(controller: ctrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'أدخل الرمز'), autofocus: true),
      actions: [TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('إلغاء')), ElevatedButton(onPressed: (){
        if(ctrl.text.trim() == adminPin){
          Navigator.pop(ctx);
          Navigator.push(ctx, MaterialPageRoute(builder: (_)=> const AdminPage()));
        } else {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('رمز خاطئ')));
        }
      }, child: const Text('دخول'))],
    ));
  }
}

class CustomerPage extends StatefulWidget { const CustomerPage({super.key}); @override State<CustomerPage> createState()=> _CustomerPageState(); }
class _CustomerPageState extends State<CustomerPage> {
  String? lastCode;
  Map? product;
  double weight = 1.0;
  double usdSyp = 15000, usdTry = 34;
  String currency = 'SYP';
  final weightCtrl = TextEditingController(text: '1');
  @override void initState(){ super.initState(); _loadRates(); }
  Future<void> _loadRates() async {
    final pref = await SharedPreferences.getInstance();
    setState((){ usdSyp = pref.getDouble('usd_syp') ?? 15000; usdTry = pref.getDouble('usd_try') ?? 34; });
  }
  @override Widget build(BuildContext ctx){
    return Scaffold(
      appBar: AppBar(title: const Text(marketName), backgroundColor: Colors.black, actions: [DropdownButton<String>(value: currency, dropdownColor: Colors.black, underline: const SizedBox(), style: const TextStyle(color: Colors.white), items: const [DropdownMenuItem(value: 'SYP', child: Text('SYP')), DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'TRY', child: Text('TRY'))], onChanged: (v){ if(v!=null) setState(()=> currency=v); })]),
      body: Column(children: [
        Expanded(flex: 3, child: MobileScanner(onDetect: (cap) async {
          final code = cap.barcodes.first.rawValue;
          if(code==null || code==lastCode) return;
          lastCode = code;
          var prod = await DBHelper.byBarcode(code);
          if(!mounted) return;
          if(prod!=null){
            setState((){ product = prod; weightCtrl.text = '1'; weight = 1; });
          } else {
            setState(()=> product = {'name': 'المادة غير موجودة', 'code': code, 'barcode': code, 'unit':'Pcs','price_syp':0, 'notFound': true});
          }
          await Future.delayed(const Duration(seconds: 2));
          lastCode = null;
        })),
        Expanded(flex: 3, child: Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: product==null ? const Center(child: Text('وجه الكاميرا نحو الباركود', style: TextStyle(color: Colors.white54))) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('باركود: ${product!['barcode']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 4),
          Text(product!['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('الوحدة: ${product!['unit']=='Kg' ? 'كيلو' : 'قطعة'}', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 12),
          if(product!['unit']=='Kg') Row(children: [const Text('الوزن:'), const SizedBox(width: 8), SizedBox(width: 100, child: TextField(controller: weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true), onChanged: (v){ setState(()=> weight = double.tryParse(v) ?? 1.0); })), const SizedBox(width: 8), Text('x ${product!['price_syp']}')]),
          const SizedBox(height: 12),
          if(product!['notFound'] != true) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('SYP: ${(product!['price_syp']*(product!['unit']=='Kg'?weight:1)).toStringAsFixed(0)}'), Text('USD: ${((product!['price_syp']*(product!['unit']=='Kg'?weight:1))/usdSyp).toStringAsFixed(2)} \$'), Text('TRY: ${(((product!['price_syp']*(product!['unit']=='Kg'?weight:1))/usdSyp)*usdTry).toStringAsFixed(2)}')]),
          ])),
          const Spacer(),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: ()=> setState(()=> product=null), child: const Text('مسح جديد')))
        ])))
      ]),
    );
  }
}

class AdminPage extends StatefulWidget { const AdminPage({super.key}); @override State<AdminPage> createState()=> _AdminPageState(); }
class _AdminPageState extends State<AdminPage> {
  List<Map> products = [];
  String q = '';
  double usdSyp = 15000, usdTry = 34;
  final usdCtrl = TextEditingController();
  final tryCtrl = TextEditingController();
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    final pref = await SharedPreferences.getInstance();
    usdSyp = pref.getDouble('usd_syp') ?? 15000;
    usdTry = pref.getDouble('usd_try') ?? 34;
    usdCtrl.text = usdSyp.toStringAsFixed(0);
    tryCtrl.text = usdTry.toStringAsFixed(2);
    var list = await DBHelper.all(q: q);
    setState(()=> products = list);
  }
  Future<void> _import() async {
    try{
      var res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx','xls']);
      if(res==null) return;
      var bytes = res.files.first.bytes ?? await File(res.files.first.path!).readAsBytes();
      var excel = Excel.decodeBytes(bytes);
      var sheet = excel.tables[excel.tables.keys.first]!;
      int added=0, updated=0;
      var allExisting = await DBHelper.all();
      var existingCodes = allExisting.map((e)=> e['code'].toString()).toSet();
      for(var i=1;i<sheet.rows.length;i++){
        var row = sheet.rows[i];
        if(row.length < 3) continue;
        String code = row[0]?.value?.toString().trim() ?? '';
        String barcode = row.length>1 ? (row[1]?.value?.toString().trim() ?? '') : '';
        String name = row.length>2 ? (row[2]?.value?.toString().trim() ?? '') : '';
        String unitRaw = row.length>3 ? (row[3]?.value?.toString().trim() ?? '') : 'قطعة';
        String unit = unitRaw.contains('كغ') || unitRaw.toLowerCase().contains('kg') ? 'Kg' : 'Pcs';
        double price = 0;
        if(row.length>4) price = double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0;
        if(code.isEmpty || name.isEmpty) continue;
        if(barcode.isEmpty) barcode = code;
        bool isNew = !existingCodes.contains(code);
        await DBHelper.upsert({'code': code, 'barcode': barcode, 'name': name, 'unit': unit, 'price_syp': price});
        if(isNew) added++; else updated++;
        existingCodes.add(code);
      }
      await _load();
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم: إضافة $added - تحديث $updated')));
    }catch(e){
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }
  Future<void> _saveRates() async {
    final pref = await SharedPreferences.getInstance();
    double u = double.tryParse(usdCtrl.text) ?? usdSyp;
    double t = double.tryParse(tryCtrl.text) ?? usdTry;
    await pref.setDouble('usd_syp', u);
    await pref.setDouble('usd_try', t);
    setState(()=> {usdSyp=u, usdTry=t});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ سعر الصرف')));
  }
  @override Widget build(BuildContext ctx){
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة روز ماركت'), backgroundColor: Colors.black),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(12), color: const Color(0xFF1E1E1E), child: Column(children: [
          const Text('أسعار الصرف', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: usdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '1\$ = ل.س', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: tryCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '1\$ = تركي', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _saveRates, child: const Text('حفظ'))
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file), label: const Text('استيراد من الأمين'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange))),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: ()=> _showAddDialog(), icon: const Icon(Icons.add), label: const Text('مادة'))
          ])
        ])),
        Padding(padding: const EdgeInsets.all(8), child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث', border: OutlineInputBorder(), isDense: true), onChanged: (v){ q=v; _load(); })),
        Expanded(child: ListView.builder(itemCount: products.length, itemBuilder: (_,i){
          var pItem = products[i];
          return ListTile(title: Text(pItem['name']), subtitle: Text('${pItem['code']} - ${pItem['barcode']} - ${pItem['unit']=='Kg'?'كيلو':'قطعة'} - ${pItem['price_syp']} ل.س'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: ()=> _showAddDialog(edit: pItem)), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async { await DBHelper.delete(pItem['code']); _load(); })]));
        }))
      ]),
    );
  }
  void _showAddDialog({Map? edit}){
    final codeCtrl = TextEditingController(text: edit?['code']?.toString() ?? '');
    final barCtrl = TextEditingController(text: edit?['barcode']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: edit?['name']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: edit?['price_syp']?.toString() ?? '');
    String unit = edit?['unit'] ?? 'Pcs';
    showDialog(context: context, builder: (BuildContext dialogCtx)=> StatefulBuilder(builder: (ctx2,setSt)=> AlertDialog(
      title: Text(edit==null ? 'إضافة مادة' : 'تعديل مادة'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'رمز المادة'), enabled: edit==null),
        TextField(controller: barCtrl, decoration: const InputDecoration(labelText: 'الباركود')),
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
        TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر سوري')),
        DropdownButton<String>(value: unit, items: const [DropdownMenuItem(value: 'Pcs', child: Text('قطعة')), DropdownMenuItem(value: 'Kg', child: Text('كيلو'))], onChanged: (v){ setSt(()=> unit=v!); })
      ])),
      actions: [TextButton(onPressed: ()=> Navigator.pop(dialogCtx), child: const Text('إلغاء')), ElevatedButton(onPressed: () async {
        if(codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
        await DBHelper.upsert({'code': codeCtrl.text.trim(), 'barcode': barCtrl.text.trim().isEmpty ? codeCtrl.text.trim() : barCtrl.text.trim(), 'name': nameCtrl.text.trim(), 'unit': unit, 'price_syp': double.tryParse(priceCtrl.text) ?? 0});
        Navigator.pop(dialogCtx); _load();
      }, child: const Text('حفظ'))],
    )));
  }
}
