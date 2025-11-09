import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../state/auth.dart';
import '../config.dart';
import '../services/socket_service.dart';

String _imgUrl(String? p) {
  if (p == null || p.isEmpty) return '';
  return p.startsWith('http')
      ? p
      : '${AppConfig.hostBase}${p.startsWith('/') ? '' : '/'}$p';
}

String _serverMsg(String action, int code, String body) {
  try {
    final d = jsonDecode(body);
    final msg = (d['error'] ?? d['message'] ?? body).toString();
    return '$action ($code): $msg';
  } catch (_) {
    return '$action ($code): $body';
  }
}

final itemsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/items'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) {
    throw Exception('Load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['items'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

final categoriesProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/categories'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) {
    throw Exception('Category load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['categories'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

class ItemScreen extends ConsumerStatefulWidget {
  const ItemScreen({super.key});
  @override
  ConsumerState<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends ConsumerState<ItemScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final SocketService _socketService = SocketService();

  bool get _canManage {
    final role = (ref.read(authStateProvider)?.roleName ?? '').toLowerCase();
    return role == 'admin' || role == 'manager';
  }

  Map<String, String> _headers() {
    final token = ref.read(authStateProvider)?.token ?? '';
    return {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
  }

  @override
  void initState() {
    super.initState();

    final restaurantId = ref.read(authStateProvider)?.restaurantId ?? '';
    if (restaurantId.isNotEmpty) {
      _socketService.connect(AppConfig.socketBase, restaurantId);

      _socketService.onItemCreated((item) => ref.refresh(itemsProvider));
      _socketService.onItemUpdated((item) => ref.refresh(itemsProvider));
      _socketService.onItemDeleted((id) => ref.refresh(itemsProvider));
      _socketService.onCategoryCreated((_) => ref.refresh(categoriesProvider));
      _socketService.onCategoryUpdated((_) => ref.refresh(categoriesProvider));
      _socketService.onCategoryDeleted((_) => ref.refresh(categoriesProvider));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _socketService.disconnect();
    super.dispose();
  }
  Future<void> _delete(String id) async {
    final r = await http.delete(
      Uri.parse('${AppConfig.apiBase}/items/$id'),
      headers: _headers(),
    );
    if (r.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Delete failed', r.statusCode, r.body));
    }
  }

  Future<void> _openForm({Map<String, dynamic>? item}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFDF6EC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ItemFormSheet(item: item, headers: _headers),
    );
    if (changed == true && mounted) {
      ref.refresh(itemsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      appBar: AppBar(
        title: const Text('Items', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFFF7043),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
              ),
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: $e')),
              ),
              data: (all) {
                final items = all.where((m) {
                  final n = (m['name'] ?? '').toString().toLowerCase();
                  final d = (m['description'] ?? '').toString().toLowerCase();
                  return _query.isEmpty ||
                      n.contains(_query) ||
                      d.contains(_query);
                }).toList();

                if (items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(itemsProvider),
                    child: ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.fastfood, size: 64, color: Colors.black26),
                        SizedBox(height: 12),
                        Center(child: Text('No items found')),
                        SizedBox(height: 80),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(itemsProvider),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.86,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final name = (it['name'] ?? '').toString();
                      final desc = (it['description'] ?? '').toString();
                      final url = _imgUrl(it['image'] as String?);
                      final variants =
                          (it['variants'] as List?)?.cast<Map<String, dynamic>>() ??
                              [];
                      final available = (it['available'] as bool?) ?? true;
                      final catName = it['category']?['name'] ?? '';

                      final priceLine = variants.isNotEmpty
                          ? (() {
                        final v = variants.first;
                        final u = (v['unit'] ?? '').toString();
                        final p = (v['price'] as num?)?.toDouble() ?? 0.0;
                        return u.isEmpty
                            ? 'Rs ${p.toStringAsFixed(2)}'
                            : '$u • Rs ${p.toStringAsFixed(2)}';
                      })()
                          : '';

                      return InkWell(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(name),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (url.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        url,
                                        height: 160,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image_outlined),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  if (desc.trim().isNotEmpty) Text(desc),
                                  if (catName.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Category: $catName',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))
                                  ],
                                  if (variants.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    const Text('Variants',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    ...variants.map((v) {
                                      final u = (v['unit'] ?? '').toString();
                                      final p =
                                          (v['price'] as num?)?.toDouble() ?? 0.0;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Text(u.isEmpty
                                            ? 'Rs ${p.toStringAsFixed(2)}'
                                            : '$u — Rs ${p.toStringAsFixed(2)}'),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                            ),
                            actions: [
                              if (_canManage)
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _openForm(item: it);
                                  },
                                  child: const Text('Edit'),
                                ),
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close')),
                            ],
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(colors: [
                              Color(0xFFFFF3E8),
                              Color(0xFFFFE6D6)
                            ]),
                            border: Border.all(color: const Color(0x1A000000)),
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16)),
                                child: AspectRatio(
                                  aspectRatio: 16 / 10,
                                  child: url.isEmpty
                                      ? const ColoredBox(
                                    color: Colors.white,
                                    child: Center(
                                        child: Icon(Icons.image_outlined,
                                            color: Colors.black26)),
                                  )
                                      : Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                    const Center(
                                        child: Icon(Icons
                                            .broken_image_outlined)),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                const EdgeInsets.fromLTRB(10, 8, 4, 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16),
                                          ),
                                          if (priceLine.isNotEmpty)
                                            Text(
                                              priceLine,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 12.5,
                                                  color:
                                                  Colors.brown.shade800),
                                            ),
                                          if (catName.isNotEmpty)
                                            Text(
                                              catName,
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                  Colors.brown.shade600),
                                            ),
                                          Text(
                                            desc.isEmpty
                                                ? 'No description'
                                                : desc,
                                            maxLines: 2,
                                            overflow:
                                            TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12.5,
                                                color:
                                                Colors.brown.shade700),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_canManage)
                                      PopupMenuButton<String>(
                                        onSelected: (v) async {
                                          if (v == 'edit') _openForm(item: it);
                                          if (v == 'delete') {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title:
                                                const Text('Delete Item'),
                                                content:
                                                Text('Delete "$name"?'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context, false),
                                                      child:
                                                      const Text('Cancel')),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                        backgroundColor:
                                                        const Color(
                                                            0xFFFF7043)),
                                                    child:
                                                    const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              try {
                                                await _delete(it['_id']);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                      context)
                                                      .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Item deleted')));
                                                  ref.refresh(itemsProvider);
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                      context)
                                                      .showSnackBar(SnackBar(
                                                      content: Text(
                                                          e.toString())));
                                                }
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit')),
                                          PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Delete')),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton(
        backgroundColor: const Color(0xFFFF7043),
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
    );
  }
}

