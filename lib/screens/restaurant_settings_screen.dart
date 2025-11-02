import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../config.dart';

class RestaurantSettingsScreen extends StatefulWidget {
  final String token;
  final String restaurantId;
  final String role;

  const RestaurantSettingsScreen({
    super.key,
    required this.token,
    required this.restaurantId,
    required this.role,
  });

  @override
  State<RestaurantSettingsScreen> createState() =>
      _RestaurantSettingsScreenState();
}

class _RestaurantSettingsScreenState extends State<RestaurantSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final restaurantNameController = TextEditingController();
  final idNumberController = TextEditingController(); // for VAT or PAN
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();

  String? _selectedIdType; // 'VAT' or 'PAN'
  Map<String, dynamic> _fetchedSettings = {};
  File? _selectedLogo;
  String? _logoUrl;
  bool _loading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();

    // Restrict staff role
    if (widget.role == 'staff') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access denied for staff')),
        );
        Navigator.pop(context);
      });
      return;
    }

    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    setState(() => _loading = true);

    try {
      final dio = Dio();

      final response = await dio.get(
        "${AppConfig.apiBase}/restaurant-settings",
        options: Options(
          headers: {
            'Authorization': 'Bearer ${widget.token}',
          },
        ),
      );

      if (response.statusCode == 200) {
        final settingsData = response.data['settings'];
        if (settingsData != null) {
          setState(() {
            _fetchedSettings = Map<String, dynamic>.from(settingsData);

            restaurantNameController.text =
                settingsData['restaurantName'] ?? '';
            emailController.text = settingsData['email'] ?? '';
            phoneController.text = settingsData['phone'] ?? '';
            addressController.text = settingsData['address'] ?? '';
            _logoUrl = settingsData['logoUrl'];

            // Set VAT or PAN
            if (settingsData['vatNo'] != null &&
                settingsData['vatNo'].toString().isNotEmpty) {
              _selectedIdType = 'VAT';
              idNumberController.text = settingsData['vatNo'];
            } else if (settingsData['panNo'] != null &&
                settingsData['panNo'].toString().isNotEmpty) {
              _selectedIdType = 'PAN';
              idNumberController.text = settingsData['panNo'];
            }
          });
        }
      } else {
        debugPrint(
            "Fetch settings failed: ${response.statusCode} ${response.data}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to fetch settings: ${response.statusCode}')),
        );
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching settings: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickLogo() async {
    if (!_isEditing) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _selectedLogo = File(pickedFile.path));
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final dio = Dio();
      final formData = FormData();

      formData.fields.add(MapEntry('restaurantName', restaurantNameController.text));
      formData.fields.add(MapEntry('email', emailController.text));
      formData.fields.add(MapEntry('phone', phoneController.text));
      formData.fields.add(MapEntry('address', addressController.text));

      // Add VAT or PAN field depending on selection
      if (_selectedIdType == 'VAT') {
        formData.fields.add(MapEntry('vatNo', idNumberController.text));
      } else if (_selectedIdType == 'PAN') {
        formData.fields.add(MapEntry('panNo', idNumberController.text));
      }

      if (_selectedLogo != null) {
        formData.files.add(
          MapEntry(
            'logo',
            await MultipartFile.fromFile(_selectedLogo!.path,
                filename: _selectedLogo!.path.split('/').last),
          ),
        );
      }

      final response = await dio.put(
        "${AppConfig.apiBase}/restaurant-settings",
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings updated successfully!')),
        );
        setState(() => _isEditing = false);
        _fetchSettings();
      } else {
        debugPrint("Save failed: ${response.statusCode} ${response.data}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${response.statusCode}')),
        );
      }
    } catch (e) {
      debugPrint("Save error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }

    setState(() => _loading = false);
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      restaurantNameController.text = _fetchedSettings['restaurantName'] ?? '';
      emailController.text = _fetchedSettings['email'] ?? '';
      phoneController.text = _fetchedSettings['phone'] ?? '';
      addressController.text = _fetchedSettings['address'] ?? '';

      if (_fetchedSettings['vatNo'] != null &&
          _fetchedSettings['vatNo'].toString().isNotEmpty) {
        _selectedIdType = 'VAT';
        idNumberController.text = _fetchedSettings['vatNo'];
      } else if (_fetchedSettings['panNo'] != null &&
          _fetchedSettings['panNo'].toString().isNotEmpty) {
        _selectedIdType = 'PAN';
        idNumberController.text = _fetchedSettings['panNo'];
      } else {
        _selectedIdType = null;
        idNumberController.clear();
      }

      _selectedLogo = null;
    });
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.brown.shade700),
      filled: true,
      fillColor: _isEditing ? Colors.orange.shade50 : Colors.orange.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.orange.shade700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Restaurant Settings"),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickLogo,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _selectedLogo != null
                      ? FileImage(_selectedLogo!)
                      : (_logoUrl != null
                      ? NetworkImage("${AppConfig.hostBase}/${_logoUrl!}")
                  as ImageProvider
                      : null),
                  child: _selectedLogo == null && _logoUrl == null
                      ? const Icon(Icons.camera_alt,
                      size: 40, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(height: 20),

              // Restaurant Name
              TextFormField(
                controller: restaurantNameController,
                enabled: _isEditing,
                style: const TextStyle(color: Colors.black),
                decoration: _fieldDecoration("Restaurant Name"),
                validator: (v) =>
                v == null || v.isEmpty ? "Enter restaurant name" : null,
              ),
              const SizedBox(height: 12),

              // Dropdown for VAT or PAN
              DropdownButtonFormField<String>(
                value: _selectedIdType,
                decoration: _fieldDecoration("ID Type (VAT or PAN)"),
                items: const [
                  DropdownMenuItem(value: 'VAT', child: Text('VAT Number')),
                  DropdownMenuItem(value: 'PAN', child: Text('PAN Number')),
                ],
                onChanged: _isEditing
                    ? (value) => setState(() {
                  _selectedIdType = value;
                  idNumberController.clear();
                })
                    : null,
                validator: (v) =>
                v == null ? 'Please select VAT or PAN' : null,
              ),
              const SizedBox(height: 12),

              // ID Number
              TextFormField(
                controller: idNumberController,
                enabled: _isEditing,
                style: const TextStyle(color: Colors.black),
                decoration: _fieldDecoration(
                    _selectedIdType == 'VAT' ? "VAT Number" : "PAN Number"),
                validator: (v) =>
                v == null || v.isEmpty ? "Enter ${_selectedIdType ?? 'ID'} number" : null,
              ),
              const SizedBox(height: 12),

              // Other fields
              TextFormField(
                controller: emailController,
                enabled: _isEditing,
                style: const TextStyle(color: Colors.black),
                decoration: _fieldDecoration("Email"),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: phoneController,
                enabled: _isEditing,
                style: const TextStyle(color: Colors.black),
                decoration: _fieldDecoration("Phone"),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: addressController,
                enabled: _isEditing,
                style: const TextStyle(color: Colors.black),
                decoration: _fieldDecoration("Address"),
              ),
              const SizedBox(height: 24),

              if (_isEditing)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save),
                        label: const Text("Save"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.brown.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cancelEditing,
                        icon: const Icon(Icons.cancel),
                        label: const Text("Cancel"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
