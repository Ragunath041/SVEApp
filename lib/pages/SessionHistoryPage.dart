import 'dart:async';
import 'package:flutter/material.dart';
import '../Services/ExcelService.dart';
import 'package:supervisorapp/widgets/footer.dart';

class SessionHistoryPage extends StatefulWidget {
  final String initialSessionName;
  final List<Map<String, dynamic>> initialHistoryData;
  final String centre;

  const SessionHistoryPage({
    super.key,
    required this.initialSessionName,
    required this.initialHistoryData,
    required this.centre,
  });

  @override
  State<SessionHistoryPage> createState() => _SessionHistoryPageState();
}

class _SessionHistoryPageState extends State<SessionHistoryPage> {
  late String sessionName;
  late List<Map<String, dynamic>> historyData;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    sessionName = widget.initialSessionName;
    historyData = widget.initialHistoryData;
    // Start auto-refresh every 30 seconds
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);
    try {
      final result = await ExcelService.fetchCurrentSessionHistory(
        widget.centre,
      );
      if (mounted && result['success'] == true) {
        setState(() {
          sessionName = result['session'] ?? widget.initialSessionName;
          historyData = List<Map<String, dynamic>>.from(result['data']);
        });
      }
    } catch (e) {
      debugPrint('Auto-refresh error: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> groupedData = {};
    for (var item in historyData) {
      final sid = item['studentId'] ?? 'UNKNOWN';
      if (!groupedData.containsKey(sid)) {
        groupedData[sid] = [];
      }
      groupedData[sid]!.add(item);
    }

    final studentIds = groupedData.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$sessionName Session History',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF181D27),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF181D27)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: historyData.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.history_edu,
                          size: 64,
                          color: Color(0xFFD0D5DD),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No answer sheets uploaded yet',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            color: Color(0xFF535862),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: studentIds.length,
                itemBuilder: (context, index) {
                  final sid = studentIds[index];
                  final uploads = groupedData[sid]!;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: const Color.fromARGB(255, 255, 255, 255),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(10, 13, 18, 0.05),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          sid,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF181D27),
                          ),
                        ),
                        subtitle: Text(
                          '${uploads.length} Answer Sheets',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: Color(0xFF717680),
                          ),
                        ),
                        iconColor: const Color(0xFF717680),
                        children: [
                          const Divider(height: 1, color: Color(0xFFE9EAEB)),
                          ...uploads.map((u) => _buildDetailCard(u)),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  Widget _buildDetailCard(Map<String, dynamic> upload) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFEAECF0), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${upload['courseCode']}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF444CE7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${upload['pageCount']} Pages',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF444CE7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            upload['fileName'] ?? 'No Filename',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF344054),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Uploaded at ${upload['uploadTime']}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFF717680),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF087443),
                size: 14,
              ),
              const SizedBox(width: 4),
              const Text(
                'Uploaded Successfully',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF087443),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
