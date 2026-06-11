import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/loading_overlay.dart';

class RfidManagementScreen extends StatefulWidget {
  const RfidManagementScreen({super.key});
  @override
  State<RfidManagementScreen> createState() => _RfidManagementScreenState();
}

class _RfidManagementScreenState extends State<RfidManagementScreen> {
  final _api = ApiService();

  List<Map<String, dynamic>> _cards     = [];
  List<EmployeeModel>        _employees = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load all pages of employees to get full list
      final allEmployees = <EmployeeModel>[];
      int page  = 1;
      int pages = 1;

      do {
        final resp = await _api.get('/employees', params: {
          'status':   'active',
          'per_page': '50',
          'page':     '$page',
        });
        final data = resp.data as Map<String, dynamic>;
        final items = (data['employees'] as List)
            .map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>))
            .toList();
        allEmployees.addAll(items);
        pages = data['pages'] as int? ?? 1;
        page++;
      } while (page <= pages);

      // Load unassigned cards
      final cardsResp = await _api.get('/rfid/cards');
      final cardsData = cardsResp.data as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _employees = allEmployees;
          _cards = (cardsData['cards'] as List)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      _showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Employees WITHOUT a card — shown in assign dropdown

  // Employees WITH a card — shown in assigned section
  List<EmployeeModel> get _assignedEmployees => _employees
      .where((e) => e.rfidCardUid != null && e.rfidCardUid!.trim().isNotEmpty)
      .toList();

  Future<void> _assignCard(String cardUid, String employeeId) async {
    try {
      await _api.post('/rfid/assign', data: {
        'card_uid':    cardUid,
        'employee_id': employeeId,
      });
      _showSuccess('Card $cardUid assigned successfully');
      _load();
    } catch (e) {
      _showError(apiErrorMessage(e));
    }
  }

  Future<void> _deleteCard(String cardId, String cardUid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Card'),
        content: Text('Remove card $cardUid from registry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete('/rfid/cards/$cardId');
      _showSuccess('Card removed');
      _load();
    } catch (e) {
      _showError(apiErrorMessage(e));
    }
  }

  void _showAssignDialog(Map<String, dynamic> card) {
  String? selectedEmployeeId;
  final cardUid = card['card_uid'] as String;

  // Debug: print all employees and their card status
  debugPrint('Total employees loaded: ${_employees.length}');
  for (final e in _employees) {
    debugPrint('  ${e.fullName} | card: ${e.rfidCardUid ?? "NONE"}');
  }

  // Show employees who have NO card assigned
  final available = _employees
      .where((e) =>
          e.rfidCardUid == null ||
          e.rfidCardUid!.trim().isEmpty ||
          e.rfidCardUid == 'null')
      .toList();

  debugPrint('Available (no card): ${available.length}');

  if (available.isEmpty) {
    _showError('All active employees already have cards assigned');
    return;
  }

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setDlgState) => AlertDialog(
        title: Text('Assign $cardUid'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.credit_card,
                  color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text(cardUid,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryBlue,
                      fontSize: 15,
                      letterSpacing: 1)),
            ]),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Select employee (no card assigned):',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedEmployeeId,
            hint: const Text('Select employee'),
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: available
                .map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.fullName}  (${e.employeeId})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setDlgState(() => selectedEmployeeId = v),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selectedEmployeeId == null
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _assignCard(cardUid, selectedEmployeeId!);
                  },
            child: const Text('Assign'),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _confirmUnassign(EmployeeModel employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unassign Card'),
        content: Text(
          'Remove card ${employee.rfidCardUid} from '
          '${employee.fullName}?\n\n'
          'The card will return to the unassigned pool.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange),
            child: const Text('Unassign'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.post('/rfid/unassign',
          data: {'employee_id': employee.id});
      _showSuccess('Card unassigned from ${employee.fullName}');
      _load();
    } catch (e) {
      _showError(apiErrorMessage(e));
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: AppTheme.accentGreen));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: AppTheme.accentRed));
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('d MMM yyyy, HH:mm')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final assigned   = _assignedEmployees;


    return LoadingOverlay(
      isLoading: _loading,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              // ── Header ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RFID Card Registry',
                            style: AppTextStyles.heading2),
                        Text(
                          '${_cards.length} unassigned · '
                          '${assigned.length} assigned',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _load,
                    ),
                  ]),
                ),
              ),

              // ── Info banner ──────────────────────────────────
              if (_cards.isNotEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.2)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.primaryBlue, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'New cards appear here when tapped on the reader. '
                          'Tap a card to assign it to an employee.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF334155)),
                        ),
                      ),
                    ]),
                  ),
                ),

              // ── Unassigned cards section label ───────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Row(children: [
                    const Icon(Icons.credit_card_off_outlined,
                        size: 18, color: AppTheme.accentOrange),
                    const SizedBox(width: 8),
                    Text(
                      'Unassigned Cards (${_cards.length})',
                      style: AppTextStyles.bodyMed,
                    ),
                  ]),
                ),
              ),

              // ── Unassigned cards list ────────────────────────
              _cards.isEmpty
                  ? SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(children: [
                          Icon(Icons.credit_card_off_outlined,
                              size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('No unassigned cards',
                              style: TextStyle(color: Colors.grey[500])),
                          const SizedBox(height: 4),
                          Text(
                            'Tap a new RFID card on the reader\n'
                            'and it will appear here automatically.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[400]),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: _RfidCardTile(
                            card: _cards[i],
                            formattedDate:
                                _fmtDate(_cards[i]['last_seen'] as String?),
                            onAssign: () => _showAssignDialog(_cards[i]),
                            onDelete: () => _deleteCard(
                              _cards[i]['id'] as String,
                              _cards[i]['card_uid'] as String,
                            ),
                          ),
                        ),
                        childCount: _cards.length,
                      ),
                    ),

              // ── Assigned cards section ───────────────────────
              if (assigned.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppTheme.accentGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Assigned Cards (${assigned.length})',
                        style: AppTextStyles.bodyMed,
                      ),
                    ]),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _AssignedCardTile(
                        employee: assigned[i],
                        onUnassign: () => _confirmUnassign(assigned[i]),
                      ),
                    ),
                    childCount: assigned.length,
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Unassigned Card Tile ───────────────────────────────────────

class _RfidCardTile extends StatelessWidget {
  final Map<String, dynamic> card;
  final String formattedDate;
  final VoidCallback onAssign;
  final VoidCallback onDelete;

  const _RfidCardTile({
    required this.card,
    required this.formattedDate,
    required this.onAssign,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final uid      = card['card_uid'] as String;
    final tapCount = card['tap_count'] as int? ?? 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.credit_card,
                color: AppTheme.accentOrange, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(uid,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text('Last seen: $formattedDate',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF94A3B8))),
                Text('Tapped $tapCount time${tapCount > 1 ? "s" : ""}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton(
              onPressed: onAssign,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(90, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Assign',
                  style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentRed,
                minimumSize: const Size(90, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Remove',
                  style: TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Assigned Card Tile ─────────────────────────────────────────

class _AssignedCardTile extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback  onUnassign;

  const _AssignedCardTile({
    required this.employee,
    required this.onUnassign,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accentGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.credit_card,
              color: AppTheme.accentGreen, size: 22),
        ),
        title: Text(employee.fullName,
            style: AppTextStyles.bodyMed),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(employee.employeeId,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8))),
            Text(
              employee.rfidCardUid ?? '',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentGreen,
                  letterSpacing: 0.5),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: onUnassign,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accentOrange,
          ),
          child: const Text('Unassign'),
        ),
      ),
    );
  }
}
