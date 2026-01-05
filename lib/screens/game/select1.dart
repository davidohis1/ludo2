import 'package:flutter/material.dart';
import '/screens/theme/app_theme.dart';

class SelectTierScreen extends StatelessWidget {
  const SelectTierScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Select Tier'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildTierCard(
              context,
              tier: 'Bronze',
              entryFee: '100 Coins',
              prizePool: '500',
              players: '25',
              icon: Icons.brightness_1,
              iconColor: Colors.brown.shade400,
            ),
            _buildTierCard(
              context,
              tier: 'Silver',
              entryFee: '500 Coins',
              prizePool: '2,500',
              players: '15',
              icon: Icons.brightness_1,
              iconColor: Colors.grey.shade400,
            ),
            _buildTierCard(
              context,
              tier: 'Gold',
              entryFee: '1,000 Coins',
              prizePool: '5,000',
              players: '5',
              icon: Icons.brightness_1,
              iconColor: Colors.amber.shade700,
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard(
    BuildContext context, {
    required String tier,
    required String entryFee,
    required String prizePool,
    required String players,
    required IconData icon,
    required Color iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: kCardColor,
          borderRadius: BorderRadius.circular(15.0),
          boxShadow: [
            BoxShadow(
              color: iconColor.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Placeholder for Chess Piece Image
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 40),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tier, style: kSubHeadingStyle.copyWith(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text('Entry: $entryFee', style: kBodyTextStyle.copyWith(color: kPrimaryColor, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Prize Pool: $prizePool', style: kBodyTextStyle),
                          Text('Players: $players', style: kBodyTextStyle),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/game');
              },
              child: const Text('Join Match'),
            ),
          ],
        ),
      ),
    );
  }
}