import 'package:flutter/material.dart';

import 'account.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.enabled = true,
    this.autofillHints,
  });
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: hidden,
    enableSuggestions: false,
    autocorrect: false,
    autofillHints: widget.autofillHints,
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: hidden
            ? 'Show ${widget.label.toLowerCase()}'
            : 'Hide ${widget.label.toLowerCase()}',
        onPressed: () => setState(() => hidden = !hidden),
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({
    super.key,
    required this.account,
    this.email = '',
  });
  final AccountAuth account;
  final String email;
  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final form = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.email);
  bool busy = false, sent = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.account.requestReset(email.text);
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Reset your password'),
      content: SizedBox(
        width: 420,
        child: sent
            ? const Text(
                'If an account exists for this email, password reset instructions have been sent.',
              )
            : Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Enter your registered email address.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: email,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                      ),
                      validator: (v) => validEmail(v ?? '')
                          ? null
                          : 'Enter a valid email address.',
                      onFieldSubmitted: (_) => submit(),
                    ),
                    if (error != null) AccountError(error!),
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(sent ? 'Done' : 'Cancel'),
        ),
        if (!sent)
          FilledButton(
            onPressed: busy ? null : submit,
            child: const Text('Send reset instructions'),
          ),
      ],
    ),
  );
}

class AccountError extends StatelessWidget {
  const AccountError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}

class PasswordUpdateForm extends StatefulWidget {
  const PasswordUpdateForm({
    super.key,
    required this.account,
    required this.onSaved,
    this.recovery = false,
    this.onBusyChanged,
  });
  final AccountAuth account;
  final Future<void> Function() onSaved;
  final bool recovery;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<PasswordUpdateForm> createState() => _PasswordUpdateFormState();
}

class _PasswordUpdateFormState extends State<PasswordUpdateForm> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      nonce = TextEditingController();
  bool busy = false;
  String? error, notice;
  void setBusy(bool value) {
    if (!mounted) return;
    setState(() => busy = value);
    widget.onBusyChanged?.call(value);
  }

  @override
  void dispose() {
    current.dispose();
    password.dispose();
    confirm.dispose();
    nonce.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setBusy(true);
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.account.changePassword(
        password.text,
        current: widget.recovery ? null : current.text,
        nonce: nonce.text,
      );
      current.clear();
      password.clear();
      confirm.clear();
      nonce.clear();
      await widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setBusy(false);
    }
  }

  Future<void> requestCode() async {
    if (busy) return;
    setBusy(true);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.account.client.auth.reauthenticate();
      if (mounted) {
        setState(() => notice = 'Check your email for the verification code.');
      }
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.recovery
              ? 'Set a new password for your account.'
              : 'Confirm your current password to secure this change.',
        ),
        const SizedBox(height: 16),
        if (!widget.recovery) ...[
          PasswordField(
            controller: current,
            label: 'Current password',
            enabled: !busy,
            autofillHints: const [AutofillHints.password],
            validator: (v) =>
                (v ?? '').isEmpty ? 'Enter your current password.' : null,
          ),
          const SizedBox(height: 16),
        ],
        PasswordField(
          controller: password,
          label: 'New password',
          enabled: !busy,
          validator: validatePassword,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 16),
        PasswordField(
          controller: confirm,
          label: 'Confirm new password',
          enabled: !busy,
          validator: (v) => v != password.text || (v ?? '').isEmpty
              ? 'Passwords must match.'
              : null,
        ),
        if (!widget.recovery) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: nonce,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Verification code (if requested)',
            ),
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
          ),
          TextButton(
            onPressed: busy ? null : requestCode,
            child: const Text('Request verification code'),
          ),
        ],
        if (notice != null) Semantics(liveRegion: true, child: Text(notice!)),
        if (error != null) AccountError(error!),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy ? null : submit,
          child: const Text('Update password'),
        ),
      ],
    ),
  );
}

Future<void> showChangePassword(
  BuildContext context,
  AccountAuth account,
) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ChangePasswordDialog(account: account),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Password updated.')));
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.account});
  final AccountAuth account;
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Change password'),
      content: SizedBox(
        width: 420,
        child: PasswordUpdateForm(
          account: widget.account,
          onBusyChanged: (value) => setState(() => busy = value),
          onSaved: () async {
            setState(() => busy = false);
            // Rebuild PopScope before closing the protected dialog.
            await WidgetsBinding.instance.endOfFrame;
            if (context.mounted) Navigator.pop(context, true);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
