import 'package:flutter/material.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/Services/duty/duty_allocation_service.dart';
import 'package:supervisorapp/models/supervisor_requirement_slot.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ExpressInterestPage extends StatefulWidget {
  final String supervisorId;
  final String fullName;
  final String centre;

  const ExpressInterestPage({
    super.key,
    required this.supervisorId,
    required this.fullName,
    required this.centre,
  });

  @override
  State<ExpressInterestPage> createState() => _ExpressInterestPageState();
}

class _ExpressInterestPageState extends State<ExpressInterestPage> {
  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color _brand = Color.fromARGB(255, 68, 76, 231);
  static const Color _brandLight = Color.fromARGB(30, 68, 76, 231);
  static const Color _brandBorder = Color.fromARGB(80, 68, 76, 231);

  // ── Service & Dataset ──────────────────────────────────────────────────────
  final SupervisorRequirementService _requirementService =
      SupervisorRequirementService();
  List<SupervisorRequirementSlot> _allRecords = [];
  bool _isLoading = true;
  String? _errorMessage;

  // ── Filter options (dynamically derived from backend data) ─────────────────
  List<String> get _allCities {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _allRecords) {
      if (seen.add(r.city)) out.add(r.city);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<String> get _allDates {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _allRecords) {
      if (seen.add(r.date)) out.add(r.date);
    }
    return out;
  }

