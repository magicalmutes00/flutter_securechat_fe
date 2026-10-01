import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_tokens.dart';
import '../blocs/auth/auth_bloc.dart';
import '../blocs/auth/auth_event.dart';
import '../blocs/auth/auth_state.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/ui/ui.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // Email/Password controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isEmailRegisterMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Inline validation errors (null = valid / untouched).
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  // Phone controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  String? _phoneError;
  String? _otpError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _tabIndex) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // Email/Password auth -------------------------------------------------------

  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  void _submitEmailAuth() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _emailError = email.isEmpty
          ? 'Please enter your email'
          : (!_isValidEmail(email) ? 'Enter a valid email address' : null);
      _passwordError = password.isEmpty ? 'Please enter your password' : null;
      _confirmError = null;
      if (_isEmailRegisterMode) {
        if (password != _confirmPasswordController.text) {
          _confirmError = 'Passwords do not match';
        } else if (password.length < 6) {
          _passwordError = 'Use at least 6 characters';
        }
      }
    });

    if (_emailError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }

    if (_isEmailRegisterMode) {
      context.read<AuthBloc>().add(AuthEmailRegisterRequested(
            email: email,
            password: password,
            displayName: _displayNameController.text.trim().isNotEmpty
                ? _displayNameController.text.trim()
                : null,
          ));
    } else {
      context.read<AuthBloc>().add(AuthEmailLoginRequested(
            email: email,
            password: password,
          ));
    }
  }

  // Phone OTP auth ------------------------------------------------------------

  String _normalizePhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+')) return trimmed;
    // Default to India country code when no international prefix is given.
    return '+91$trimmed';
  }

  void _sendOtp() {
    final phone = _phoneController.text.trim();
    setState(() {
      _phoneError = phone.isEmpty ? 'Please enter your phone number' : null;
    });
    if (_phoneError != null) return;

    context
        .read<AuthBloc>()
        .add(AuthFirebaseOtpRequested(phone: _normalizePhone(phone)));
  }

  void _signInWithGoogle() {
    context.read<AuthBloc>().add(AuthGoogleSignInRequested());
  }

  void _verifyOtp() {
    final state = context.read<AuthBloc>().state;
    final code = _otpController.text.trim();

    setState(() {
      if (code.isEmpty) {
        _otpError = 'Please enter the verification code';
      } else if (code.length != 6) {
        _otpError = 'The code is 6 digits';
      } else if (state.verificationId == null ||
          state.verificationId!.isEmpty) {
        _otpError = 'Please request a code first';
      } else {
        _otpError = null;
      }
    });
    if (_otpError != null) return;

    context.read<AuthBloc>().add(AuthFirebaseOtpVerifyRequested(otpCode: code));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == AuthStatus.authenticated) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          } else if (state.status == AuthStatus.error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'An error occurred'),
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state.status == AuthStatus.loading;
          return SafeArea(
            child: Stack(
              children: [
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.primaryContainer.withValues(alpha: 0.55),
                        colors.primaryContainer.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      _BrandHeader(),
                      const SizedBox(height: AppSpacing.xxl),
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Email'),
                          Tab(text: 'Phone'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // IndexedStack sized by its child: no fixed height,
                      // no nested scrolling — the page scrolls as one.
                      IndexedStack(
                        index: _tabIndex,
                        children: [
                          _buildEmailTab(isLoading),
                          _buildPhoneTab(state, isLoading),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md),
                            child: Text(
                              'or',
                              style: context.text.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      GoogleSignInButton(
                        onPressed: _signInWithGoogle,
                        isLoading: isLoading,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmailTab(bool isLoading) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isEmailRegisterMode
                    ? 'Already have an account?'
                    : "Don't have an account?",
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _isEmailRegisterMode = !_isEmailRegisterMode;
                  _emailError = _passwordError = _confirmError = null;
                }),
                child: Text(_isEmailRegisterMode ? 'Login' : 'Register'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_isEmailRegisterMode) ...[
            AppTextField(
              controller: _displayNameController,
              labelText: 'Display name',
              hintText: 'Your name',
              prefixIcon: const Icon(Icons.person_outline),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppTextField(
            controller: _emailController,
            labelText: 'Email',
            hintText: 'you@example.com',
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _passwordController,
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            obscureText: _obscurePassword,
            textInputAction: _isEmailRegisterMode
                ? TextInputAction.next
                : TextInputAction.done,
            autofillHints: _isEmailRegisterMode
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            errorText: _passwordError,
            onChanged: (_) {
              if (_passwordError != null) {
                setState(() => _passwordError = null);
              }
            },
            onSubmitted: (_) {
              if (!_isEmailRegisterMode) _submitEmailAuth();
            },
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          if (_isEmailRegisterMode) ...[
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _confirmPasswordController,
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline),
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              errorText: _confirmError,
              onChanged: (_) {
                if (_confirmError != null) {
                  setState(() => _confirmError = null);
                }
              },
              onSubmitted: (_) => _submitEmailAuth(),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() =>
                    _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: _isEmailRegisterMode ? 'Create account' : 'Login',
            loading: isLoading,
            onPressed: _submitEmailAuth,
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneTab(AuthState state, bool isLoading) {
    final isOtpStep = state.otpPhone != null;

    if (!isOtpStep) {
      return AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _phoneController,
              labelText: 'Phone number',
              hintText: '+91 98765 43210',
              prefixIcon: const Icon(Icons.phone_outlined),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              errorText: _phoneError,
              onChanged: (_) {
                if (_phoneError != null) {
                  setState(() => _phoneError = null);
                }
              },
              onSubmitted: (_) => _sendOtp(),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Send code',
              loading: isLoading,
              onPressed: _sendOtp,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'You will receive a 6-digit verification code by SMS.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the 6-digit code sent to\n${state.otpPhone ?? ''}',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppTextField(
            controller: _otpController,
            labelText: 'Verification code',
            style: const TextStyle(fontSize: 22, letterSpacing: 8),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            errorText: _otpError,
            onChanged: (_) {
              if (_otpError != null) setState(() => _otpError = null);
            },
            onSubmitted: (_) => _verifyOtp(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Verify & continue',
            loading: isLoading,
            onPressed: _verifyOtp,
          ),
          AppButton.ghost(
            label: 'Resend code',
            onPressed: isLoading ? null : _sendOtp,
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.card(context.theme.brightness),
          ),
          child: Image.asset(
            'assets/images/logo.png',
            width: 72,
            height: 72,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('SecureChat', style: context.text.displayMedium),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Simple, fast messaging',
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
