import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:ludotitian/screens/store_screen.dart';
import '/constants/colors.dart';
import '/cubits/user/user_cubit.dart';
import '/services/database_service.dart';
import '/services/withdrawal_service.dart';
import '/utils/toast_utils.dart';
import '/models/user_model.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final DatabaseService databaseService = DatabaseService();
  final WithdrawalService withdrawalService = WithdrawalService();
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  
  // Withdrawal variables
  List<Map<String, dynamic>> banks = [];
  Map<String, dynamic>? selectedBank;
  TextEditingController amountController = TextEditingController();
  TextEditingController accountNumberController = TextEditingController();
  TextEditingController accountNameController = TextEditingController();
  bool isVerifyingAccount = false;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  // Load banks from Paystack
  Future<void> _loadBanks() async {
    final loadedBanks = await withdrawalService.getBanks();
    setState(() {
      banks = loadedBanks;
    });
  }

  // Sync user to MySQL database
  Future<void> _syncUserToMySQL(UserModel user) async {
    try {
      final response = await http.post(
        Uri.parse('https://dynamic360tech.name.ng/ludo/sync_user.php'), // UPDATE THIS URL
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': user.id,
          'coins': user.coins,
          'display_name': user.displayName ?? '',
        }),
      );
      
      final data = json.decode(response.body);
      if (!data['success']) {
        print('⚠️ User sync warning: ${data['message']}');
      }
    } catch (e) {
      print('⚠️ User sync error: $e');
    }
  }

  // Verify account number
  Future<void> _verifyAccountNumber() async {
    if (selectedBank == null || accountNumberController.text.isEmpty) {
      ToastUtils.showError(context, 'Please select bank and enter account number');
      return;
    }

    setState(() {
      isVerifyingAccount = true;
      accountNameController.clear();
    });

    final result = await withdrawalService.verifyAccountNumber(
      accountNumberController.text,
      selectedBank!['code'].toString(),
    );

    setState(() {
      isVerifyingAccount = false;
    });

    if (result['success'] == true) {
      setState(() {
        accountNameController.text = result['accountName'];
      });
      ToastUtils.showSuccess(context, 'Account verified successfully');
    } else {
      ToastUtils.showError(context, result['message'] ?? 'Verification failed');
    }
  }

  // Show withdrawal dialog
  Future<void> _showWithdrawalDialog(BuildContext context, UserModel user) async {
    // Sync user to MySQL first
    await _syncUserToMySQL(user);
    
    // Reset controllers
    amountController.clear();
    accountNumberController.clear();
    accountNameController.clear();
    selectedBank = null;

    // Get eligible balance
    final balanceResult = await withdrawalService.getEligibleBalance(user.id);
    
    if (!balanceResult['success']) {
      ToastUtils.showError(context, balanceResult['message']);
      return;
    }
    
    final eligibleAmount = balanceResult['eligibleAmount'] as double;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text(
              'Withdraw Funds',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
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
                          'Available Balance:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${user.coins} coins',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Eligible for Withdrawal:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${eligibleAmount.toStringAsFixed(2)} units',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // Amount
                  TextFormField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Amount to Withdraw',
                      hintText: 'Minimum 10 units',
                      prefixText: '₦ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      final amount = double.tryParse(value) ?? 0;
                      if (amount > eligibleAmount) {
                        amountController.text = eligibleAmount.toStringAsFixed(2);
                        ToastUtils.showWarning(context, 'Cannot exceed eligible balance');
                      }
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Bank Selection
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedBank,
                    decoration: InputDecoration(
                      labelText: 'Select Bank',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: banks.map((bank) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: bank,
                        child: Text('${bank['name']}'),
                      );
                    }).toList(),
                    onChanged: (bank) {
                      setState(() {
                        selectedBank = bank;
                        accountNameController.clear();
                      });
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Account Number
                  TextFormField(
                    controller: accountNumberController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Account Number',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: isVerifyingAccount
                          ? const CircularProgressIndicator()
                          : IconButton(
                              icon: const Icon(Icons.verified_user),
                              onPressed: _verifyAccountNumber,
                            ),
                    ),
                    onChanged: (value) {
                      if (value.length == 10) {
                        _verifyAccountNumber();
                      }
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Account Name
                  TextFormField(
                    controller: accountNameController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Account Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Conversion Info
                  Text(
                    'Note: 100 coins = 1 unit • Processing may take 24 hours',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isProcessing
                    ? null
                    : () async {
                        final amount = double.tryParse(amountController.text) ?? 0;
                        
                        // Validate
                        if (amount < 10) {
                          ToastUtils.showError(context, 'Minimum withdrawal is 10 units');
                          return;
                        }
                        
                        if (amount > eligibleAmount) {
                          ToastUtils.showError(context, 'Amount exceeds eligible balance');
                          return;
                        }
                        
                        if (selectedBank == null) {
                          ToastUtils.showError(context, 'Please select a bank');
                          return;
                        }
                        
                        if (accountNumberController.text.isEmpty) {
                          ToastUtils.showError(context, 'Please enter account number');
                          return;
                        }
                        
                        if (accountNameController.text.isEmpty) {
                          ToastUtils.showError(context, 'Please verify account number');
                          return;
                        }
                        
                        setState(() {
                          isProcessing = true;
                        });
                        
                        // Process withdrawal
                        final result = await withdrawalService.processWithdrawal(
                          userId: user.id,
                          amount: amount,
                          bankCode: selectedBank!['code'].toString(),
                          accountNumber: accountNumberController.text,
                          accountName: accountNameController.text,
                        );
                        
                        setState(() {
                          isProcessing = false;
                        });
                        
                        if (result['success'] == true) {
                          ToastUtils.showSuccess(context, 'Withdrawal initiated successfully!');
                          Navigator.pop(context);
                          
                          // Refresh user data
                          context.read<UserCubit>().refreshUserData();
                        } else {
                          ToastUtils.showError(context, result['message']);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: AppColors.white,
                ),
                child: isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('Withdraw'),
              ),
            ],
          );
        },
      ),
    );
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Balance Card
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
                            'Current Balance',
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
                        user.coins.toStringAsFixed(0),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            '****  ****  ****  ',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 18,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            user.id.substring(0, 4),
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 18,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _showAddCoinsDialog(context, userId!);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
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
                        onPressed: () {
                          _showWithdrawalDialog(context, user);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPink,
                          foregroundColor: AppColors.primaryRed,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
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

                // View Transactions Button
                OutlinedButton(
                  onPressed: () {
                    // Handle view transactions
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

                // Transaction List
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: databaseService.getUserTransactions(userId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
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

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final type = transaction['type'] as String;
    final amount = transaction['amount'] as int;
    final description = transaction['description'] as String;
    final timestamp = transaction['timestamp'];

    IconData icon;
    Color iconColor;

    switch (type) {
      case 'win':
        icon = Icons.emoji_events;
        iconColor = AppColors.success;
        break;
      case 'loss':
        icon = Icons.close;
        iconColor = AppColors.error;
        break;
      case 'purchase':
        icon = Icons.shopping_cart;
        iconColor = AppColors.warning;
        break;
      default:
        icon = Icons.account_balance_wallet;
        iconColor = AppColors.primaryRed;
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
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
                      ? DateFormat('MMM dd, yyyy').format(timestamp.toDate())
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
            '${amount >= 0 ? '+' : ''}$amount',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: amount >= 0 ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCoinsDialog(BuildContext context, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Coins'),
        content: const Text('Buy More Coins'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StoreScreen()),
              );
            },
            child: const Text('Simulate Add 100'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}