// ------------------ Form Sheet ------------------

class _ItemFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? item;
  final Map<String, String> Function() headers;
  const _ItemFormSheet({required this.item, required this.headers});

  @override
  ConsumerState<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends ConsumerState<_ItemFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late TextEditingController nameCtrl;
  late TextEditingController descCtrl;
  bool available = true;
  XFile? picked;
  bool removeImage = false;
  String? selectedCategoryId;

  final List<_VariantRow> rows = [];

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    nameCtrl = TextEditingController(text: it?['name'] ?? '');
    descCtrl = TextEditingController(text: it?['description'] ?? '');
    available = (it?['available'] as bool?) ?? true;
    selectedCategoryId = it?['category']?['_id']?.toString();

    final vs = (it?['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (vs.isEmpty) {
      rows.add(_VariantRow());
    } else {
      for (final v in vs) {
        rows.add(_VariantRow(
            unit: v['unit']?.toString() ?? '',
            price: (v['price'] as num?)?.toString() ?? ''));
      }
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    for (final r in rows) {
      r.unitCtrl.dispose();
      r.priceCtrl.dispose();
    }
    super.dispose();
  }

  Future<XFile?> _pick(ImageSource src) =>
      _picker.pickImage(source: src, imageQuality: 88, requestFullMetadata: false);

  List<Map<String, dynamic>> _collectVariants() {
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final u = r.unitCtrl.text.trim();
      final p = r.priceCtrl.text.trim();
      if (u.isEmpty || p.isEmpty) continue;
      final val = double.tryParse(p);
      if (val == null || val < 0) continue;
      out.add({'unit': u, 'price': val});
    }
    return out;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category')));
      return;
    }

    final variants = _collectVariants();
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one valid unit & price')));
      return;
    }

    final isEdit = widget.item != null;
    final uri = isEdit
        ? Uri.parse('${AppConfig.apiBase}/items/${widget.item!['_id']}')
        : Uri.parse('${AppConfig.apiBase}/items');

    final m = http.MultipartRequest(isEdit ? 'PUT' : 'POST', uri)
      ..headers.addAll(widget.headers())
      ..fields['name'] = nameCtrl.text.trim()
      ..fields['available'] = available.toString()
      ..fields['variants'] = jsonEncode(variants)
      ..fields['categoryId'] = selectedCategoryId!;

    final d = descCtrl.text.trim();
    if (d.isNotEmpty) m.fields['description'] = d;

    if (isEdit && removeImage) m.fields['removeImage'] = 'true';
    if (picked != null) {
      m.files.add(await http.MultipartFile.fromPath('image', picked!.path,
          filename: picked!.name));
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
        const Center(child: CircularProgressIndicator()));
    try {
      final s = await m.send();
      final body = await s.stream.bytesToString();
      if (mounted) Navigator.pop(context);

      if (s.statusCode ~/ 100 != 2) {
        throw Exception(_serverMsg(
            isEdit ? 'Update failed' : 'Create failed', s.statusCode, body));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider);

    return Padding(
      padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          top: 14),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 5,
              width: 40,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(3)),
            ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  cats.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Category load error: $e'),
                    data: (list) {
                      if (selectedCategoryId != null &&
                          !list.any((c) => c['_id'].toString() == selectedCategoryId)) {
                        selectedCategoryId = null;
                      }

                      return DropdownButtonFormField<String>(
                        decoration:
                        const InputDecoration(labelText: 'Category'),
                        value: selectedCategoryId,
                        items: list
                            .map((c) => DropdownMenuItem<String>(
                          value: c['_id'].toString(),
                          child: Text(c['name'].toString()),
                        ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => selectedCategoryId = v);
                        },
                        validator: (v) =>
                        v == null ? 'Select category' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: available,
                    onChanged: (v) => setState(() => available = v),
                    title: const Text('Available'),
                    activeColor: const Color(0xFFFF7043),
                  ),
                  const SizedBox(height: 8),
                  ...rows.map((r) => r),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => rows.add(_VariantRow())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Variant'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF7043)),
                          child: Text(widget.item == null
                              ? 'Create Item'
                              : 'Save Changes'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantRow extends StatefulWidget {
  final TextEditingController unitCtrl;
  final TextEditingController priceCtrl;

  _VariantRow({String? unit, String? price})
      : unitCtrl = TextEditingController(text: unit),
        priceCtrl = TextEditingController(text: price ?? '');

  @override
  State<_VariantRow> createState() => _VariantRowState();
}

class _VariantRowState extends State<_VariantRow> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: widget.unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: widget.priceCtrl,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
