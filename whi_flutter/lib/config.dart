/// API Configuration for Waffle House Index
///
/// Update the CLOUDFRONT_URL after deploying to AWS
class ApiConfig {
  // Set to true to use production AWS API
  static const bool useProduction = false;

  // CloudFront URL from Terraform output (update after deployment)
  // Example: "https://d1234567890.cloudfront.net"
  static const String cloudfrontUrl = "https://YOUR_DISTRIBUTION.cloudfront.net";

  // Local development URLs
  static const String localUrlAndroid = "http://10.0.2.2:8000";
  static const String localUrlDesktop = "http://localhost:8000";
  static const String localUrlIOS = "http://localhost:8000";  // or your computer's IP

  /// Get the appropriate API base URL based on platform and environment
  static String getApiBaseUrl({required bool isAndroid, required bool isIOS, required bool isDesktop}) {
    if (useProduction) {
      return cloudfrontUrl;
    }

    if (isAndroid) {
      return localUrlAndroid;
    } else if (isIOS) {
      return localUrlIOS;
    } else {
      return localUrlDesktop;
    }
  }
}