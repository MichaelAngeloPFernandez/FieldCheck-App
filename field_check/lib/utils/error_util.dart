class ErrorUtil {
  static String normalize(Object error) {
    if (error is FormatException) return 'Invalid data format';
    if (error is StateError) return 'Unexpected state encountered';
    // Basic fallback to string; can be expanded to inspect http responses.
    return error.toString();
  }
}