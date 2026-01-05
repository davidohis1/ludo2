import 'package:http/http.dart' as http;
import 'dart:convert';

class PaystackService {
  // Use your Paystack test keys
  static const String _secretKey = 'sk_live_c0f51b10fb9361d6ed0b49a83a4f8e79379defad';
  static const String _publicKey = 'pk_live_034a7ac36945002cfd7cef87ee9e89fc977930ac';
  static const String _baseUrl = 'https://api.paystack.co';

  // Initialize payment transaction
  Future<Map<String, dynamic>> initializePayment({
    required String email,
    required int amountInKobo,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/transaction/initialize');
      
      final headers = {
        'Authorization': 'Bearer $_secretKey',
        'Content-Type': 'application/json',
      };
      
      final reference = _generateReference();
      
      final body = json.encode({
        'email': email,
        'amount': amountInKobo.toString(),
        'reference': reference,
        'metadata': {
          'userId': userId,
          'type': 'coin_purchase',
          'coins': (amountInKobo / 100).round(),
        },
        'callback_url': 'https://standard.paystack.co/close',
      });
      
      final response = await http.post(url, headers: headers, body: body);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == true) {
          final responseData = data['data'];
          return {
            'success': true,
            'reference': responseData['reference'],
            'authorizationUrl': responseData['authorization_url'],
            'accessCode': responseData['access_code'],
            'checkoutUrl': responseData['checkout_url'],
            'message': data['message'],
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Transaction initialization failed',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Exception: $e',
      };
    }
  }

  // Verify transaction
  Future<Map<String, dynamic>> verifyTransaction(String reference) async {
    try {
      final url = Uri.parse('$_baseUrl/transaction/verify/$reference');
      
      final headers = {
        'Authorization': 'Bearer $_secretKey',
        'Content-Type': 'application/json',
      };
      
      final response = await http.get(url, headers: headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == true) {
          final transactionData = data['data'];
          return {
            'success': true,
            'status': transactionData['status'],
            'amount': transactionData['amount'],
            'currency': transactionData['currency'],
            'paidAt': transactionData['paid_at'],
            'channel': transactionData['channel'],
            'reference': transactionData['reference'],
            'message': data['message'],
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Transaction verification failed',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Exception: $e',
      };
    }
  }

  // Generate unique reference
  String _generateReference() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    return 'LUDO_${timestamp}_${_generateRandomString(6)}';
  }

  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    final result = StringBuffer();
    
    for (int i = 0; i < length; i++) {
      result.write(chars[(random + i) % chars.length]);
    }
    
    return result.toString();
  }

  // Get public key
  String getPublicKey() => _publicKey;
}
