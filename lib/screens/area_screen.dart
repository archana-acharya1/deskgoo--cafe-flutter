import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../state/auth.dart';
import 'tables_by_area_screen.dart';
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

final areasProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final headers = {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  final r =
  await http.get(Uri.parse('${AppConfig.apiBase}/areas'), headers: headers);
  if (r.statusCode != 200) {
    throw Exception('Load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['areas'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

final areaTablesProvider =
FutureProvider.family<List<Map<String, dynamic>>, String>((ref, areaId) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final headers = {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };
  final r = await http
      .get(Uri.parse('${AppConfig.apiBase}/tables?areaId=$areaId'), headers: headers);
  if (r.statusCode != 200) {
    throw Exception('Tables load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['tables'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

class AreaScreen extends ConsumerStatefulWidget {
  const AreaScreen({super.key});
  @override
  ConsumerState<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends ConsumerState<AreaScreen> {
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
    };
  }

  Future<XFile?> _pick(ImageSource src) => _picker.pickImage(
    source: src,
    imageQuality: 88,
    requestFullMetadata: false,
  );

  Future<void> _create({
    required String name,
    String? description,
    XFile? image,
  }) async {
    final m = http.MultipartRequest('POST', Uri.parse('${AppConfig.apiBase}/areas'))
      ..headers.addAll(_headers())
      ..fields['name'] = name;
    if ((description ?? '').trim().isNotEmpty) {
      m.fields['description'] = description!.trim();
    }
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
    String? description,
    XFile? image,
    bool removeImage = false,
  }) async {
    final m =
    http.MultipartRequest('PUT', Uri.parse('${AppConfig.apiBase}/areas/$id'))
      ..headers.addAll(_headers())
      ..fields['__type'] = 'area_update';
    if (name != null) m.fields['name'] = name;
    if (description != null) m.fields['description'] = description;
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
    await http.delete(Uri.parse('${AppConfig.apiBase}/areas/$id'), headers: _headers());
    if (r.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Delete failed', r.statusCode, r.body));
    }
  }

  Future<void> _openForm({Map<String, dynamic>? area}) async {
    final isEdit = area != null;
    final nameCtrl = TextEditingController(text: area?['name'] ?? '');
    final descCtrl = TextEditingController(text: (area?['description'] ?? '').toString());
    XFile? pickedImage;
    bool removeImage = false;

    final String existingImageUrl = _imgUrl(area?['image'] as String?);
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

        Future<void> save() async {
          if (!key.currentState!.validate()) return;

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
                id: (area!['_id'] ?? '').toString(),
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim(),
                image: pickedImage,
                removeImage: removeImage && pickedImage == null,
              );
            } else {
              await _create(
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim(),
                image: pickedImage,
              );
            }
            if (nav.canPop()) nav.pop();
            if (nav.canPop()) nav.pop();

            ref.refresh(areasProvider);
            messenger.showSnackBar(SnackBar(content: Text(isEdit ? 'Area updated' : 'Area created')));
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
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(isEdit ? 'Edit Area' : 'Add Area',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFFF7043))),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Area Name',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
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
                              return Image.file(File(pickedImage!.path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
                            }
                            if (!removeImage && existingImageUrl.isNotEmpty) {
                              return Image.network(existingImageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
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
                              if (x != null) setState(() => pickedImage = x);
                            },
                            icon: const Icon(Icons.photo),
                            label: const Text('Gallery'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final x = await _pick(ImageSource.camera);
                              if (x != null) setState(() => pickedImage = x);
                            },
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Camera'),
                          ),
                          if (isEdit && (existingImageUrl.isNotEmpty || pickedImage != null))
                            OutlinedButton.icon(
                              onPressed: () => setState(() {
                                pickedImage = null;
                                removeImage = true;
                              }),
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
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _canManage ? save : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7043),
                          foregroundColor: Colors.white,
                        ),
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

  Widget _card(Map<String, dynamic> a) {
    final name = (a['name'] ?? '') as String;
    final desc = (a['description'] ?? '') as String;
    final url = _imgUrl(a['image'] as String?);
    final areaId = (a['_id'] ?? '').toString();

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TablesByAreaScreen(areaId: areaId, areaName: name)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFFFFF3E8), Color(0xFFFFE6D6)]),
          boxShadow: const [BoxShadow(color: Color(0x15000000), blurRadius: 6, offset: Offset(0, 3))],
          border: Border.all(color: const Color(0x1A000000)),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: url.isEmpty
                        ? const ColoredBox(
                        color: Colors.white,
                        child: Center(child: Icon(Icons.image_outlined, color: Colors.black26)))
                        : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                  ),
                ),

                // Visible edit/delete icons (for managers/admins)
                if (_canManage)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Row(
                      children: [
                        // Edit button
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.green, size: 22),
                          tooltip: 'Edit area',
                          onPressed: () => _openForm(area: a),
                        ),
                        // Delete button
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 22),
                          tooltip: 'Delete area',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Delete Area'),
                                content: Text('Delete "$name"?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7043)),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              try {
                                await _delete(areaId);
                                if (mounted) {
                                  ref.refresh(areasProvider);
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('Area deleted')));
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text(e.toString())));
                                }
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                Positioned(
                  left: 6,
                  top: 6,
                  child: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        _openForm(area: a);
                      }
                      if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete Area'),
                            content: Text('Delete "$name"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7043)),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await _delete(areaId);
                            if (mounted) {
                              ref.refresh(areasProvider);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Area deleted')));
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
                      if (_canManage) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (_canManage) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Color(0xFF6A3B13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.brown.shade700),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              child: Consumer(
                builder: (ctx, ref, _) {
                  final tablesAsync = ref.watch(areaTablesProvider(areaId));
                  return tablesAsync.when(
                    loading: () => const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    error: (e, __) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Status unavailable', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ),
                    data: (tables) {
                      int avail = 0, occ = 0, res = 0;
                      for (final t in tables) {
                        switch ((t['status'] ?? 'available').toString().toLowerCase()) {
                          case 'occupied':
                            occ++;
                            break;
                          case 'reserved':
                            res++;
                            break;
                          default:
                            avail++;
                        }
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _statusChip(Colors.green, 'Available', avail),
                            _statusChip(Colors.red, 'Occupied', occ),
                            _statusChip(Colors.amber, 'Reserved', res),
                          ],
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

  Widget _statusChip(Color color, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label: $count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // WillPopScope handler
  Future<bool> _onWillPop() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Areas?'),
        content: const Text('Are you sure you want to go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(areasProvider);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFFDF6EC),
        appBar: AppBar(
          title: const Text('Areas', style: TextStyle(color: Colors.white)),
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
                  hintText: 'Search areas…',
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                ),
              ),
            ),
            Expanded(
              child: areasAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (areas) {
                  final items = areas.where((m) {
                    final n = (m['name'] ?? '').toString().toLowerCase();
                    return _query.isEmpty || n.contains(_query);
                  }).toList();

                  if (items.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async => ref.refresh(areasProvider),
                      child: ListView(
                        children: const [
                          SizedBox(height: 80),
                          Icon(Icons.grid_view_rounded, size: 64, color: Colors.black26),
                          SizedBox(height: 12),
                          Center(
                            child: Text('No areas found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                          SizedBox(height: 4),
                          Center(
                            child: Text('Try search or add a new area.', style: TextStyle(color: Colors.black54)),
                          ),
                          SizedBox(height: 80),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(areasProvider),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.86,
                      ),
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
      ),
    );
  }
}
