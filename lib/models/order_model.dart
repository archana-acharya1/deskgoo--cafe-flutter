import 'package:flutter/foundation.dart';

@immutable
class OrderItemModel {
  final String id;
  final String name;
  final String unitName;
  final double price;
  final int quantity;

  const OrderItemModel({
    required this.id,
    required this.name,
    required this.unitName,
    required this.price,
    required this.quantity,
  });

  double get lineTotal => price * quantity;
  double get total => lineTotal; // needed for invoice

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      unitName: json['unitName']?.toString() ?? json['unit']?.toString() ?? '',
      price: (json['price'] ?? 0).toDouble(),
      quantity: (json['quantity'] ?? 1).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unitName': unitName,
    'price': price,
    'quantity': quantity,
  };
}

@immutable
class OrderModel {
  final String id; // unique order id
  final String tableName;
  final String area;
  final List<OrderItemModel> items;
  final String paymentStatus;
  final double paidAmount;
  final String? customerName;
  final String? note;
  final DateTime createdAt;
  final double vatPercent;
  final double vatAmount;
  final double discountPercent;
  final double discountAmount;
  final double finalAmount;
  final String restaurantName;

  const OrderModel({
    required this.id,
    required this.tableName,
    required this.area,
    required this.items,
    required this.paymentStatus,
    required this.paidAmount,
    this.customerName,
    this.note,
    required this.createdAt,
    this.vatPercent = 0.0,
    this.vatAmount = 0.0,
    this.discountPercent = 0.0,
    this.discountAmount = 0.0,
    this.finalAmount = 0.0,
    required this.restaurantName,
  });

  double get totalAmount => items.fold(0.0, (sum, it) => sum + it.lineTotal);

  double get due => (computedFinalAmount - paidAmount).clamp(0, double.infinity);

  double get computedFinalAmount {
    final discount = discountAmount != 0
        ? discountAmount
        : (discountPercent > 0 ? totalAmount * discountPercent / 100 : 0);
    final subtotalAfterDiscount = totalAmount - discount;
    final vat = vatAmount != 0
        ? vatAmount
        : (vatPercent > 0 ? subtotalAfterDiscount * vatPercent / 100 : 0);
    return subtotalAfterDiscount + vat;
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List? ?? [];
    final itemsList = itemsRaw
        .whereType<Map<String, dynamic>>()
        .map((e) => OrderItemModel.fromJson(e))
        .toList();

    return OrderModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      tableName: json['tableName']?.toString() ?? '',
      area: json['areaName']?.toString() ?? json['area']?.toString() ?? '',
      items: itemsList,
      paymentStatus: json['paymentStatus']?.toString() ?? 'Paid',
      paidAmount: (json['paidAmount'] ?? 0).toDouble(),
      customerName: json['customerName']?.toString(),
      note: json['note']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      vatPercent: (json['vatPercent'] ?? 0).toDouble(),
      vatAmount: (json['vatAmount'] ?? 0).toDouble(),
      discountPercent: (json['discountPercent'] ?? 0).toDouble(),
      discountAmount: (json['discountAmount'] ?? 0).toDouble(),
      finalAmount: (json['finalAmount'] ?? 0).toDouble(),
      restaurantName: json['restaurantName']?.toString() ?? 'Deskgoo Cafe',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tableName': tableName,
    'area': area,
    'items': items.map((i) => i.toJson()).toList(),
    'paymentStatus': paymentStatus,
    'paidAmount': paidAmount,
    'customerName': customerName,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'vatPercent': vatPercent,
    'vatAmount': vatAmount,
    'discountPercent': discountPercent,
    'discountAmount': discountAmount,
    'finalAmount': finalAmount,
    'restaurantName': restaurantName,
  };
}
