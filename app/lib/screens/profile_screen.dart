import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/attendance.dart';
import '../services/auth.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  List<Map<String, dynamic>>? _leaveBalance;
  String? _balanceError;

  @override
  void initState() {
    super.initState();
    _loadLeaveBalance();
  }

  Future<void> _loadLeaveBalance() async {
    try {
      final api = context.read<Api>();
      final data = await api.get('/leaves/balance') as List;
      if (mounted) {
        setState(() {
          _leaveBalance = data.cast<Map<String, dynamic>>();
          _balanceError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _balanceError = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final me = auth.employee;
    if (me == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          _header(me),
          const SectionTitle('Employment'),
          NesfCard(
            child: Column(
              children: [
                DetailRow('Employee code', me.empCode),
                DetailRow('Designation', me.designation),
                DetailRow('Department', me.department),
                if (me.grade != null) DetailRow('Grade', me.grade),
                DetailRow('Role in the app', me.roleLabel),
                if (me.reportingToName != null)
                  DetailRow('Reports to', me.reportingToName),
                DetailRow('Email', me.email),
                if (me.phone != null) DetailRow('Phone', me.phone),
              ],
            ),
          ),

          // Only people who sign documents need a signature on file.
          if (me.isReviewer) ...[
            const SectionTitle('Signature'),
            _signatureCard(me),
          ],

          const SectionTitle('Attendance base'),
          _baseCard(me),

          const SectionTitle('Leave balance'),
          _leaveBalanceCard(),

          const SectionTitle('My records'),
          NesfCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _link(Icons.event_busy_rounded, 'Leave applications', '/leaves'),
                const Divider(height: 1),
                _link(Icons.description_outlined, 'Work reports', '/reports'),
                const Divider(height: 1),
                _link(Icons.receipt_long_rounded, 'TA/DA claims', '/tada'),
                const Divider(height: 1),
                _link(Icons.emoji_events_outlined, 'Projects & activities', '/projects'),
                const Divider(height: 1),
                _link(Icons.handshake_outlined, 'Contacts & donors', '/crm'),
              ],
            ),
          ),

          const SectionTitle('Account'),
          NesfCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key_outlined, size: 20, color: NesfColors.green),
                  title: const Text('Change password', style: TextStyle(fontSize: 14)),
                  subtitle: me.mustChangePassword
                      ? const Text('Still using the password issued by the office',
                          style: TextStyle(fontSize: 11.5, color: NesfColors.pending))
                      : null,
                  trailing: const Icon(Icons.chevron_right_rounded, color: NesfColors.muted),
                  onTap: _changePassword,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, size: 20, color: NesfColors.rejected),
                  title: const Text('Sign out',
                      style: TextStyle(fontSize: 14, color: NesfColors.rejected)),
                  onTap: _signOut,
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Text('${AppConfig.appName} · v1.0.0',
                    style: const TextStyle(fontSize: 11.5, color: NesfColors.muted)),
                const SizedBox(height: 3),
                Text(AppConfig.orgName,
                    style: const TextStyle(fontSize: 11, color: NesfColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Employee me) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [NesfColors.green, NesfColors.greenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Avatar(initials: me.initials, photoKey: me.photoUrl, size: 62),
              Positioned(
                bottom: 0, right: 0,
                child: InkWell(
                  onTap: _busy ? null : _uploadPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: NesfColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: NesfColors.green, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 12, color: NesfColors.ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me.fullName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(me.designation ?? 'Staff',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(me.roleLabel,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The signature image is stamped onto every document this person approves, so
  /// its absence is worth calling out explicitly.
  Widget _signatureCard(Employee me) {
    final hasSignature = me.signatureUrl != null && me.signatureUrl!.isNotEmpty;

    return NesfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasSignature)
            Container(
              height: 78,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NesfColors.surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: PrivateImage(
                storageKey: me.signatureUrl,
                fit: BoxFit.contain,
                errorWidget: const Center(
                  child: Text('Signature could not be loaded',
                      style: TextStyle(fontSize: 12, color: NesfColors.muted)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NesfColors.pendingBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(Icons.draw_outlined, size: 19, color: NesfColors.pending),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No signature uploaded. Documents you approve will print a blank '
                      'signature line until you add one.',
                      style: TextStyle(fontSize: 12, color: NesfColors.pending, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _uploadSignature,
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: Text(hasSignature ? 'Replace signature' : 'Upload signature'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign on white paper, photograph it, and upload. A PNG with a '
            'transparent background reproduces best on letterhead.',
            style: TextStyle(fontSize: 11, color: NesfColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _baseCard(Employee me) {
    return NesfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                me.hasBaseLocation ? Icons.location_on_rounded : Icons.location_off_outlined,
                size: 19,
                color: me.hasBaseLocation ? NesfColors.approved : NesfColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  me.hasBaseLocation
                      ? '${me.baseLabel ?? 'Base set'} · ${me.baseLat!.toStringAsFixed(4)}, ${me.baseLng!.toStringAsFixed(4)}'
                      : 'Not set — check-ins cannot be judged on-site or off-site',
                  style: const TextStyle(fontSize: 12.5, color: NesfColors.body, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _setBase(me),
            icon: const Icon(Icons.my_location_rounded, size: 18),
            label: Text(me.hasBaseLocation ? 'Update to my current location' : 'Set from my location'),
          ),
        ],
      ),
    );
  }

  Widget _leaveBalanceCard() {
    if (_balanceError != null) {
      return NesfCard(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NesfColors.infoBg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outlined, size: 19, color: NesfColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _balanceError!,
                  style: const TextStyle(fontSize: 12, color: NesfColors.info, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_leaveBalance == null) {
      return const NesfCard(
        child: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_leaveBalance!.isEmpty) {
      return NesfCard(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NesfColors.surface,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Text(
            'No leave types configured',
            style: TextStyle(fontSize: 12, color: NesfColors.muted),
          ),
        ),
      );
    }

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _leaveBalance!.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final b = _leaveBalance![i] as Map<String, dynamic>;
          final available = (b['available'] as num?)?.toDouble() ?? 0.0;
          final entitled = (b['entitled'] as num?)?.toDouble() ?? 0.0;
          return Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: NesfColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${b['name']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: NesfColors.muted, height: 1.25),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      available.toInt().toString(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: available <= 0 ? NesfColors.rejected : NesfColors.green,
                      ),
                    ),
                    Text(' / ${entitled.toInt()}',
                        style: const TextStyle(fontSize: 12, color: NesfColors.muted)),
                  ],
                ),
                const Text('days', style: TextStyle(fontSize: 10.5, color: NesfColors.muted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _link(IconData icon, String label, String path) {
    return ListTile(
      leading: Icon(icon, size: 20, color: NesfColors.green),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right_rounded, color: NesfColors.muted),
      onTap: () => context.push(path),
    );
  }

  Future<void> _uploadPhoto() => _uploadImage(
        source: ImageSource.camera,
        endpoint: (id) => '/employees/$id/photo',
        field: 'photo',
        successMessage: 'Photo updated.',
      );

  Future<void> _uploadSignature() => _uploadImage(
        source: ImageSource.gallery,
        endpoint: (id) => '/employees/$id/signature',
        field: 'signature',
        successMessage: 'Signature saved. It will appear on documents you approve.',
      );

  Future<void> _uploadImage({
    required ImageSource source,
    required String Function(int id) endpoint,
    required String field,
    required String successMessage,
  }) async {
    // Resolve the providers before awaiting the picker: the camera can put this
    // screen in the background, and reading context afterwards is unsafe.
    final auth = context.read<AuthService>();
    final api = context.read<Api>();

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final result = await api.upload(
        endpoint(auth.employee!.id),
        field: field,
        filename: picked.name.isEmpty ? '$field.jpg' : picked.name,
        bytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
      ) as Map<String, dynamic>;

      await auth.refresh();
      if (!mounted) return;
      // The server may advise a transparent PNG for a cleaner letterhead result.
      showSnack(context, result['note'] as String? ?? successMessage);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBase(Employee me) async {
    setState(() => _busy = true);
    try {
      await context.read<AttendanceService>()
          .setBaseHere(me.id, label: me.baseLabel ?? 'My base');
      if (!mounted) return;
      await context.read<AuthService>().refresh();
      if (mounted) showSnack(context, 'Base location saved.');
    } on CaptureException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: current,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'At least 8 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                  validator: (v) => v != next.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 10),
                const Text(
                  'You will stay signed in on this device; other devices will need '
                  'to sign in again.',
                  style: TextStyle(fontSize: 11.5, color: NesfColors.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await context.read<AuthService>().changePassword(current.text, next.text);
      if (mounted) showSnack(context, 'Password changed.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your password to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: NesfColors.rejected),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthService>().signOut();
  }
}
