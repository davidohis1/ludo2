import 'dart:convert';
import 'package:http/http.dart' as http;

class WithdrawalService {
  // Update this with your server URL
  static const String _baseUrl = 'https://dynamic360tech.name.ng/ludo';
  
  /// Check eligible withdrawal balance
  Future<Map<String, dynamic>> getEligibleBalance(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/withdraw.php?user_id=$userId'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return {
            'success': true,
            'coins': data['data']['coins'],
            'eligibleAmount': data['data']['eligible_amount'].toDouble(),
            'conversionRate': data['data']['conversion_rate'],
          };
        } else {
          return {
            'success': false,
            'message': data['message'],
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
  
  /// Get list of Nigerian banks
  Future<List<Map<String, dynamic>>> getBanks() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.paystack.co/bank'),
        headers: {
          'Authorization': 'Bearer sk_test_62b62967af7367582bb7385e7601b0d622da56ca',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == true) {
          final banks = List<Map<String, dynamic>>.from(data['data']);
          return banks;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  
  /// Verify account number
  Future<Map<String, dynamic>> verifyAccountNumber(
    String accountNumber,
    String bankCode,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.paystack.co/bank/resolve?account_number=$accountNumber&bank_code=$bankCode',
        ),
        headers: {
          'Authorization': 'Bearer sk_test_62b62967af7367582bb7385e7601b0d622da56ca',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == true) {
          return {
            'success': true,
            'accountName': data['data']['account_name'],
            'accountNumber': data['data']['account_number'],
          };
        } else {
          return {
            'success': false,
            'message': data['message'],
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Verification failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
  
  /// Process withdrawal request
  Future<Map<String, dynamic>> processWithdrawal({
    required String userId,
    required double amount,
    required String bankCode,
    required String accountNumber,
    required String accountName,
  }) async {
    try {
      final requestData = {
        'user_id': userId,
        'amount': amount,
        'bank_code': bankCode,
        'account_number': accountNumber,
        'account_name': accountName,
      };
      
      final response = await http.post(
        Uri.parse('$_baseUrl/withdraw.php'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'],
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
  
  /// Get withdrawal history
  Future<List<Map<String, dynamic>>> getWithdrawalHistory(String userId) async {
    // You'll need to implement this endpoint in PHP
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/withdrawal_history.php?user_id=$userId'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}