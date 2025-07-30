import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import 'views/all_instructors_view.dart';
import 'views/students_view.dart';
import 'views/categories_view.dart';
import 'views/events_view.dart'; // Add this import

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;

  Future<void> _confirmLogout(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await authService.logout(context);
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard'),
        backgroundColor: Color(0xFFDB2777),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),

      body: Row(
        children: [
          if (isWideScreen)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() => _selectedIndex = index);
              },
              labelType: NavigationRailLabelType.selected,
              backgroundColor: Color(0xFFFDF2F8),
              selectedLabelTextStyle: TextStyle(
                color: Color(0xFFDB2777),
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: Colors.grey[600],
              ),
              selectedIconTheme: IconThemeData(
                color: Color(0xFFDB2777),
              ),
              unselectedIconTheme: IconThemeData(
                color: Colors.grey[600],
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.school),
                  selectedIcon: Icon(Icons.school),
                  label: Text('All\nInstructors'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people),
                  selectedIcon: Icon(Icons.people),
                  label: Text('Students'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.category),
                  selectedIcon: Icon(Icons.category),
                  label: Text('Categories'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.event),
                  selectedIcon: Icon(Icons.event),
                  label: Text('Events'),
                ),
              ],
            ),
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: _buildSelectedView(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWideScreen
          ? null
          : BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Color(0xFFDB2777),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'Instructors',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Students',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.category),
            label: 'Categories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Events',
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedView() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 200),
      child: _getView(_selectedIndex),
    );
  }

  Widget _getView(int index) {
    switch (index) {
      case 0:
        return AllInstructorsView(key: ValueKey('instructors'));
      case 1:
        return StudentsView(key: ValueKey('students'));
      case 2:
        return CategoriesView(key: ValueKey('categories'));
      case 3:
        return EventsView(key: ValueKey('events'));
      default:
        return Center(child: Text('Select a view'));
    }
  }
}