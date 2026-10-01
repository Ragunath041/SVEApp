import 'package:flutter/material.dart';
import 'package:supervisorapp/widgets/footer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

enum _AllocationStatus { pending, accepted, rejected }

class _AllocationNotification {
  final String id;
  final String city;
  final String center;
  final String date;
  final String session;
  final String room;
  _AllocationStatus status;
  bool expanded;

  _AllocationNotification({
    required this.id,
    required this.city,
    required this.center,
    required this.date,
    required this.session,
    required this.room,
  }) : status = _AllocationStatus.pending,
       expanded = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AllocationNotificationPage extends StatefulWidget {
  final String supervisorId;
  final String fullName;
  final String centre;

  const AllocationNotificationPage({
    super.key,
    required this.supervisorId,
    required this.fullName,
    required this.centre,
  });

  @override
  State<AllocationNotificationPage> createState() =>
      _AllocationNotificationPageState();
}

class _AllocationNotificationPageState
    extends State<AllocationNotificationPage> {
  // ── Colors ─────────────────────────────────────────────────────────────────
  static const Color _brand = Color.fromARGB(255, 68, 76, 231);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _greenLight = Color(0xFFE8F5E9);
  static const Color _red = Color(0xFFC62828);
  static const Color _redLight = Color(0xFFFFEBEE);

  // ── Sample notifications ───────────────────────────────────────────────────
  final List<_AllocationNotification> _notifications = [
    _AllocationNotification(
      id: 'N001',
      city: 'Coimbatore',
      center: 'PSG College of Technology',
      date: '22-08-2026',
      session: 'FN',
      room: 'Room 101',
    ),
    _AllocationNotification(
      id: 'N002',
      city: 'Coimbatore',
      center: 'KARPAGAM ACADEMY OF HIGHER EDUCATION',
      date: '22-08-2026',
      session: 'AN',
      room: 'Hall B',
    ),
    _AllocationNotification(
      id: 'N003',
      city: 'Coimbatore',
      center: 'CIT Campus',
      date: '22-08-2026',
      session: 'EN',
      room: 'Hall 3',
    ),
    _AllocationNotification(
      id: 'N004',
      city: 'Coimbatore',
      center: 'PSG College of Technology',
      date: '23-08-2026',
      session: 'FN',
      room: 'Room 205',
    ),
    _AllocationNotification(
      id: 'N005',
      city: 'Coimbatore',
      center: 'KARPAGAM ACADEMY OF HIGHER EDUCATION',
      date: '23-08-2026',
      session: 'AN',
      room: 'Hall A',
    ),
    _AllocationNotification(
      id: 'N006',
      city: 'Coimbatore',
      center: 'CIT Campus',
      date: '23-08-2026',
      session: 'EN',
      room: 'Room 302',
    ),
    _AllocationNotification(
      id: 'N007',
      city: 'Coimbatore',
      center: 'SNS College of Engineering',
      date: '24-08-2026',
      session: 'FN',
      room: 'Block C - 201',
    ),
    _AllocationNotification(
      id: 'N008',
      city: 'Coimbatore',
      center: 'SNS College of Engineering',
      date: '24-08-2026',
      session: 'AN',
      room: 'Block C - 202',
    ),
    _AllocationNotification(
      id: 'N009',
      city: 'Coimbatore',
      center: 'PSG College of Technology',
      date: '25-08-2026',
      session: 'FN',
      room: 'Room 110',
    ),
    _AllocationNotification(
      id: 'N010',
      city: 'Coimbatore',
      center: 'CIT Campus',
      date: '25-08-2026',
      session: 'EN',
      room: 'Hall 5',
    ),
    _AllocationNotification(
      id: 'N011',
      city: 'Chennai',
      center: 'Anna University Main Campus',
      date: '22-08-2026',
      session: 'FN',
      room: 'Main Hall - 1',
    ),
    _AllocationNotification(
      id: 'N012',
      city: 'Chennai',
      center: 'Anna University Main Campus',
      date: '22-08-2026',
      session: 'AN',
      room: 'Main Hall - 2',
    ),
    _AllocationNotification(
      id: 'N013',
      city: 'Chennai',
      center: 'Loyola College',
      date: '23-08-2026',
      session: 'FN',
      room: 'Block A - 101',
    ),
    _AllocationNotification(
      id: 'N014',
      city: 'Chennai',
      center: 'Loyola College',
      date: '23-08-2026',
      session: 'EN',
      room: 'Block A - 102',
    ),
    _AllocationNotification(
      id: 'N015',
      city: 'Chennai',
      center: 'SRM Institute of Science',
      date: '24-08-2026',
      session: 'AN',
      room: 'Tech Block - 301',
    ),
    _AllocationNotification(
      id: 'N016',
      city: 'Chennai',
      center: 'SRM Institute of Science',
      date: '24-08-2026',
      session: 'EN',
      room: 'Tech Block - 302',
    ),
    _AllocationNotification(
      id: 'N017',
      city: 'Madurai',
      center: 'Madurai Kamaraj University',
      date: '22-08-2026',
      session: 'FN',
      room: 'Seminar Hall 1',
    ),
    _AllocationNotification(
      id: 'N018',
      city: 'Madurai',
      center: 'Madurai Kamaraj University',
      date: '23-08-2026',
      session: 'AN',
      room: 'Seminar Hall 2',
    ),
    _AllocationNotification(
      id: 'N019',
      city: 'Madurai',
      center: 'Thiagarajar College of Engineering',
      date: '24-08-2026',
      session: 'FN',
      room: 'Room 401',
    ),
    _AllocationNotification(
      id: 'N020',
      city: 'Madurai',
      center: 'Thiagarajar College of Engineering',
      date: '24-08-2026',
      session: 'EN',
      room: 'Room 402',
    ),
    _AllocationNotification(
      id: 'N021',
      city: 'Trichy',
      center: 'NIT Trichy',
      date: '25-08-2026',
      session: 'FN',
      room: 'Lecture Hall 7',
    ),
    _AllocationNotification(
      id: 'N022',
      city: 'Trichy',
      center: 'Bharathidasan University',
      date: '25-08-2026',
      session: 'AN',
      room: 'Block B - 105',
    ),
  ];

  int get _pendingCount =>
      _notifications.where((n) => n.status == _AllocationStatus.pending).length;

  void _accept(_AllocationNotification n) {
    setState(() {
      n.status = n.status == _AllocationStatus.accepted
          ? _AllocationStatus.pending
          : _AllocationStatus.accepted;
    });
  }

  void _reject(_AllocationNotification n) {
    setState(() {
      n.status = n.status == _AllocationStatus.rejected
          ? _AllocationStatus.pending
          : _AllocationStatus.rejected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double s = (mq.size.width / 375.0).clamp(0.80, 1.15);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: _buildAppBar(s),
      body: _notifications.isEmpty
          ? _buildEmpty(s)
          : Column(
              children: [
                // ── Summary banner ──────────────────────────────────────────
                _buildSummaryBanner(s),

                // ── Notification list ───────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16 * s,
                      12 * s,
                      16 * s,
                      16 * s,
                    ),
                    itemCount: _notifications.length,
                    itemBuilder: (_, i) => _buildCard(_notifications[i], s),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(double s) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 52 * s,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.black87,
          size: 20 * s,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6 * s),
            child: Image.asset(
              'assets/images/company_logo.png',
              width: 30 * s,
              height: 30 * s,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 30 * s,
                height: 30 * s,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(30, 68, 76, 231),
                  borderRadius: BorderRadius.circular(6 * s),
                ),
                child: Icon(Icons.school, color: _brand, size: 16 * s),
              ),
            ),
          ),
          SizedBox(width: 8 * s),
          Text(
            'Allocation Notifications',
            style: TextStyle(
              fontSize: 17 * s,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary banner ─────────────────────────────────────────────────────────

  Widget _buildSummaryBanner(double s) {
    final accepted = _notifications
        .where((n) => n.status == _AllocationStatus.accepted)
        .length;
    final rejected = _notifications
        .where((n) => n.status == _AllocationStatus.rejected)
        .length;
    final total = _notifications.length;
    final pending = _pendingCount;
    final hasResponded = accepted > 0 || rejected > 0;

    return Container(
      margin: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 0),
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: status text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusLine('Total', total, Colors.black87, s),
                SizedBox(height: 3 * s),
                _statusLine('Accepted', accepted, _green, s),
                SizedBox(height: 3 * s),
                _statusLine('Rejected', rejected, _red, s),
                SizedBox(height: 3 * s),
                _statusLine('Pending', pending, const Color(0xFFF57F17), s),
              ],
            ),
          ),
          SizedBox(width: 12 * s),
          // Right: Submit button
          SizedBox(
            height: 52 * s,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: hasResponded ? _brand : Colors.grey.shade400,
                foregroundColor: Colors.white,
                elevation: hasResponded ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10 * s),
                ),
                padding: EdgeInsets.symmetric(horizontal: 18 * s),
              ),
              onPressed: hasResponded ? () => _submitResponses(s) : null,
              child: Text(
                'Submit\nRequests',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13 * s,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(String label, int count, Color color, double s) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label : ',
            style: TextStyle(
              fontSize: 12 * s,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
          TextSpan(
            text: '$count',
            style: TextStyle(
              fontSize: 13 * s,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _submitResponses(double s) {
    final accepted = _notifications
        .where((n) => n.status == _AllocationStatus.accepted)
        .length;
    final rejected = _notifications
        .where((n) => n.status == _AllocationStatus.rejected)
        .length;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18 * s),
        ),
        child: Padding(
          padding: EdgeInsets.all(22 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56 * s,
                height: 56 * s,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF7EE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: _green,
                  size: 32 * s,
                ),
              ),
              SizedBox(height: 14 * s),
              Text(
                'Responses Submitted!',
                style: TextStyle(
                  fontSize: 16 * s,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6 * s),
              Text(
                '$accepted accepted  ·  $rejected rejected',
                style: TextStyle(fontSize: 12 * s, color: Colors.grey.shade600),
              ),
              SizedBox(height: 18 * s),
              SizedBox(
                width: double.infinity,
                height: 44 * s,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10 * s),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Notification card ──────────────────────────────────────────────────────

  Widget _buildCard(_AllocationNotification n, double s) {
    final isAccepted = n.status == _AllocationStatus.accepted;
    final isRejected = n.status == _AllocationStatus.rejected;
    final isPending = n.status == _AllocationStatus.pending;

    // Border accent color based on status
    Color accentColor = isPending ? _brand : (isAccepted ? _green : _red);
    Color headerBg = isPending
        ? Colors.white
        : (isAccepted ? _greenLight : _redLight);

    return Padding(
      padding: EdgeInsets.only(bottom: 10 * s),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12 * s),
          border: Border(left: BorderSide(color: accentColor, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header row ─────────────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => n.expanded = !n.expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * s,
                  vertical: 13 * s,
                ),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: n.expanded
                      ? BorderRadius.only(topRight: Radius.circular(12 * s))
                      : BorderRadius.only(
                          topRight: Radius.circular(12 * s),
                          bottomRight: Radius.circular(12 * s),
                        ),
                ),
                child: Row(
                  children: [
                    // Status icon
                    Container(
                      width: 32 * s,
                      height: 32 * s,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPending
                            ? Icons.notifications_outlined
                            : (isAccepted
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.cancel_outlined),
                        color: accentColor,
                        size: 18 * s,
                      ),
                    ),

                    SizedBox(width: 10 * s),

                    // Center name + city
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.center,
                            style: TextStyle(
                              fontSize: 13 * s,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2 * s),
                          Text(
                            '${n.city}  •  ${n.date}',
                            style: TextStyle(
                              fontSize: 10 * s,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(width: 8 * s),

                    // ── Accept / Reject buttons ────────────────────────────
                    _actionBtn(
                      icon: Icons.check_rounded,
                      active: isAccepted,
                      activeColor: _green,
                      activeBg: _greenLight,
                      inactiveColor: Colors.grey.shade400,
                      tooltip: 'Accept',
                      onTap: () => _accept(n),
                      s: s,
                    ),
                    SizedBox(width: 6 * s),
                    _actionBtn(
                      icon: Icons.close_rounded,
                      active: isRejected,
                      activeColor: _red,
                      activeBg: _redLight,
                      inactiveColor: Colors.grey.shade400,
                      tooltip: 'Reject',
                      onTap: () => _reject(n),
                      s: s,
                    ),
                    SizedBox(width: 8 * s),

                    // Expand chevron
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: n.expanded ? 0.5 : 0.0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade400,
                        size: 20 * s,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded detail rows ────────────────────────────────────────
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: n.expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: _buildDetails(n, s, accentColor),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action button (Accept / Reject) ────────────────────────────────────────

  Widget _actionBtn({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required Color activeBg,
    required Color inactiveColor,
    required String tooltip,
    required VoidCallback onTap,
    required double s,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 34 * s,
          height: 34 * s,
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(8 * s),
            border: Border.all(
              color: active ? activeColor : const Color(0xFFDDDDDD),
              width: 1.5,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Icon(
            icon,
            size: 18 * s,
            color: active ? Colors.white : inactiveColor,
          ),
        ),
      ),
    );
  }

  // ── Detail panel ───────────────────────────────────────────────────────────

  Widget _buildDetails(_AllocationNotification n, double s, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(12 * s)),
      ),
      child: Column(
        children: [
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
            child: Column(
              children: [
                _detailRow(
                  Icons.location_city_rounded,
                  'Center',
                  n.center,
                  accentColor,
                  s,
                ),
                _detailRow(
                  Icons.calendar_today_rounded,
                  'Date',
                  n.date,
                  accentColor,
                  s,
                ),
                _detailRow(
                  Icons.wb_sunny_outlined,
                  'Session',
                  n.session,
                  accentColor,
                  s,
                ),
                _detailRow(
                  Icons.meeting_room_outlined,
                  'Room',
                  n.room,
                  accentColor,
                  s,
                  isLast: true,
                ),
              ],
            ),
          ),

          // ── Status indicator ───────────────────────────────────────────
          if (n.status != _AllocationStatus.pending)
            Container(
              width: double.infinity,
              margin: EdgeInsets.fromLTRB(14 * s, 0, 14 * s, 12 * s),
              padding: EdgeInsets.symmetric(vertical: 9 * s),
              decoration: BoxDecoration(
                color: n.status == _AllocationStatus.accepted
                    ? _greenLight
                    : _redLight,
                borderRadius: BorderRadius.circular(8 * s),
                border: Border.all(
                  color: n.status == _AllocationStatus.accepted
                      ? _green.withValues(alpha: 0.4)
                      : _red.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    n.status == _AllocationStatus.accepted
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 16 * s,
                    color: n.status == _AllocationStatus.accepted
                        ? _green
                        : _red,
                  ),
                  SizedBox(width: 6 * s),
                  Text(
                    n.status == _AllocationStatus.accepted
                        ? 'You have accepted this allocation'
                        : 'You have rejected this allocation',
                    style: TextStyle(
                      fontSize: 11 * s,
                      fontWeight: FontWeight.w600,
                      color: n.status == _AllocationStatus.accepted
                          ? _green
                          : _red,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
    Color accentColor,
    double s, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10 * s),
      child: Row(
        children: [
          Container(
            width: 28 * s,
            height: 28 * s,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6 * s),
            ),
            child: Icon(icon, size: 14 * s, color: accentColor),
          ),
          SizedBox(width: 10 * s),
          SizedBox(
            width: 62 * s,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11 * s,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12 * s,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmpty(double s) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 64 * s,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: 14 * s),
          Text(
            'No Allocation Notifications',
            style: TextStyle(
              fontSize: 16 * s,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
            ),
          ),
          SizedBox(height: 6 * s),
          Text(
            'You have no pending allocations at the moment.',
            style: TextStyle(fontSize: 12 * s, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
