import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '/constants/colors.dart';
import '/cubits/user/user_cubit.dart';
import '/services/database_service.dart';
import '/services/paystack_service.dart';
import '/utils/toast_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final DatabaseService databaseService = DatabaseService();
  final PaystackService paystackService = PaystackService();
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  bool _isProcessing = false;
  double _withdrawableBalance = 0.0;
  bool _hasPendingWithdrawal = false;
  
  // FIX 1: Add this line here at class level
  late Future<List<Map<String, dynamic>>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _checkPendingWithdrawals();
    
    // FIX 2: Initialize here
    if (userId != null) {
      _transactionsFuture = databaseService.getUserTransactionsOnce(userId!);
    }
  }

  // FIX 3: Add this method here at class level
  Future<void> _refreshTransactions() async {
    if (userId == null) return;
    
    if (mounted) {
      setState(() {
        _transactionsFuture = databaseService.getUserTransactionsOnce(userId!);
      });
    }
  }

  Future<void> _checkPendingWithdrawals() async {
    if (userId == null) return;
    
    try {
      final response = await http.post(
        Uri.parse('https://dynamic360tech.name.ng/ludo/check_pending.php'),
        body: {'user_id': userId},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _hasPendingWithdrawal = data['has_pending'] == true;
          });
        }
      }
    } catch (e) {
      print('Error checking pending withdrawals: $e');
    }
  }

  Future<void> _loadWithdrawableBalance() async {
  if (userId == null) return;
  
  try {
    // First migrate user if needed
    await databaseService.migrateUserBalance(userId!);
    
    // Get user document
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId!)
        .get();
    
    if (userDoc.exists) {
      final data = userDoc.data()!;
      final winningCoins = (data['winningCoins'] ?? 0).toDouble();
      
      if (mounted) {
        setState(() {
          _withdrawableBalance = winningCoins;
        });
      }
    }
  } catch (e) {
    print('Error loading withdrawable balance: $e');
  }
}

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: User not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet'), centerTitle: true),
      body: BlocBuilder<UserCubit, UserState>(
        builder: (context, userState) {
          final user = userState is UserLoaded ? userState.currentUser : null;

          if (user == null) {
            if (userState is UserError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'Data Load Error: ${userState.message}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          // Load withdrawable balance when user data is available
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadWithdrawableBalance();
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Balance Cards
                Column(
                  children: [
                    // Total Balance Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Balance',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet,
                                  color: AppColors.white,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            user.totalCoins.toStringAsFixed(0),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Available coin',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Withdrawable Balance Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primaryRed.withOpacity(0.9),
                            AppColors.primaryPink.withOpacity(0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Withdrawable Balance',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.attach_money,
                                  color: AppColors.white,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _withdrawableBalance.toStringAsFixed(0),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Winnings from games (deposits not withdrawable)',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
  child: ElevatedButton(
    onPressed: _isProcessing ? null : () {
      // Get email directly from Firebase Auth (always available for logged in users)
      final currentUser = FirebaseAuth.instance.currentUser;
      final userEmail = currentUser?.email;
      
      if (userEmail != null && userEmail.isNotEmpty) {
        _showAddCoinsDialog(context, userId!, userEmail);
      } else {
        ToastUtils.showError(context, 'Unable to get your email. Please check your account.');
      }
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryRed,
      foregroundColor: AppColors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    child: _isProcessing
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Text(
            'Add Coins',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
  ),
),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _hasPendingWithdrawal 
                            ? () {
                                ToastUtils.showInfo(context, 'You have a pending withdrawal. Please wait for it to be processed.');
                              }
                            : () {
                                if (_withdrawableBalance < 1000) {
                                  ToastUtils.showError(context, 'Minimum withdrawable balance is 1000 coins');
                                  return;
                                }
                                _showWithdrawDialog(context, user.displayName ?? user.email, _withdrawableBalance);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasPendingWithdrawal 
                              ? Colors.grey 
                              : AppColors.primaryPink,
                          foregroundColor: _hasPendingWithdrawal 
                              ? Colors.white 
                              : AppColors.primaryRed,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _hasPendingWithdrawal
                            ? const Text(
                                'Pending Withdrawal',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : const Text(
                                'Withdraw',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Add this in the Column children, after the Row with Add Coins and Withdraw buttons
const SizedBox(height: 16),

// TEST BUTTON - REMOVE IN PRODUCTION



                // Quick Purchase Options
                const Text(
                  'Quick Purchase:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildQuickPurchaseOption(100, '₦100', context, user.email),
                    _buildQuickPurchaseOption(500, '₦500', context, user.email),
                    _buildQuickPurchaseOption(1000, '₦1,000', context, user.email),
                    _buildQuickPurchaseOption(2500, '₦2,500', context, user.email),
                  ],
                ),

                const SizedBox(height: 16),

                // View Transactions Button
                OutlinedButton(
                  onPressed: () {
                    _showTransactionHistory(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryRed,
                    side: const BorderSide(
                      color: AppColors.primaryRed,
                      width: 2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'View Transactions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: 32),

                // Transaction History
                const Text(
                  'Transaction History',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                // FIX 4: Remove the duplicate declarations that were in the build method
                // and use this Row with refresh button
                Row(
                  children: [
                    const Text(
                      'Transaction History',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshTransactions,
                      tooltip: 'Refresh transactions',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Transaction List - USING FutureBuilder
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _transactionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Error loading transactions',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'No transactions yet',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final transaction = snapshot.data![index];
                        return _buildTransactionItem(transaction);
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, String userName, double withdrawableBalance) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final accountNumberController = TextEditingController();
    final accountNameController = TextEditingController();
    final bankController = TextEditingController();
    
    String? selectedBank;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Withdraw Funds'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Withdrawable Balance:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${withdrawableBalance.toStringAsFixed(0)} coins',
                            style: const TextStyle(
                              color: AppColors.primaryRed,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Amount Field
                    TextFormField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount to Withdraw (Coins)',
                        border: OutlineInputBorder(),
                        prefixText: '',
                        suffixText: 'coins',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter amount';
                        }
                        final amount = double.tryParse(value);
                        if (amount == null) {
                          return 'Please enter a valid number';
                        }
                        if (amount < 1000) {
                          return 'Minimum withdrawal is 1000 coins';
                        }
                        if (amount > 10000) {
                          return 'Maximum withdrawal per day is 10000 coins';
                        }
                        if (amount > withdrawableBalance) {
                          return 'Insufficient withdrawable balance';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Account Number
                    TextFormField(
                      controller: accountNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Account Number',
                        border: OutlineInputBorder(),
                        hintText: '10-digit account number',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter account number';
                        }
                        if (value.length != 10) {
                          return 'Account number must be 10 digits';
                        }
                        if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                          return 'Please enter valid account number';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Bank Selection
                    DropdownButtonFormField<String>(
                      value: selectedBank,
                      decoration: const InputDecoration(
                        labelText: 'Bank',
                        border: OutlineInputBorder(),
                      ),
                      items: _getBankList().map((bank) {
                        return DropdownMenuItem(
                          value: bank,
                          child: Text(bank),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedBank = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a bank';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Account Name
                    TextFormField(
                      controller: accountNameController,
                      decoration: const InputDecoration(
                        labelText: 'Account Name',
                        border: OutlineInputBorder(),
                        hintText: 'Name as it appears on bank account',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter account name';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Terms and Conditions
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Important Notes:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('• Maximum withdrawal: 10,000 coins per day'),
                          SizedBox(height: 4),
                          Text('• Minimum withdrawal: 1,000 coins'),
                          SizedBox(height: 4),
                          Text('• Withdrawal processing: 2-4 hours'),
                          SizedBox(height: 4),
                          Text('• Only one withdrawal per day allowed'),
                          SizedBox(height: 4),
                          Text('• Deposited coins are not withdrawable'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _isProcessing ? null : () async {
                  if (formKey.currentState!.validate()) {
                    await _processWithdrawal(
                      context,
                      userId!,
                      userName,
                      double.parse(amountController.text),
                      accountNumberController.text,
                      selectedBank!,
                      accountNameController.text,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Withdrawal'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processWithdrawal(
    BuildContext context,
    String userId,
    String userName,
    double amount,
    String accountNumber,
    String bank,
    String accountName,
  ) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://dynamic360tech.name.ng/ludo/withdraw1.php'),
        body: {
          'user_id': userId,
          'user_name': userName,
          'amount': amount.toStringAsFixed(0),
          'account_number': accountNumber,
          'bank': bank,
          'account_name': accountName,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          // Deduct coins from user's balance
          await databaseService.processWithdrawal(userId, amount.toInt());
          
          // Add transaction record
          await databaseService.addTransaction(
              userId: userId,
              type: 'withdrawal',
              amount: -amount.toInt(), // This is already negative
              description: 'Withdrawal request - ${bank.substring(0, 3)}...${accountNumber.substring(accountNumber.length - 4)}',
            );

          await databaseService.processWithdrawal(userId, amount.toInt());
          
          // Refresh user data
          if (mounted) {
            final userCubit = context.read<UserCubit>();
            userCubit.refreshUserData();
            
            // Update local state
            setState(() {
              _hasPendingWithdrawal = true;
            });
            
            Navigator.pop(context);
            ToastUtils.showSuccess(context, 'Withdrawal request submitted successfully! It will be processed within 2-4 hours.');
          }
        } else {
          ToastUtils.showError(context, data['message'] ?? 'Withdrawal failed');
        }
      } else {
        ToastUtils.showError(context, 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      ToastUtils.showError(context, 'Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  List<String> _getBankList() {
    return [
      'Access Bank',
      'First Bank',
      'Guaranty Trust Bank (GTB)',
      'United Bank for Africa (UBA)',
      'Zenith Bank',
      'Ecobank',
      'Fidelity Bank',
      'Union Bank',
      'Stanbic IBTC Bank',
      'Sterling Bank',
      'Wema Bank',
      'Heritage Bank',
      'Keystone Bank',
      'Polaris Bank',
      'Unity Bank',
      'Jaiz Bank',
      'SunTrust Bank',
      'Providus Bank',
      'Titan Trust Bank',
      'Kuda Bank',
      'Moniepoint',
      'OPay',
      'PalmPay',
    ];
  }

  // ... [Keep all other existing methods unchanged - _buildQuickPurchaseOption, _buildTransactionItem, 
  // _showAddCoinsDialog, _processPayment, _openPaystackPaymentWebView, 
  // _verifyAndUpdatePayment, _processQuickPurchase, _showTransactionHistory]
  // ... [All deposit-related methods remain exactly as they were]

  Widget _buildQuickPurchaseOption(int coins, String price, BuildContext context, String userEmail) {
    return GestureDetector(
      onTap: () => _processQuickPurchase(coins, price, context, userEmail),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryRed.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$coins',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryRed,
              ),
            ),
            const Text(
              'Coins',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
  final type = transaction['type'] as String;
  final amount = transaction['amount'] as int;
  final description = transaction['description'] as String;
  final timestamp = transaction['timestamp'];

  IconData icon;
  Color iconColor;
  String displayAmount;

  switch (type) {
    case 'win':
      icon = Icons.emoji_events;
      iconColor = AppColors.success;
      displayAmount = '+$amount'; // Positive
      break;
    case 'loss':
      icon = Icons.close;
      iconColor = AppColors.error;
      displayAmount = '-${amount.abs()}'; // Negative
      break;
    case 'purchase':
      icon = Icons.shopping_cart;
      iconColor = AppColors.warning;
      displayAmount = '+$amount'; // Positive (deposit)
      break;
    case 'withdrawal':
      icon = Icons.money_off;
      iconColor = AppColors.error;
      displayAmount = '-${amount.abs()}'; // Negative
      break;
    default:
      icon = Icons.account_balance_wallet;
      iconColor = AppColors.primaryRed;
      displayAmount = '$amount';
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: AppColors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        // ... icon container
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timestamp != null
                    ? DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate())
                    : 'N/A',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          displayAmount, // Use displayAmount instead of raw amount
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: type == 'withdrawal' || type == 'loss' 
                ? AppColors.error 
                : AppColors.success,
          ),
        ),
      ],
    ),
  );

  }

  void _showAddCoinsDialog(BuildContext context, String userId, String userEmail) {
    TextEditingController amountController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Coins'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter amount in Naira (minimum ₦100):'),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g., 500',
                    prefixText: '₦',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '1 Naira = 1 Coin\nChoose your payment method on the next screen',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _isProcessing ? null : () async {
                  final amountText = amountController.text.trim();
                  if (amountText.isEmpty) {
                    ToastUtils.showError(context, 'Please enter an amount');
                    return;
                  }
                  
                  final amount = int.tryParse(amountText);
                  if (amount == null || amount < 100) {
                    ToastUtils.showError(context, 'Minimum amount is ₦100');
                    return;
                  }
                  
                  Navigator.pop(context);
                  await _processPayment(context, userId, userEmail, amount);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Proceed to Payment'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processPayment(
    BuildContext context, 
    String userId, 
    String userEmail, 
    int amountInNaira
  ) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final amountInKobo = amountInNaira * 100;
      
      // Initialize Paystack payment
      final result = await paystackService.initializePayment(
        email: userEmail,
        amountInKobo: amountInKobo,
        userId: userId,
      );

      if (result['success'] == true && result['authorizationUrl'] != null) {
        // Open Paystack payment page with WebView
        await _openPaystackPaymentWebView(
          context: context,
          authorizationUrl: result['authorizationUrl']!,
          reference: result['reference']!,
          userId: userId,
          amountInNaira: amountInNaira,
        );
      } else {
        if (!mounted) return;
        ToastUtils.showError(context, 'Failed to initialize payment: ${result['message']}');
      }
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showError(context, 'Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _openPaystackPaymentWebView({
    required BuildContext context,
    required String authorizationUrl,
    required String reference,
    required String userId,
    required int amountInNaira,
  }) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PaystackPaymentScreen(
          authorizationUrl: authorizationUrl,
          reference: reference,
          userId: userId,
          amountInNaira: amountInNaira,
        ),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      // Payment was successful
      await _verifyAndUpdatePayment(userId, reference, amountInNaira);
    } else if (result == false) {
      // Payment was cancelled or failed
      ToastUtils.showInfo(context, 'Payment cancelled');
    }
  }

  // Add this method to add test winnings
Future<void> _addTestWinnings(BuildContext context) async {
  if (userId == null) return;
  
  setState(() {
    _isProcessing = true;
  });
  
  try {
    const testCoins = 5000;
    
    // Update user's coins (this is now the withdrawable amount)
    await FirebaseFirestore.instance
      .collection('users')
      .doc(userId!)
      .update({
        'coins': FieldValue.increment(testCoins),
      });
    
    // Add a "win" transaction
    await databaseService.addTransaction(
      userId: userId!,
      type: 'win',
      amount: testCoins,
      description: 'Test coins added',
    );
    
    // Refresh user data
    final userCubit = context.read<UserCubit>();
    userCubit.refreshUserData();
    
    // Reload withdrawable balance (which is now total balance)
    await _loadWithdrawableBalance();
    
    ToastUtils.showSuccess(context, 'Added $testCoins test coins! You can now test withdrawal.');
  } catch (e) {
    ToastUtils.showError(context, 'Error: $e');
  } finally {
    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}

  Future<void> _verifyAndUpdatePayment(
    String userId, 
    String reference, 
    int amountInNaira
  ) async {
    if (!mounted) return;
    ToastUtils.showInfo(context, 'Verifying payment...');
    
    // Verify the payment with Paystack
    final result = await paystackService.verifyTransaction(reference);

if (result['success'] == true && result['status'] == 'success') {
  // THIS IS WHAT YOU CURRENTLY HAVE:
  final coins = amountInNaira;
  
  // 1. Update coins directly in Firebase
  await FirebaseFirestore.instance
    .collection('users')
    .doc(userId)
    .update({
      'totalCoins': FieldValue.increment(coins),
      'depositCoins': FieldValue.increment(coins),
    });
  
  // 2. Refresh user data in UserCubit
  if (mounted) {
    final userCubit = context.read<UserCubit>();
    userCubit.refreshUserData();
  }
  
  // 3. Add transaction
  await databaseService.addTransaction(
    userId: userId,
    type: 'purchase',
    amount: coins,
    description: 'Coin purchase - Ref: ${reference.substring(0, 8)}...',
  );
}
  }

  Future<void> _processQuickPurchase(
    int coins, 
    String price, 
    BuildContext context, 
    String userEmail
  ) async {
    if (userId == null) return;
    
    final priceText = price.replaceAll('₦', '').replaceAll(',', '');
    final amount = int.tryParse(priceText) ?? 0;
    
    await _processPayment(context, userId!, userEmail, amount);
  }

  void _showTransactionHistory(BuildContext context) {
    ToastUtils.showInfo(context, 'Transaction history screen coming soon.');
  }
}

// Keep the existing PaystackPaymentScreen class exactly as it was
// ... [PaystackPaymentScreen class remains unchanged]

// Enhanced Paystack Payment Screen with proper Android 11+ support
class PaystackPaymentScreen extends StatefulWidget {
  final String authorizationUrl;
  final String reference;
  final String userId;
  final int amountInNaira;

  const PaystackPaymentScreen({
    super.key,
    required this.authorizationUrl,
    required this.reference,
    required this.userId,
    required this.amountInNaira,
  });

  @override
  State<PaystackPaymentScreen> createState() => _PaystackPaymentScreenState();
}

class _PaystackPaymentScreenState extends State<PaystackPaymentScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    // Platform-specific parameters for better Android 11+ support
    late final PlatformWebViewControllerCreationParams params;
    
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _isLoading = progress < 100;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _checkPaymentStatus(url);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _hasError = true;
                _isLoading = false;
              });
            }
            print('WebView error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            _checkPaymentStatus(request.url);
            return NavigationDecision.navigate;
          },
        ),
      );

    // Android-specific configuration for better compatibility
    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async {
            return GeolocationPermissionsResponse(
              allow: true,
              retain: true,
            );
          },
        );
    }

    // Load the payment URL
    _controller.loadRequest(Uri.parse(widget.authorizationUrl));
  }

  void _checkPaymentStatus(String url) {
    print('Current URL: $url');

    // Check for Paystack success/failure patterns
    if (url.contains('checkout.paystack.com/close') || 
        url.contains('standard.paystack.co/close')) {
      // Payment completed (success or failure)
      _handlePaymentComplete();
    } else if (url.contains('trxref=') || url.contains('reference=')) {
      // Transaction reference found - likely successful
      _handlePaymentComplete();
    } else if (url.contains('cancelled=true') || url.contains('cancel')) {
      _handlePaymentCancelled();
    }
  }

  void _handlePaymentComplete() {
    if (!mounted) return;
    // Return true to indicate payment completion
    Navigator.of(context).pop(true);
  }

  void _handlePaymentCancelled() {
    if (!mounted) return;
    // Return false to indicate cancellation
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Confirm if user wants to cancel payment
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel Payment?'),
            content: const Text('Are you sure you want to cancel this payment?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        
        if (shouldPop == true) {
          Navigator.of(context).pop(false);
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete Payment'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final shouldClose = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cancel Payment?'),
                  content: const Text('Are you sure you want to cancel this payment?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Yes'),
                    ),
                  ],
                ),
              );
              
              if (shouldClose == true && mounted) {
                Navigator.of(context).pop(false);
              }
            },
          ),
        ),
        body: Stack(
          children: [
            if (_hasError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load payment page',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _isLoading = true;
                        });
                        _controller.reload();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              WebViewWidget(controller: _controller),
            if (_isLoading && !_hasError)
              Container(
                color: Colors.white,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading payment page...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
