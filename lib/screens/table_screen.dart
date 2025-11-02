import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../state/auth.dart';
import '../config.dart';

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

final areasLiteProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final headers = {'Authorization': 'Bearer $token', 'Accept': 'application/json'};

  final r = await http.get(Uri.parse('${AppConfig.apiBase}/areas'), headers: headers);
  if (r.statusCode != 200) {
    throw Exception('Areas load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['areas'] as List?) ?? [];
  return list
      .map((e) => {
    '_id': (e as Map<String, dynamic>)['_id'],
    'name': (e)['name'],
  })
      .cast<Map<String, dynamic>>()
      .toList();
});

final tablesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final headers = {'Authorization': 'Bearer $token', 'Accept': 'application/json'};

  final r = await http.get(Uri.parse('${AppConfig.apiBase}/tables'), headers: headers);
  if (r.statusCode != 200) {
    throw Exception('Tables load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['tables'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});
  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  final _picker = ImagePicker();
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _canManage {
    final role = (ref.read(authStateProvider)?.roleName ?? '').toLowerCase();
    return role == 'admin' || role == 'manager';
  }

  Map<String, String> _headers() {
    final token = ref.read(authStateProvider)?.token ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    };
  }

  Map<String, String> _authAcceptHeadersOnly() {
    final token = ref.read(authStateProvider)?.token ?? '';
    return {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
  }

  Future<XFile?> _pick(ImageSource src) => _picker.pickImage(
    source: src,
    imageQuality: 88,
    requestFullMetadata: false,
  );

  Future<void> _create({
    required String name,
    required int capacity,
    required String areaId,
    XFile? image,
  }) async {
    final m = http.MultipartRequest('POST', Uri.parse('${AppConfig.apiBase}/tables'))
      ..headers.addAll(_authAcceptHeadersOnly())
      ..fields['name'] = name
      ..fields['capacity'] = capacity.toString()
      ..fields['areaId'] = areaId;
    if (image != null) {
      m.files.add(await http.MultipartFile.fromPath('image', image.path, filename: image.name));
    }
    final s = await m.send();
    final body = await s.stream.bytesToString();
    if (s.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Create failed', s.statusCode, body));
    }
  }

  Future<void> _update({
    required String id,
    String? name,
    int? capacity,
    String? areaId,
    XFile? image,
    bool removeImage = false,
  }) async {
    final m = http.MultipartRequest('PUT', Uri.parse('${AppConfig.apiBase}/tables/$id'))
      ..headers.addAll(_authAcceptHeadersOnly());
    if (name != null) m.fields['name'] = name;
    if (capacity != null) m.fields['capacity'] = capacity.toString();
    if (areaId != null && areaId.isNotEmpty) m.fields['areaId'] = areaId;
    if (removeImage) m.fields['removeImage'] = 'true';
    if (image != null) {
      m.files.add(await http.MultipartFile.fromPath('image', image.path, filename: image.name));
    }
    final s = await m.send();
    final body = await s.stream.bytesToString();
    if (s.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Update failed', s.statusCode, body));
    }
  }

  Future<void> _delete(String id) async {
    final r =
    await http.delete(Uri.parse('${AppConfig.apiBase}/tables/$id'), headers: _headers());
    if (r.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Delete failed', r.statusCode, r.body));
    }
  }

  Future<void> _openForm({Map<String, dynamic>? table}) async {
    final isEdit = table != null;
    final name = TextEditingController(text: table?['name'] ?? '');
    final capacityCtrl = TextEditingController(text: (table?['capacity'] ?? 1).toString());
    String? pickedAreaId = (() {
      final a = table?['area'];
      if (a is Map && a['_id'] is String) return a['_id'] as String;
      if (a is String) return a;
      return null;
    })();

    XFile? pickedImage;
    bool removeImage = false;
    final String existingImageUrl = _imgUrl(table?['image'] as String?);

    final key = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFDF6EC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final bottom = MediaQuery.of(sheetCtx).viewInsets.bottom;

        final areasAsync = ref.read(areasLiteProvider);

        Future<void> save() async {
          if (!key.currentState!.validate()) return;
          if (pickedAreaId == null || pickedAreaId!.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Please select an area')));
            return;
          }

          final capVal = int.tryParse(capacityCtrl.text.trim());
          if (capVal == null || capVal < 1) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Capacity must be >= 1')));
            return;
          }

          final nav = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
          try {
            if (isEdit) {
              await _update(
                id: table!['_id'],
                name: name.text.trim(),
                capacity: capVal,
                areaId: pickedAreaId,
                image: pickedImage,
                removeImage: removeImage && pickedImage == null,
              );
            } else {
              await _create(
                name: name.text.trim(),
                capacity: capVal,
                areaId: pickedAreaId!,
                image: pickedImage,
              );
            }
            if (nav.canPop()) nav.pop();
            if (nav.canPop()) nav.pop();

            ref.refresh(tablesProvider);
            messenger.showSnackBar(
                SnackBar(content: Text(isEdit ? 'Table updated' : 'Table created')));
          } catch (e) {
            if (nav.canPop()) nav.pop();
            messenger.showSnackBar(SnackBar(content: Text(e.toString())));
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Form(
            key: key,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4))),
                ),
                const SizedBox(height: 12),
                Text(isEdit ? 'Edit Table' : 'Add Table',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFFF7043))),
                const SizedBox(height: 16),

                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Table Name',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: capacityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Capacity',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Required';
                    final d = int.tryParse(t);
                    if (d == null || d < 1) return 'Must be >= 1';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                const Text('Area', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                areasAsync.when(
                  loading: () => const Center(
                      child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator())),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Failed to load areas: $e',
                        style: const TextStyle(color: Colors.red)),
                  ),
                  data: (areas) {
                    if (areas.isEmpty) {
                      return const Text('No areas found. Create an area first.',
                          style: TextStyle(color: Colors.red));
                    }
                    final valid = areas.any((a) => a['_id'] == pickedAreaId);
                    if (!valid) pickedAreaId = areas.first['_id'] as String;

                    return DropdownButtonFormField<String>(
                      value: pickedAreaId,
                      items: [
                        for (final a in areas)
                          DropdownMenuItem(
                            value: a['_id'] as String,
                            child: Text((a['name'] ?? 'No name') as String, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => pickedAreaId = v),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                const Text('Photo', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 68,
                        height: 68,
                        color: Colors.white,
                        child: Builder(
                          builder: (_) {
                            if (pickedImage != null) {
                              return Image.file(
                                File(pickedImage!.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                              );
                            }
                            if (!removeImage && existingImageUrl.isNotEmpty) {
                              return Image.network(
                                existingImageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                              );
                            }
                            return const Center(child: Icon(Icons.image_outlined, color: Colors.black26));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final x = await _pick(ImageSource.gallery);
                              if (x != null) {
                                setState(() {
                                  pickedImage = x;
                                  removeImage = false;
                                });
                              }
                            },
                            icon: const Icon(Icons.photo),
                            label: const Text('Gallery'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final x = await _pick(ImageSource.camera);
                              if (x != null) {
                                setState(() {
                                  pickedImage = x;
                                  removeImage = false;
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Camera'),
                          ),
                          if (isEdit && (existingImageUrl.isNotEmpty || pickedImage != null))
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  pickedImage = null;
                                  removeImage = true;
                                });
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _canManage ? save : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF7043),
                            foregroundColor: Colors.white),
                        child: Text(isEdit ? 'Save' : 'Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(Map<String, dynamic> t) {
    final name = (t['name'] ?? '') as String;
    final cap = (t['capacity'] as num?)?.toInt() ?? 1;
    final areaName = (() {
      final a = t['area'];
      if (a is Map && a['name'] is String) return a['name'] as String;
      return 'Unknown area';
    })();
    final status = (t['status'] ?? 'available') as String;
    final badgeColor = switch (status) {
      'occupied' => const Color(0xFFB71C1C),
      'reserved' => const Color(0xFFF57C00),
      _ => const Color(0xFF2E7D32),
    };

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(name)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(.25)),
                ),
                child: Text(status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Area: $areaName'),
              const SizedBox(height: 6),
              Text('Capacity: $cap'),
            ],
          ),
          actions: [
            if (_canManage)
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _openForm(table: t);
                  },
                  child: const Text('Edit')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFFFFF3E8), Color(0xFFFFE6D6)]),
          boxShadow: const [
            BoxShadow(color: Color(0x15000000), blurRadius: 6, offset: Offset(0, 3))
          ],
          border: Border.all(color: const Color(0x1A000000)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF6A3B13))),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: badgeColor.withOpacity(.25)),
                    ),
                    child: Text(status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') _openForm(table: t);
                      if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete Table'),
                            content: Text('Delete "$name"?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF7043)),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await _delete(t['_id']);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Table deleted')));
                              ref.refresh(tablesProvider);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(e.toString())));
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'view', child: Text('View')),
                      if (_canManage) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (_canManage)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Area: $areaName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.brown.shade800)),
              const SizedBox(height: 2),
              Text('Capacity: $cap',
                  style: TextStyle(fontSize: 12.5, color: Colors.brown.shade700)),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(tablesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      appBar: AppBar(
        title: const Text('Tables', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFFFF7043),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search tables…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: tablesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e', textAlign: TextAlign.center),
                ),
              ),
              data: (all) {
                final items = all.where((m) {
                  final n = (m['name'] ?? '').toString().toLowerCase();
                  final aName = (() {
                    final a = m['area'];
                    if (a is Map && a['name'] is String) {
                      return (a['name'] as String).toLowerCase();
                    }
                    return '';
                  })();
                  return _query.isEmpty || n.contains(_query) || aName.contains(_query);
                }).toList();

                if (items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(tablesProvider),
                    child: ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.table_bar, size: 64, color: Colors.black26),
                        SizedBox(height: 12),
                        Center(
                            child: Text('No tables found',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600))),
                        SizedBox(height: 4),
                        Center(
                            child: Text('Try search or add a new table.',
                                style: TextStyle(color: Colors.black54))),
                        SizedBox(height: 80),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(tablesProvider),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.02),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _card(items[i]),
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
