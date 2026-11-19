import 'package:flutter/material.dart';

import '../../../shared/services/api_client.dart';

// CATATAN PEMELIHARAAN: form hanya memvalidasi bentuk input; kredensial
// diverifikasi server oleh ApiClient. Pesan server ditampilkan tanpa menyimpan
// password di widget/state setelah request selesai.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});

  final Future<void> Function(String username, String password) onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onLogin(
        _usernameController.text.trim(),
        _passwordController.text,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          return Row(
            children: [
              if (isWide) const Expanded(flex: 11, child: _LoginBrandPanel()),
              Expanded(
                flex: isWide ? 9 : 1,
                child: Container(
                  color: const Color(0xFFF6F8FB),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isWide ? 40 : 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: _buildForm(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width < 900) ...[
          const _BrandMark(),
          const SizedBox(height: 32),
        ],
        const Text(
          'Selamat datang',
          style: TextStyle(
            color: Color(0xFF172B4D),
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Masuk untuk mengelola inventaris sekolah.',
          style: TextStyle(color: Color(0xFF69778D), fontSize: 14),
        ),
        const SizedBox(height: 30),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Username',
                style: TextStyle(
                  color: Color(0xFF34445D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('login-username'),
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  hintText: 'Masukkan username',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Username wajib diisi'
                    : null,
              ),
              const SizedBox(height: 20),
              const Text(
                'Kata sandi',
                style: TextStyle(
                  color: Color(0xFF34445D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('login-password'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Masukkan kata sandi',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    tooltip: _obscurePassword
                        ? 'Tampilkan kata sandi'
                        : 'Sembunyikan kata sandi',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Kata sandi wajib diisi'
                    : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF168B83),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Masuk',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('login-error'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFF9C332A), fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4F3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF168B83),
                size: 18,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Login memverifikasi akun pada server. Pastikan API inventaris sekolah dapat dijangkau.',
                  style: TextStyle(
                    color: Color(0xFF4F6D6A),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const Center(
          child: Text(
            '© 2026 RuangSarana · Inventaris Sekolah',
            style: TextStyle(color: Color(0xFF9AA5B5), fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _LoginBrandPanel extends StatelessWidget {
  const _LoginBrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172B4D), Color(0xFF1E4864), Color(0xFF168B83)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -100,
            top: -50,
            child: _CircleDecoration(diameter: 360, opacity: 0.06),
          ),
          Positioned(
            left: -120,
            bottom: -180,
            child: _CircleDecoration(diameter: 440, opacity: 0.06),
          ),
          Padding(
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandMark(onDark: true),
                const Spacer(),
                const Text(
                  'Semua aset sekolah,\nlebih mudah terkelola.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pantau barang, lokasi, kondisi, dan riwayatnya dalam satu tempat.',
                  style: TextStyle(
                    color: Color(0xFFD4E5EA),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 34),
                const _FeatureLine(
                  icon: Icons.qr_code_2_rounded,
                  label: 'Pelacakan aset dengan kode inventaris',
                ),
                const SizedBox(height: 15),
                const _FeatureLine(
                  icon: Icons.fact_check_outlined,
                  label: 'Catatan kondisi dan pemeliharaan',
                ),
                const SizedBox(height: 15),
                const _FeatureLine(
                  icon: Icons.bar_chart_rounded,
                  label: 'Ringkasan dan laporan inventaris',
                ),
                const Spacer(),
                const Text(
                  'RuangSarana · Sarana sekolah tercatat, terawat, dan siap digunakan.',
                  style: TextStyle(color: Color(0xFFC4D9DD), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: onDark ? const Color(0xFF20A69A) : const Color(0xFF168B83),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RuangSarana',
              style: TextStyle(
                color: onDark ? Colors.white : const Color(0xFF172B4D),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'INVENTARIS SEKOLAH',
              style: TextStyle(
                color: onDark
                    ? const Color(0xFFB7CFD4)
                    : const Color(0xFF8994A7),
                fontSize: 9,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF8DE0D4), size: 19),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE4F0F1),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CircleDecoration extends StatelessWidget {
  const _CircleDecoration({required this.diameter, required this.opacity});

  final double diameter;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: opacity),
          width: 1.2,
        ),
      ),
    );
  }
}
