/// App-wide constants for RetailLite retail billing app
library;

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'RetailLite';
  static const String defaultShopName = 'My Shop';
  static const String appTagline = 'ÃƒÂ Ã‚Â¤Ã‚Â­ÃƒÂ Ã‚Â¤Ã‚Â¾ÃƒÂ Ã‚Â¤Ã‚Â°ÃƒÂ Ã‚Â¤Ã‚Â¤ ÃƒÂ Ã‚Â¤Ã¢â‚¬Â¢ÃƒÂ Ã‚Â¤Ã‚Â¾ ÃƒÂ Ã‚Â¤Ã‚Â¸ÃƒÂ Ã‚Â¤Ã‚Â¬ÃƒÂ Ã‚Â¤Ã‚Â¸ÃƒÂ Ã‚Â¥Ã¢â‚¬Â¡ ÃƒÂ Ã‚Â¤Ã¢â‚¬Â ÃƒÂ Ã‚Â¤Ã‚Â¸ÃƒÂ Ã‚Â¤Ã‚Â¾ÃƒÂ Ã‚Â¤Ã‚Â¨ ÃƒÂ Ã‚Â¤Ã‚Â¬ÃƒÂ Ã‚Â¤Ã‚Â¿ÃƒÂ Ã‚Â¤Ã‚Â²ÃƒÂ Ã‚Â¤Ã‚Â¿ÃƒÂ Ã‚Â¤Ã¢â‚¬Å¡ÃƒÂ Ã‚Â¤Ã¢â‚¬â€ ÃƒÂ Ã‚Â¤Ã‚ÂÃƒÂ Ã‚Â¤Ã‚Âª';
  static const String version = '10.0.3';

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ FREE Tier Limits (enforced via UserSubscription.billsLimit / productsLimit) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  static const int freeMaxBillsPerMonth = 50; // 50 bills / month
  static const int freeMaxProducts = 100; // 100 products
  static const int freeMaxCustomers = 10; // 10 customers

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ PRO Tier Limits ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  static const int proMaxBillsPerMonth = 500;
  static const int proMaxProducts = 999999; // unlimited
  static const int proMaxCustomers = 999999; // unlimited
  static const int proPriceInrMonthly = 299;
  static const int proPriceInrAnnual = 2390; // ~20% off

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ BUSINESS Tier Limits ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  static const int businessMaxBillsPerMonth = 999999; // unlimited
  static const int businessMaxProducts = 999999; // unlimited
  static const int businessMaxCustomers = 999999; // unlimited
  static const int businessPriceInrMonthly = 999;
  static const int businessPriceInrAnnual = 7990; // ~20% off

  // OTP Settings
  static const int otpLength = 4;
  static const int otpResendSeconds = 30;
  static const int otpTimeoutSeconds = 60;

  // Bill Settings
  static const String currencySymbol = 'ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¹';
  static const String countryCode = '+91';

  // Date Formats
  static const String dateFormatDisplay = 'd MMM yyyy';
  static const String dateFormatStorage = 'yyyy-MM-dd';
  static const String timeFormat = 'h:mm a';

  // Animation Durations
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);

  // Firestore Query Limits
  static const int queryLimitBills = 100;
  static const int queryLimitExpenses = 100;
  static const int queryLimitProducts = 100;
  static const int queryLimitCustomers = 100;
  static const int queryLimitTransactions = 100;
  static const int queryLimitNotifications = 50;
  static const int queryLimitAdminAnalytics = 200;
}
