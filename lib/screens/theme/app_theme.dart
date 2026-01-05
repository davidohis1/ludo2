import 'package:flutter/material.dart';

// --- Colors ---
const Color kPrimaryColor = Color(0xFFF04B4B); // Bright Red
const Color kSecondaryColor = Color(0xFF1E1E1E); // Dark Background (Leaderboard)
const Color kBackgroundColor = Color(0xFFF7F7F7); // Light Background
const Color kWhiteColor = Colors.white;
const Color kBlackColor = Colors.black;
const Color kCardColor = Color(0xFFFFFFFF);

// --- Text Styles ---
const kHeadingStyle = TextStyle(
  fontSize: 24.0,
  fontWeight: FontWeight.bold,
  color: kBlackColor,
);

const kSubHeadingStyle = TextStyle(
  fontSize: 18.0,
  fontWeight: FontWeight.w600,
  color: kBlackColor,
);

const kBodyTextStyle = TextStyle(
  fontSize: 14.0,
  color: kBlackColor,
);

// --- Theme Data ---
final kAppTheme = ThemeData(
  primaryColor: kPrimaryColor,
  scaffoldBackgroundColor: kBackgroundColor,
  appBarTheme: AppBarTheme(
    backgroundColor: kBackgroundColor,
    foregroundColor: kBlackColor,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: kHeadingStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: kCardColor,
    selectedItemColor: kPrimaryColor,
    unselectedItemColor: Colors.grey,
    elevation: 8,
    type: BottomNavigationBarType.fixed,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimaryColor,
      foregroundColor: kWhiteColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      minimumSize: const Size(double.infinity, 56),
      textStyle: kSubHeadingStyle.copyWith(color: kWhiteColor),
      elevation: 4,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kCardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.0),
      borderSide: BorderSide.none,
    ),
    hintStyle: kBodyTextStyle.copyWith(color: Colors.grey),
  ),
  useMaterial3: true,
);

// --- Utility Widgets (For UI consistency) ---

// A common button used for social logins (White, Black, Blue)
// NOTE: This version is the original, but the functionally updated version
// is used in sign_in_screen.dart for logic. We keep this version minimal
// in the theme file to avoid circular dependencies if it were imported elsewhere.
Widget buildSocialButton({
  required String text,
  required Color color,
  required Color textColor,
  required IconData icon,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8.0),
    child: ElevatedButton(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        minimumSize: const Size(double.infinity, 56),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    ),
  );
}