import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/auth.dart';
import '../config.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  List<dynamic> categories = [];
  List<dynamic> filteredCategories = [];
  bool isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  static const themeColor = Color(0xFFFF7043);

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _searchController.addListener(_filterCategories);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    setState(() => isLoading = true);
    final auth = ref.read(authStateProvider);
    if (auth == null) return;

    try {
      final res = await http.get(
        Uri.parse("${AppConfig.apiBase}/categories"),
        headers: {
          'Authorization': 'Bearer ${auth.token}',
          'Content-Type': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          categories = data['categories'] ?? [];
          filteredCategories = categories;
        });
      } else {
        _showSnack('Failed to fetch categories (${res.statusCode})');
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _filterCategories() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredCategories = categories.where((c) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        final desc = (c['description'] ?? '').toString().toLowerCase();
        return name.contains(query) || desc.contains(query);
      }).toList();
    });
  }

  Future<void> _addOrEditCategory({Map<String, dynamic>? category}) async {
    final nameController = TextEditingController(text: category?['name'] ?? '');
    final descController =
    TextEditingController(text: category?['description'] ?? '');
    final isEdit = category != null;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          isEdit ? 'Edit Category' : 'Add Category',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: themeColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                _showSnack('Category name cannot be empty');
                return;
              }

              final auth = ref.read(authStateProvider);
              if (auth == null) return;

              final url = "${AppConfig.apiBase}/categories";
              final body = json.encode({
                "name": name,
                "description": descController.text.trim(),
              });

              try {
                http.Response res;
                if (isEdit) {
                  res = await http.put(
                    Uri.parse("$url/${category!['_id']}"),
                    headers: {
                      'Authorization': 'Bearer ${auth.token}',
                      'Content-Type': 'application/json',
                    },
                    body: body,
                  );
                } else {
                  res = await http.post(
                    Uri.parse(url),
                    headers: {
                      'Authorization': 'Bearer ${auth.token}',
                      'Content-Type': 'application/json',
                    },
                    body: body,
                  );
                }

                if (res.statusCode == 200 || res.statusCode == 201) {
                  _showSnack(isEdit ? 'Category updated' : 'Category added');
                  _fetchCategories();
                  Navigator.pop(ctx);
                } else {
                  final err = json.decode(res.body);
                  _showSnack(err['error'] ?? 'Failed to save category');
                }
              } catch (e) {
                _showSnack('Error: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          'Delete Category',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: themeColor,
          ),
        ),
        content: const Text(
            'Are you sure you want to delete this category? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final auth = ref.read(authStateProvider);
    if (auth == null) return;

    try {
      final res = await http.delete(
        Uri.parse("${AppConfig.apiBase}/categories/$id"),
        headers: {'Authorization': 'Bearer ${auth.token}'},
      );

      if (res.statusCode == 200) {
        _showSnack('Category deleted');
        _fetchCategories();
      } else {
        _showSnack('Failed to delete category');
      }
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: themeColor,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Categories",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: themeColor,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: themeColor,
        onPressed: () => _addOrEditCategory(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(color: themeColor),
      )
          : RefreshIndicator(
        color: themeColor,
        onRefresh: _fetchCategories,
        child: Column(
          children: [
            // 🔍 Search bar
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search categories...',
                  prefixIcon:
                  const Icon(Icons.search, color: themeColor),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: themeColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: themeColor),
                  ),
                ),
              ),
            ),

            // 🧾 List of categories
            Expanded(
              child: filteredCategories.isEmpty
                  ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.category_outlined,
                        size: 70, color: Colors.grey),
                    SizedBox(height: 10),
                    Text(
                      'No categories found',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Try a different search or add one',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: filteredCategories.length,
                itemBuilder: (ctx, i) {
                  final c = filteredCategories[i];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    child: ListTile(
                      leading: const Icon(Icons.category,
                          color: themeColor, size: 28),
                      title: Text(
                        c['name'] ?? 'Unnamed',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        c['description'] ?? '',
                        style:
                        const TextStyle(color: Colors.grey),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _addOrEditCategory(category: c);
                          } else if (value == 'delete') {
                            _deleteCategory(c['_id']);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