  List<String> get _allSessions {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _allRecords) {
      if (seen.add(r.session)) out.add(r.session);
    }
    const priority = {'FN': 1, 'AN': 2, 'EN': 3};
    out.sort((a, b) => (priority[a] ?? 99).compareTo(priority[b] ?? 99));
    return out;
  }

  // ── Applied filters ────────────────────────────────────────────────────────
  Set<String> _appliedCities = {};
  Set<String> _appliedDates = {};
  Set<String> _appliedSessions = {};

  // ── Temp dropdown selections ───────────────────────────────────────────────
  Set<String> _tempCities = {};
  Set<String> _tempDates = {};
  Set<String> _tempSessions = {};

  // ── Open filter dropdown ───────────────────────────────────────────────────
  String? _openDropdown;

  // ── City accordion expanded state ──────────────────────────────────────────
  final Map<String, bool> _cityExpanded = {};

  // ── Layer links ────────────────────────────────────────────────────────────
  final LayerLink _cityLink = LayerLink();
  final LayerLink _dateLink = LayerLink();
  final LayerLink _sessionLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadRequirements();
  }

  Future<void> _loadRequirements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _requirementService.fetchRequirements(
      supervisorId: widget.supervisorId,
    );

    if (!mounted) return;

    if (result['success'] == true && result['slots'] != null) {
      final List<SupervisorRequirementSlot> fetched =
          result['slots'] as List<SupervisorRequirementSlot>;
      setState(() {
        _allRecords = fetched;
        _isLoading = false;
        for (final c in _allCities) {
          _cityExpanded.putIfAbsent(c, () => true);
        }
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            result['error']?.toString() ?? 'Failed to load requirements.';
      });
    }
  }

  // ── Computed filtered list ─────────────────────────────────────────────────
  List<SupervisorRequirementSlot> get _filtered => _allRecords.where((r) {
    final cityOk = _appliedCities.isEmpty || _appliedCities.contains(r.city);
    final dateOk = _appliedDates.isEmpty || _appliedDates.contains(r.date);
    final sessionOk =
        _appliedSessions.isEmpty || _appliedSessions.contains(r.session);
    return cityOk && dateOk && sessionOk;
  }).toList();

  List<String> get _filteredCities {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _filtered) {
      if (seen.add(r.city)) out.add(r.city);
    }
    return out;
  }

  bool get _hasActiveFilters =>
      _appliedCities.isNotEmpty ||
      _appliedDates.isNotEmpty ||
      _appliedSessions.isNotEmpty;

  bool get _hasAnyInterest =>
      _allRecords.any((r) => r.interested && !r.isSubmitted);

  // ── Overlay management ─────────────────────────────────────────────────────

  void _openFilter(String key) {
    _removeOverlay();
    setState(() {
      _openDropdown = key;
      if (key == 'city') _tempCities = Set.from(_appliedCities);
      if (key == 'date') _tempDates = Set.from(_appliedDates);
      if (key == 'session') _tempSessions = Set.from(_appliedSessions);
    });
    _showOverlay(key);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _openDropdown = null);
  }

  void _showOverlay(String key) {
    final mq = MediaQuery.of(context);
    final sw = mq.size.width;
    final s = (sw / 375.0).clamp(0.80, 1.15);

    final int tabIndex = key == 'city' ? 0 : (key == 'date' ? 1 : 2);

    LayerLink link;
    List<String> options;
    Set<String> tempSet;
    String title;

    if (key == 'city') {
      link = _cityLink;
      options = _allCities;
      tempSet = _tempCities;
      title = 'Select City';
    } else if (key == 'date') {
      link = _dateLink;
      options = _allDates;
      tempSet = _tempDates;
      title = 'Select Date';
    } else {
      link = _sessionLink;
      options = _allSessions;
      tempSet = _tempSessions;
      title = 'Select Session';
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _DropdownOverlay(
        link: link,
        title: title,
        options: options,
        selectedSet: tempSet,
        scale: s,
        screenWidth: sw,
        tabIndex: tabIndex,
        brand: _brand,
        brandLight: _brandLight,
        brandBorder: _brandBorder,
        onToggle: (opt) {
          setState(() {
            if (tempSet.contains(opt)) {
              tempSet.remove(opt);
            } else {
              tempSet.add(opt);
            }
          });
          _overlayEntry?.markNeedsBuild();
        },
        onClear: () {
          setState(() => tempSet.clear());
          _overlayEntry?.markNeedsBuild();
        },
        onApply: () {
          setState(() {
            if (key == 'city') _appliedCities = Set.from(tempSet);
            if (key == 'date') _appliedDates = Set.from(tempSet);
            if (key == 'session') _appliedSessions = Set.from(tempSet);
          });
          _removeOverlay();
        },
        onDismiss: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeChip(String type, String value) {
    setState(() {
      if (type == 'city') _appliedCities.remove(value);
      if (type == 'date') _appliedDates.remove(value);
      if (type == 'session') _appliedSessions.remove(value);
    });
  }

  void _clearAll() => setState(() {
    _appliedCities.clear();
    _appliedDates.clear();
    _appliedSessions.clear();
  });

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitInterest(double s) async {
    final selected = _allRecords.where((r) => r.interested).toList();
    if (selected.isEmpty) return;

    // Show loading indicator dialog while saving to DynamoDB
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 20 * s),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14 * s),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _brand, strokeWidth: 3 * s),
              SizedBox(height: 14 * s),
              Text(
                'Submitting interest...',
                style: TextStyle(
                  fontSize: 13 * s,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final res = await _requirementService.submitInterestRequests(
      supervisorId: widget.supervisorId,
      selectedSlots: selected,
    );

    if (!mounted) return;
    Navigator.pop(context); // Dismiss loading dialog

    if (res['success'] != true) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14 * s),
          ),
          title: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.red.shade600,
                size: 22 * s,
              ),
              SizedBox(width: 8 * s),
              Text(
                'Submission Failed',
                style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            res['error'] ?? 'Failed to submit interest. Please try again.',
            style: TextStyle(fontSize: 13 * s),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'OK',
                style: TextStyle(color: _brand, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Show success dialog
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
                width: 60 * s,
                height: 60 * s,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF7EE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: const Color(0xFF2E7D32),
                  size: 36 * s,
                ),
              ),
              SizedBox(height: 14 * s),
              Text(
                'Interest Submitted!',
                style: TextStyle(
                  fontSize: 17 * s,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6 * s),
              Text(
                'You have expressed interest for ${selected.length} slot${selected.length > 1 ? 's' : ''}.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12 * s, color: Colors.grey.shade600),
              ),
              SizedBox(height: 14 * s),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12 * s),
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(10 * s),
                  border: Border.all(color: _brandBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: selected
                      .map(
                        (r) => Padding(
                          padding: EdgeInsets.symmetric(vertical: 3 * s),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 6 * s, color: _brand),
                              SizedBox(width: 6 * s),
                              Expanded(
                                child: Text(
                                  '${r.city}  |  ${r.center}  |  ${r.date}  |  ${r.session}',
                                  style: TextStyle(
                                    fontSize: 11 * s,
                                    fontWeight: FontWeight.w600,
                                    color: _brand,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
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
                    setState(() {
                      for (final r in selected) {
                        r.interested = false;
                      }
                    });
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

  @override
  void dispose() {
    _removeOverlay();
    _requirementService.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double s = (mq.size.width / 375.0).clamp(0.80, 1.15);

    return GestureDetector(
      onTap: () {
        if (_openDropdown != null) _removeOverlay();
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(s),
        body: Column(
          children: [
            // ── Filter nav ───────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 0),
              child: _buildFilterNav(s),
            ),

            // ── Active chips ─────────────────────────────────────────────
            if (_hasActiveFilters)
              Padding(
                padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 0),
                child: _buildFilterChips(s),
              ),

            SizedBox(height: 10 * s),

            // ── City accordion table ──────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: _brand,
                            strokeWidth: 3 * s,
                          ),
                          SizedBox(height: 14 * s),
                          Text(
                            'Loading supervisor requirements...',
                            style: TextStyle(
                              fontSize: 13 * s,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24 * s),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red.shade400,
                              size: 42 * s,
                            ),
                            SizedBox(height: 10 * s),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13 * s,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 16 * s),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brand,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8 * s),
                                ),
                              ),
                              onPressed: _loadRequirements,
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: 16 * s,
                                color: Colors.white,
                              ),
                              label: Text(
                                'Retry',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12 * s,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildCityAccordions(s),
            ),

            // ── Submit bar ───────────────────────────────────────────────
            _buildSubmitBar(s),
          ],
        ),
        bottomNavigationBar: const AppFooter(),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

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
      titleSpacing: 0,
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6 * s),
            child: Image.asset(
              'assets/images/company_logo.png',
              width: 28 * s,
              height: 28 * s,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 28 * s,
                height: 28 * s,
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(6 * s),
                ),
                child: Icon(Icons.school, color: _brand, size: 16 * s),
              ),
            ),
          ),
          SizedBox(width: 8 * s),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Supervisor Allocation',
                style: TextStyle(
                  fontSize: 18 * s,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.refresh_rounded,
            color: Colors.black87,
            size: 22 * s,
          ),
          tooltip: 'Refresh',
          onPressed: _isLoading ? null : _loadRequirements,
        ),
        IconButton(
          icon: Icon(
            Icons.logout_rounded,
            color: const Color(0xFFE53935),
            size: 22 * s,
          ),
          tooltip: 'Logout',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // ── Submit bar ────────────────────────────────────────────────────────────

  Widget _buildSubmitBar(double s) {
    final bool enabled = _hasAnyInterest;
    final int count = _allRecords.where((r) => r.interested).length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.fromLTRB(16 * s, 10 * s, 16 * s, 12 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFEEEEEE))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: enabled ? 0.06 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48 * s,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1.0 : 0.45,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled ? _brand : Colors.grey.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12 * s),
              ),
              elevation: enabled ? 2 : 0,
            ),
            onPressed: enabled ? () => _submitInterest(s) : null,
            icon: Icon(Icons.send_rounded, size: 18 * s, color: Colors.white),
            label: Text(
              enabled
                  ? 'Submit Interest  ($count selected)'
                  : 'Select slots to submit',
              style: TextStyle(
                fontSize: 14 * s,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Filter nav bar ─────────────────────────────────────────────────────────

  Widget _buildFilterNav(double s) {
    return Container(
      height: 46 * s,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10 * s),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _filterTab(
            key: 'city',
            icon: Icons.location_city_rounded,
            label: 'City',
            link: _cityLink,
            s: s,
          ),
          _vDivider(s),
          _filterTab(
            key: 'date',
            icon: Icons.calendar_today_rounded,
            label: 'Date',
            link: _dateLink,
            s: s,
          ),
          _vDivider(s),
          _filterTab(
            key: 'session',
            icon: Icons.person_outline_rounded,
            label: 'Session',
            link: _sessionLink,
            s: s,
          ),
        ],
      ),
    );
  }

  Widget _vDivider(double s) =>
      Container(width: 1, height: 26 * s, color: const Color(0xFFE0E0E0));

  Widget _filterTab({
    required String key,
    required IconData icon,
    required String label,
    required LayerLink link,
    required double s,
  }) {
    final bool active = _openDropdown == key;
    final bool hasApplied =
        (key == 'city' && _appliedCities.isNotEmpty) ||
        (key == 'date' && _appliedDates.isNotEmpty) ||
        (key == 'session' && _appliedSessions.isNotEmpty);

    return Expanded(
      child: CompositedTransformTarget(
        link: link,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              _openDropdown == key ? _removeOverlay() : _openFilter(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.all(3 * s),
            decoration: BoxDecoration(
              color: active ? _brand : Colors.transparent,
              borderRadius: BorderRadius.circular(7 * s),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15 * s,
                    color: active
                        ? Colors.white
                        : (hasApplied ? _brand : Colors.black54),
                  ),
                  SizedBox(width: 4 * s),
                  Text(
                    label,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white
                          : (hasApplied ? _brand : Colors.black87),
                    ),
                  ),
                  if (hasApplied && !active) ...[
                    SizedBox(width: 3 * s),
                    Container(
                      width: 5 * s,
                      height: 5 * s,
                      decoration: const BoxDecoration(
                        color: _brand,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────────

  Widget _buildFilterChips(double s) {
    final chips = <Widget>[];
    for (final city in _appliedCities) {
      chips.add(_chip('City', city, () => _removeChip('city', city), s));
    }
    for (final date in _appliedDates) {
      chips.add(_chip('Date', date, () => _removeChip('date', date), s));
    }
    for (final session in _appliedSessions) {
      chips.add(
        _chip('Session', session, () => _removeChip('session', session), s),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(spacing: 6 * s, runSpacing: 5 * s, children: chips),
        ),
        SizedBox(width: 6 * s),
        GestureDetector(
          onTap: _clearAll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade400,
                size: 18 * s,
              ),
              Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 9 * s,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String type, String value, VoidCallback onRemove, double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: _brandLight,
        border: Border.all(color: _brandBorder),
        borderRadius: BorderRadius.circular(20 * s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$type: ',
            style: TextStyle(
              fontSize: 10 * s,
              color: _brand.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11 * s,
              color: _brand,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 3 * s),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 13 * s, color: _brand),
          ),
        ],
      ),
    );
  }

  // ── City Accordion Table ────────────────────────────────────────────────────

  Widget _buildCityAccordions(double s) {
    final cities = _filteredCities;

    if (_allRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32 * s),
          child: Text(
            'No supervisor requirements found in database.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13 * s),
          ),
        ),
      );
    }

    if (cities.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32 * s),
          child: Text(
            'No records match the selected filters.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13 * s),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(14 * s, 0, 14 * s, 14 * s),
      itemCount: cities.length,
      itemBuilder: (_, i) {
        final city = cities[i];
        final rows = _filtered.where((r) => r.city == city).toList();
        final expanded = _cityExpanded[city] ?? true;

        return Padding(
          padding: EdgeInsets.only(bottom: 12 * s),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10 * s),
              border: Border.all(color: _brandBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── City header / dropdown trigger ──────────────────────
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(
                    () => _cityExpanded[city] = !(_cityExpanded[city] ?? true),
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14 * s,
                      vertical: 13 * s,
                    ),
                    decoration: BoxDecoration(
                      color: _brand,
                      borderRadius: expanded
                          ? BorderRadius.only(
                              topLeft: Radius.circular(9 * s),
                              topRight: Radius.circular(9 * s),
                            )
                          : BorderRadius.circular(9 * s),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_city_rounded,
                          color: Colors.white,
                          size: 18 * s,
                        ),
                        SizedBox(width: 8 * s),
                        Expanded(
                          child: Text(
                            city,
                            style: TextStyle(
                              fontSize: 14 * s,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${rows.length} slot${rows.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11 * s,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 8 * s),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 200),
                          turns: expanded ? 0.5 : 0.0,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 22 * s,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Expanded table ──────────────────────────────────────
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: expanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: _buildCityTable(rows, s),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCityTable(List<SupervisorRequirementSlot> rows, double s) {
    return Column(
      children: [
        // ── Table header ──────────────────────────────────────────────────
        Container(
          color: const Color(0xFFF5F6FF),
          child: Row(
            children: [
              _th('CENTER', flex: 4, s: s),
              _thDiv(s),
              _th('DATE', flex: 3, s: s),
              _thDiv(s),
              _th('SESSION', flex: 2, s: s),
              _thDiv(s),
              _th('INTERESTED', flex: 2, s: s),
            ],
          ),
        ),

        // ── Table rows ────────────────────────────────────────────────────
        ...List.generate(
          rows.length,
          (i) => _tableRow(rows[i], i, i == rows.length - 1, s),
        ),
      ],
    );
  }

  Widget _th(String label, {required int flex, required double s}) => Expanded(
    flex: flex,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 9 * s, horizontal: 2 * s),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9 * s,
            fontWeight: FontWeight.w700,
            color: _brand,
            letterSpacing: 0.3,
          ),
        ),
      ),
    ),
  );

  Widget _thDiv(double s) =>
      Container(width: 1, height: 36 * s, color: _brandBorder);

  Widget _tableRow(
    SupervisorRequirementSlot r,
    int idx,
    bool isLast,
    double s,
  ) {
    final bool isUnavailable = r.isUnavailable;
    final Color rowBg = isUnavailable
        ? const Color(0xFFEEEEEE)
        : (idx % 2 == 0 ? Colors.white : const Color(0xFFF9F9FF));
    final Color textColor = isUnavailable
        ? Colors.grey.shade500
        : Colors.black87;
    final Color subTextColor = isUnavailable
        ? Colors.grey.shade400
        : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(top: const BorderSide(color: Color(0xFFEEEEEE))),
        borderRadius: isLast
            ? BorderRadius.only(
                bottomLeft: Radius.circular(9 * s),
                bottomRight: Radius.circular(9 * s),
              )
            : BorderRadius.zero,
      ),
      child: Row(
        children: [
          _td(r.center, flex: 4, s: s, bold: !isUnavailable, color: textColor),
          _tdDiv(s),
          _td(r.date, flex: 3, s: s, color: subTextColor),
          _tdDiv(s),
          _td(r.session, flex: 2, s: s, bold: !isUnavailable, color: textColor),
          _tdDiv(s),
          _tdCheckbox(r, flex: 2, s: s),
        ],
      ),
    );
  }

  Widget _td(
    String text, {
    required int flex,
    required double s,
    bool bold = false,
    Color? color,
  }) => Expanded(
    flex: flex,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * s, horizontal: 4 * s),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11 * s,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color ?? Colors.black54,
        ),
      ),
    ),
  );

  Widget _tdDiv(double s) =>
      Container(width: 1, height: 42 * s, color: const Color(0xFFEEEEEE));

  Widget _tdCheckbox(
    SupervisorRequirementSlot r, {
    required int flex,
    required double s,
  }) {
    if (r.isUnavailable) {
      final String badgeText = r.isSubmitted ? 'Applied' : 'Full';
      final Color badgeBg = r.isSubmitted
          ? const Color(0xFFE8F5E9)
          : const Color(0xFFE0E0E0);
      final Color badgeBorder = r.isSubmitted
          ? const Color(0xFFA5D6A7)
          : const Color(0xFFBDBDBD);
      final Color badgeTextColor = r.isSubmitted
          ? const Color(0xFF2E7D32)
          : Colors.grey.shade700;

      return Expanded(
        flex: flex,
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(5 * s),
              border: Border.all(color: badgeBorder, width: 1.2),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 9 * s,
                fontWeight: FontWeight.w700,
                color: badgeTextColor,
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      flex: flex,
      child: Center(
        child: GestureDetector(
          onTap: () => setState(() => r.interested = !r.interested),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20 * s,
            height: 20 * s,
            decoration: BoxDecoration(
              color: r.interested ? _brand : Colors.white,
              borderRadius: BorderRadius.circular(4 * s),
              border: Border.all(color: _brand, width: 1.6),
            ),
            child: r.interested
                ? Icon(Icons.check_rounded, color: Colors.white, size: 13 * s)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLOATING DROPDOWN OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownOverlay extends StatelessWidget {
  final LayerLink link;
  final String title;
  final List<String> options;
  final Set<String> selectedSet;
  final double scale;
  final double screenWidth;
  final int tabIndex;
  final Color brand;
  final Color brandLight;
  final Color brandBorder;
  final void Function(String) onToggle;
  final VoidCallback onClear;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.link,
    required this.title,
    required this.options,
    required this.selectedSet,
    required this.scale,
    required this.screenWidth,
    required this.tabIndex,
    required this.brand,
    required this.brandLight,
    required this.brandBorder,
    required this.onToggle,
    required this.onClear,
    required this.onApply,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final double s = scale;

    final double tabW = (screenWidth - 32 * s) / 3.0;
    final double xOffset = -(tabIndex * tabW);
    final double dropW = (screenWidth - 32 * s).clamp(180.0 * s, 360.0 * s);

    return Stack(
      children: [
        // Barrier
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),

        // Dropdown card
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: Offset(xOffset, 48 * s),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dropW,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11 * s),
                border: Border.all(color: const Color(0xFFE0E0E0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Padding(
                    padding: EdgeInsets.fromLTRB(13 * s, 11 * s, 13 * s, 5 * s),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12 * s,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  // Options
                  ...options.map((opt) {
                    final selected = selectedSet.contains(opt);
                    return GestureDetector(
                      onTap: () => onToggle(opt),
                      child: Container(
                        color: Colors.transparent,
                        padding: EdgeInsets.symmetric(
                          horizontal: 13 * s,
                          vertical: 10 * s,
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 18 * s,
                              height: 18 * s,
                              decoration: BoxDecoration(
                                color: selected ? brand : Colors.white,
                                borderRadius: BorderRadius.circular(4 * s),
                                border: Border.all(
                                  color: selected
                                      ? brand
                                      : const Color(0xFFBBBBBB),
                                  width: 1.5,
                                ),
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 12 * s,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            SizedBox(width: 9 * s),
                            Expanded(
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 12 * s,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected ? brand : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  // Clear / Apply buttons
                  Padding(
                    padding: EdgeInsets.fromLTRB(11 * s, 9 * s, 11 * s, 11 * s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onTap: onApply,
                          child: Container(
                            height: 36 * s,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: brand,
                              borderRadius: BorderRadius.circular(7 * s),
                            ),
                            child: Text(
                              'Apply',
                              style: TextStyle(
                                fontSize: 13 * s,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 7 * s),
                        GestureDetector(
                          onTap: onClear,
                          child: Container(
                            height: 32 * s,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: brand, width: 1.4),
                              borderRadius: BorderRadius.circular(7 * s),
                            ),
                            child: Text(
                              'Clear Selection',
                              style: TextStyle(
                                fontSize: 11 * s,
                                fontWeight: FontWeight.w600,
                                color: brand,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
