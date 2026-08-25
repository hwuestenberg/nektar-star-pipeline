// Simcenter STAR-CCM+ 20.04 batch macro support.
//
// Shared environment-variable reading helpers used by multiple macros in
// this directory. STAR-CCM+ compiles every .java file in a macro's
// directory together when a macro from that directory is run via -batch,
// so this plain utility class (not a StarMacro) is picked up automatically
// by BootstrapCase.java, ConfigureMesh.java, ConfigureRans.java and
// ExportRansTable.java without any change to how run_star_*.sh invoke
// -batch.
//
// optionalBoolean and requiredAbsolutePath are deliberately NOT
// centralized here even though similarly-named helpers exist in more than
// one macro: BootstrapCase's and ExportRansTable's optionalBoolean accept
// different input formats (BootstrapCase also accepts "1"/"0" and compares
// the untrimmed value against "true"/"false"), and ExportCcm's and
// ExportRansTable's requiredAbsolutePath differ in an extra isAbsolute()
// check. Forcing those into one shared implementation would be a behavior
// change in at least one macro, which cannot be verified without a
// STAR-CCM+ SDK to compile against, so each macro keeps its own copy.
package macro;

public final class MacroSupport {

  private MacroSupport() {
  }

  public static String requiredString(String name) {
    String value = System.getenv(name);
    if (value == null || value.trim().isEmpty()) {
      throw new IllegalArgumentException(
          "Required environment variable is not set: " + name);
    }
    return value.trim();
  }

  public static String optionalString(String name, String fallback) {
    String value = System.getenv(name);
    return value == null || value.trim().isEmpty() ? fallback : value.trim();
  }

  public static double requiredDouble(String name) {
    String value = requiredString(name);
    try {
      return Double.parseDouble(value);
    } catch (NumberFormatException error) {
      throw new IllegalArgumentException(
          "Environment variable is not a number: " + name + "=" + value,
          error);
    }
  }

  public static double optionalDouble(String name, double fallback) {
    String value = System.getenv(name);
    if (value == null || value.trim().isEmpty()) {
      return fallback;
    }
    try {
      return Double.parseDouble(value.trim());
    } catch (NumberFormatException error) {
      throw new IllegalArgumentException(
          "Environment variable must be numeric: " + name + "=" + value,
          error);
    }
  }

  public static int requiredInteger(String name) {
    String value = requiredString(name);
    try {
      return Integer.parseInt(value);
    } catch (NumberFormatException error) {
      throw new IllegalArgumentException(
          "Environment variable is not an integer: " + name + "=" + value,
          error);
    }
  }
}
