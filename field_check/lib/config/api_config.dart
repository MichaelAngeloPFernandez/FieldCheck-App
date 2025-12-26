class ApiConfig {
  // Cloud backend URL (Render deployment)
  // Note: Render free tier spins down after 15 min of inactivity
  // First request may take 30-60 seconds to warm up
  static const String baseUrl = 'https://fieldcheck-backend.onrender.com';
}
