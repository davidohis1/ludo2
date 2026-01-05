import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Toast utility for showing messages using Toastification
class ToastUtils {
  static void showSuccess(BuildContext context, String message) {
    toastification.show(
      context: context,
      title: const Text('Success'),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      alignment: Alignment.topRight,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07000000),
          blurRadius: 16,
          offset: Offset(0, 16),
          spreadRadius: 0,
        ),
      ],
      showProgressBar: true,
    );
  }

  static void showError(BuildContext context, String message) {
    toastification.show(
      context: context,
      title: const Text('Error'),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 4),
      type: ToastificationType.error,
      style: ToastificationStyle.flat,
      alignment: Alignment.topRight,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07000000),
          blurRadius: 16,
          offset: Offset(0, 16),
          spreadRadius: 0,
        ),
      ],
      showProgressBar: true,
    );
  }

  static void showInfo(BuildContext context, String message) {
    toastification.show(
      context: context,
      title: const Text('Info'),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      type: ToastificationType.info,
      style: ToastificationStyle.flat,
      alignment: Alignment.topRight,
      borderRadius: BorderRadius.circular(12),
      showProgressBar: false,
    );
  }

  static void showWarning(BuildContext context, String message) {
    toastification.show(
      context: context,
      title: const Text('Warning'),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      type: ToastificationType.warning,
      style: ToastificationStyle.flat,
      alignment: Alignment.topRight,
      borderRadius: BorderRadius.circular(12),
      showProgressBar: true,
    );
  }

  static void showCustom({
    required BuildContext context,
    required String message,
    required Color backgroundColor,
    required IconData icon,
  }) {
    toastification.showCustom(
      context: context,
      autoCloseDuration: const Duration(seconds: 3),
      alignment: Alignment.topRight,
      builder: (context, holder) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: backgroundColor,
            boxShadow: const [
              BoxShadow(
                color: Color(0x07000000),
                blurRadius: 16,
                offset: Offset(0, 16),
                spreadRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
