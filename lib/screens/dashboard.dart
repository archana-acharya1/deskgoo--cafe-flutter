import 'package:deskgoo_cafe_v2/providers/socket_provider.dart';
import 'package:deskgoo_cafe_v2/screens/daily_stock_screen.dart';
import 'package:deskgoo_cafe_v2/screens/home_page.dart';
import 'package:deskgoo_cafe_v2/screens/report_screen.dart';
import 'package:deskgoo_cafe_v2/screens/table_screen.dart';
import 'package:deskgoo_cafe_v2/screens/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'area_screen.dart';
import 'category_screen.dart';
import 'item_screen.dart';
import 'login_page.dart';
import '../state/auth.dart';
import 'order_screen.dart';
import 'orders_list_screen.dart';
import 'stock_screen.dart';
import 'restaurant_settings_screen.dart';
import 'ingredient_screen.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  String selectedMenu = 'Home';

  bool get _canSeeUsers {
    final authState = ref.watch(authStateProvider);
    final role = authState?.roleName ?? '';
    return role == 'admin' || role == 'manager';
  }

  bool get _canSeeSettings {
    final authState = ref.watch(authStateProvider);
    final role = authState?.roleName ?? '';
    return role == 'admin' || role == 'manager';
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B4513)),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF7043)),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      final socketService = ref.read(socketProvider);
      socketService.disconnect();
      ref.read(authStateProvider.notifier).state = null;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  Future<bool> _onWillPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text('Do you really want to close Deskgoo Cafe?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF7043)),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  Widget getMainContent() {
    final authState = ref.watch(authStateProvider);
    final role = authState?.roleName ?? '';

    if (selectedMenu == 'Users' && !_canSeeUsers) {
      return const Center(
        child: Text(
          "You don't have permission to view User Management",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (selectedMenu == 'Settings' && !_canSeeSettings) {
      return const Center(
        child: Text(
          "You don't have permission to access Settings",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
    }

    switch (selectedMenu) {
      case 'Areas':
        return const AreaScreen();
      case 'Items':
        return const ItemScreen();
      case 'Tables':
        return const TableScreen();
      case 'New Order':
        return OrderScreen();
      case 'Orders':
        return const OrdersListScreen();
      case 'Home':
        return const HomePage();
      case 'Users':
        return const UsersPage();
      case 'Stock':
        return const StockScreen();
      case 'Categories':
        return const CategoryScreen();
      case 'Reports':
        return const ReportsScreen();
      case 'Ingredients':
        return const IngredientScreen();
        case 'Daily-Stock':
        return const DailyStockScreen();

      case 'Settings':
        return RestaurantSettingsScreen(
          token: authState!.token,
          restaurantId: authState.restaurantId,
          role: role,
        );
      default:
        return const Center(child: Text('Welcome to Deskgoo Cafe!'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xFFFF7043);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "Deskgoo Cafe - $selectedMenu",
            style: const TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          backgroundColor: themeColor,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmLogout(context),
            ),
          ],
        ),
        drawer: SizedBox(
          width: 180,
          child: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const DrawerHeader(
                  decoration: BoxDecoration(color: Color(0xFFFF7043)),
                  child: Text(
                    'Menu',
                    style: TextStyle(color: Colors.white, fontSize: 23),
                  ),
                ),
                drawerItem('Home', Icons.home),
                drawerItem('Categories', Icons.category),
                drawerItem('Items', Icons.fastfood),
                drawerItem('Areas', Icons.location_city),
                drawerItem('Tables', Icons.table_bar),
                drawerItem('New Order', Icons.add_shopping_cart),
                drawerItem('Orders', Icons.receipt),
                drawerItem('Stock', Icons.inventory),
                drawerItem('Ingredients', Icons.kitchen),
                drawerItem('Daily-Stock', Icons.food_bank_sharp),
                drawerItem('Reports', Icons.bar_chart),
                if (_canSeeUsers)
                  drawerItem('Users', Icons.supervised_user_circle),
                if (_canSeeSettings)
                  drawerItem('Settings', Icons.settings),

              ],
            ),
          ),
        ),
        body: getMainContent(),
      ),
    );
  }

  Widget drawerItem(String title, IconData icon) {
    final isSelected = selectedMenu == title;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFFF57C00) : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? const Color(0xFFF57C00) : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        setState(() {
          selectedMenu = title;
        });
        Navigator.pop(context);
      },
    );
  }
}
