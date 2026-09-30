import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Standardized text field. Visuals come from the theme's
/// [InputDecorationTheme]; this widget only standardizes the API surface
/// (label, inline error, icons, input actions) so validation can move from
/// SnackBars to inline `errorText`.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final bool enabled;
  final TextStyle? style;
  final TextAlign textAlign;

  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.inputFormatters,
    this.autofillHints,
    this.autofocus = false,
    this.enabled = true,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      autofocus: autofocus,
      enabled: enabled,
      style: style,
      textAlign: textAlign,
    );
  }
}
