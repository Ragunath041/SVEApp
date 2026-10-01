import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supervisorapp/Services/incident/incident_history_service.dart';
import 'package:supervisorapp/widgets/footer.dart';

class IncidentLogsPage extends StatefulWidget {
  final String supervisorId;

  const IncidentLogsPage({super.key, required this.supervisorId});

  @override
  State<IncidentLogsPage> createState() => _IncidentLogsPageState();
}

class _IncidentLogsPageState extends State<IncidentLogsPage> {
  final S3IncidentService _s3Service = S3IncidentService();
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _history = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _s3Service.fetchIncidentHistory(
        widget.supervisorId,
      );
      if (mounted) {
        setState(() {
          _history = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('IncidentLogsPage: Error loading incident history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Incident History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF444CE7)),
            )
          : _history.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final date = _history.keys.elementAt(index);
                final incidents = _history[date]!;
                return _buildDateGroup(date, incidents);
              },
            ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_turned_in_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No Incident Reports Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          const Text('Reported incidents will appear here.'),
        ],
      ),
    );
  }

  Widget _buildDateGroup(String date, List<Map<String, dynamic>> incidents) {
    // Format date nicely
    String formattedDate = date;
    try {
      DateTime dt = DateTime.parse(date);
      formattedDate = DateFormat('EEEE, MMM d, y').format(dt);
    } catch (e) {
      debugPrint('IncidentLogsPage: Error formatting date $date: $e');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF444CE7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formattedDate,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                '${incidents.length} Report${incidents.length > 1 ? 's' : ''}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
        Column(
          children: incidents.map((inc) => _buildIncidentCard(inc)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> incident) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade400,
              size: 22,
            ),
          ),
          title: Text(
            incident['studentName'] ?? 'Unknown Student',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
            'ID: ${incident['studentId'] ?? 'N/A'} • ${incident['courseCode'] ?? 'No Code'}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Course', incident['courseName'] ?? 'N/A'),
                  _buildDetailRow('Offence', incident['offence'] ?? 'N/A'),
                  _buildDetailRow('Sub-Type', incident['ufm'] ?? 'N/A'),
                  if (incident['description'] != null &&
                      incident['description'].isNotEmpty)
                    _buildDetailRow('Description', incident['description']),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTimestamp(incident['timestamp']),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${incident['cityName'] ?? incident['Center'] ?? 'Unknown'} - ${incident['centreName'] ?? incident['centre'] ?? 'Unknown'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? ts) {
    if (ts == null) return 'N/A';
    try {
      DateTime dt = DateTime.parse(ts);
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      debugPrint('IncidentLogsPage: Error formatting timestamp $ts: $e');
      return ts;
    }
  }
}
