import 'package:flutter/material.dart';
import 'package:front/services/event_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:front/constants/colors.dart';
import 'package:front/services/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

class AttendanceView extends StatefulWidget {
  final int eventId;
  final String eventTitle;
  final bool isOnline;

  const AttendanceView({
    Key? key,
    required this.eventId,
    required this.eventTitle,
    required this.isOnline,
  }) : super(key: key);

  @override
  _AttendanceViewState createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> with SingleTickerProviderStateMixin {
  final EventService _eventService = EventService(baseUrl: 'http://192.168.1.13:8080');
  Future<List<AttendanceDTO>>? _attendanceFuture;
  List<AttendanceDTO> _allAttendance = []; // Cache the full attendance list
  List<AttendanceDTO> _filteredAttendance = [];
  bool _isExporting = false;
  String _searchQuery = '';
  String _filterStatus = 'All';
  late TabController _tabController;
  bool _isSearchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'username'; // Default sort by username
  bool _sortAscending = true; // Default sort direction

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _initializeAttendance();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      setState(() {
        switch (_tabController.index) {
          case 0:
            _filterStatus = 'All';
            break;
          case 1:
            _filterStatus = 'Checked In';
            break;
          case 2:
            _filterStatus = 'Not Checked In';
            break;
        }
        _applyFilters();
      });
    }
  }

  Future<void> _initializeAttendance() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = await authService.getToken();
    if (token != null) {
      _eventService.setToken(token);
      setState(() {
        _attendanceFuture = _eventService.getAttendance(widget.eventId).then((attendance) {
          _allAttendance = attendance; // Cache the data
          _filteredAttendance = List.from(attendance); // Initialize filtered list
          _applyFilters();
          return attendance;
        });
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/login');
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredAttendance = _allAttendance.where((record) {
        // Apply search filter
        final matchesSearch = _searchQuery.isEmpty ||
            record.username.toLowerCase().contains(_searchQuery.toLowerCase());

        // Apply status filter
        bool matchesStatus = true;
        if (_filterStatus == 'Checked In') {
          matchesStatus = record.checkedIn;
        } else if (_filterStatus == 'Not Checked In') {
          matchesStatus = !record.checkedIn;
        }

        return matchesSearch && matchesStatus;
      }).toList();

      // Apply sorting
      _filteredAttendance.sort((a, b) {
        int comparison;
        if (_sortBy == 'username') {
          comparison = a.username.toLowerCase().compareTo(b.username.toLowerCase());
        } else {
          // Sort by check-in time (nulls last)
          final timeA = a.checkedIn && a.checkInTime != null ? a.checkInTime! : DateTime(9999);
          final timeB = b.checkedIn && b.checkInTime != null ? b.checkInTime! : DateTime(9999);
          comparison = timeA.compareTo(timeB);
        }
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  Future<void> _exportAttendance(BuildContext context) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final csvData = await _eventService.exportAttendance(widget.eventId);
      final directory = await getTemporaryDirectory();
      final safeEventTitle = widget.eventTitle.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final path = '${directory.path}/${safeEventTitle}_attendance.csv';
      final file = File(path);
      await file.writeAsString(csvData);

      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv')],
        text: 'Attendance for ${widget.eventTitle}',
      );

      _showSnackBar('Attendance exported successfully');
    } catch (e) {
      _showSnackBar('Error exporting attendance: $e');
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.all(10),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
      if (!_isSearchVisible) {
        _searchController.clear();
        _searchQuery = '';
        _applyFilters();
      }
    });
  }

  void _toggleSort() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.sort_by_alpha),
                title: Text('Username'),
                onTap: () {
                  setState(() {
                    _sortBy = 'username';
                    _sortAscending = true;
                    _applyFilters();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.access_time),
                title: Text('Check-In Time'),
                onTap: () {
                  setState(() {
                    _sortBy = 'checkInTime';
                    _sortAscending = true;
                    _applyFilters();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                title: Text('Toggle Direction'),
                onTap: () {
                  setState(() {
                    _sortAscending = !_sortAscending;
                    _applyFilters();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: AppBar(
        title: _isSearchVisible
            ? TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search attendees...',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          style: TextStyle(color: Colors.white),
          autofocus: true,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              _applyFilters();
            });
          },
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance',
              style: TextStyle(
                color: Colors.white, 
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),

            SizedBox(height: 4),
            Text(
              widget.eventTitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_isSearchVisible ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
            tooltip: _isSearchVisible ? 'Close search' : 'Search attendees',
          ),
          IconButton(
            icon: Icon(Icons.sort),
            onPressed: _toggleSort,
            tooltip: 'Sort attendees',
          ),
          if (!widget.isOnline)
            _isExporting
                ? Container(
              width: 48,
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
            )
                : IconButton(
              icon: Icon(Icons.file_download),
              onPressed: () => _exportAttendance(context),
              tooltip: 'Export attendance',
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 3,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textGray,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              isScrollable: true, // Make tabs scrollable
              tabs: [
                Tab(text: 'All'),
                Tab(text: 'Checked In'),
                Tab(text: 'Not Checked In'),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _initializeAttendance,
        color: AppColors.primary,
        child: _buildAttendanceList(),
      ),
    );
  }

  Widget _buildAttendanceList() {
    if (_attendanceFuture == null) {
      return _buildLoadingState();
    }

    return FutureBuilder<List<AttendanceDTO>>(
      future: _attendanceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        } else if (snapshot.hasError) {
          String errorMessage = 'Failed to load attendance records';
          if (snapshot.error.toString().contains('Unauthorized')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Provider.of<AuthService>(context, listen: false).logout(context);
              Navigator.of(context).pushReplacementNamed('/login');
            });
            return _buildMessageState('Redirecting to login...');
          } else if (snapshot.error.toString().contains('404')) {
            errorMessage = 'Event not found';
          } else if (snapshot.error.toString().contains('Network')) {
            errorMessage = 'Network error. Please check your connection.';
          }
          return _buildErrorState(errorMessage);
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState();
        }

        if (_filteredAttendance.isEmpty) {
          return _buildNoResultsState();
        }

        return _buildAttendanceListView();
      },
    );
  }

  Widget _buildAttendanceListView() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: _filteredAttendance.length,
      itemBuilder: (context, index) {
        final record = _filteredAttendance[index];
        return _buildAttendanceCard(record, index);
      },
    );
  }

  Widget _buildAttendanceCard(AttendanceDTO record, int index) {
    String checkInDisplay = '';
    if (record.checkedIn && record.checkInTime != null) {
      final now = DateTime.now();
      final difference = now.difference(record.checkInTime!);
      if (difference.inDays < 1) {
        checkInDisplay = 'Checked in ${timeago.format(record.checkInTime!)}';
      } else {
        checkInDisplay = DateFormat('MMM dd, yyyy • HH:mm').format(record.checkInTime!);
      }
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: record.checkedIn ? Colors.green.shade200 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar or Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: record.checkedIn
                    ? Colors.green.shade100
                    : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  record.checkedIn ? Icons.check_circle : Icons.person,
                  color: record.checkedIn
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                  size: 28,
                ),
              ),
            ),
            SizedBox(width: 16),
            // Attendee Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.username.isEmpty ? 'Unknown User' : record.username,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: record.checkedIn
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: record.checkedIn
                                ? Colors.green.shade300
                                : Colors.grey.shade400,
                          ),
                        ),
                        child: Text(
                          record.checkedIn ? 'Checked In' : 'Not Checked In',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: record.checkedIn
                                ? Colors.green.shade700
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (record.checkedIn && record.checkInTime != null) ...[
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: AppColors.textGray,
                        ),
                        SizedBox(width: 4),
                        Text(
                          checkInDisplay,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 16),
          Text(
            'Loading attendance records...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.red.shade400,
            ),
            SizedBox(height: 16),
            Text(
              'Error Loading Attendance',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textGray,
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeAttendance,
              icon: Icon(Icons.refresh),
              label: Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 24),
            Text(
              'No Attendance Records',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'There are no attendance records for this event yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textGray,
              ),
            ),
            SizedBox(height: 24),
            if (!widget.isOnline)
              ElevatedButton.icon(
                onPressed: () => _exportAttendance(context),
                icon: Icon(Icons.file_download),
                label: Text('Export Empty Template'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 60,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 16),
            Text(
              'No Matching Records',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textGray,
              ),
            ),
            SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _isSearchVisible = false;
                  _tabController.animateTo(0);
                  _filterStatus = 'All';
                  _sortBy = 'username';
                  _sortAscending = true;
                  _applyFilters();
                });
              },
              icon: Icon(Icons.clear),
              label: Text('Clear Filters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }
}