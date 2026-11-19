import 'package:flutter/material.dart';

import '../../../shared/services/api_client.dart';

// CATATAN PEMELIHARAAN: dialog hanya mengirim sandi saat ini dan sandi baru
// melalui callback API; ia tidak menyimpan atau mengembalikan teks kredensial.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.onSubmit});

  final Future<void> Function(String currentPassword, String newPassword)
  onSubmit;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscurePasswords = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmationController.dispose();
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
      await widget.onSubmit(_currentController.text, _newController.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _passwordVisibilityButton() {
    return IconButton(
      onPressed: () {
        setState(() => _obscurePasswords = !_obscurePasswords);
      },
      tooltip: _obscurePasswords
          ? 'Tampilkan kata sandi'
          : 'Sembunyikan kata sandi',
      icon: Icon(
        _obscurePasswords
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Ubah kata sandi',
        style: TextStyle(color: Color(0xFF172B4D), fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('current-password'),
                  controller: _currentController,
                  obscureText: _obscurePasswords,
                  decoration: InputDecoration(
                    labelText: 'Kata sandi saat ini',
                    suffixIcon: _passwordVisibilityButton(),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Kata sandi saat ini wajib diisi'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('new-password'),
                  controller: _newController,
                  obscureText: _obscurePasswords,
                  decoration: const InputDecoration(
                    labelText: 'Kata sandi baru',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Kata sandi baru wajib diisi';
                    }
                    if (value.runes.length < 12 || value.runes.length > 128) {
                      return 'Gunakan 12–128 karakter';
                    }
                    if (value == _currentController.text) {
                      return 'Kata sandi baru harus berbeda';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('confirm-password'),
                  controller: _confirmationController,
                  obscureText: _obscurePasswords,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Konfirmasi kata sandi baru',
                  ),
                  validator: (value) => value != _newController.text
                      ? 'Konfirmasi kata sandi belum sama'
                      : null,
                ),
                const SizedBox(height: 14),
                if (_errorMessage != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorMessage!,
                      key: const Key('change-password-error'),
                      style: const TextStyle(
                        color: Color(0xFF9C332A),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF168B83),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
