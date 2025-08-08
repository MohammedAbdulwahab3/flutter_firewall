import 'package:hive_flutter/hive_flutter.dart';

class DenylistLocalRepo {
  static const String _boxName = 'denylist_box';
  static const String _key = 'denylist';
  DenylistLocalRepo._private();
  static final DenylistLocalRepo instance = DenylistLocalRepo._private();

  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  List<String> getAll() {
    final raw = _box.get(_key);
    if (raw == null) return <String>[];
    return (raw as List).map((e) => e.toString()).toList();
  }

  Future<void> saveAll(List<String> list) async {
    await _box.put(_key, list);
  }

  Future<void> add(String domain) async {
    final list = getAll();
    if (!list.contains(domain)) {
      list.add(domain);
      await saveAll(list);
    }
  }

  Future<void> remove(String domain) async {
    final list = getAll();
    list.removeWhere((d) => d == domain);
    await saveAll(list);
  }
}
