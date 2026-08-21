// Simcenter STAR-CCM+ 20.04 batch macro.
//
// Save the converged simulation and export cell-centred x,y,z,u,v,w,p data.
// scripts/nektar/normalize_star_rans_csv.py converts STAR's version-dependent column
// labels into the CSV convention accepted by Nektar++ FieldConvert.
package macro;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;

import star.common.FieldFunction;
import star.common.FieldFunctionManager;
import star.common.Region;
import star.common.Simulation;
import star.common.SolverStoppingCriterion;
import star.common.StarMacro;
import star.common.XyzInternalTable;

public class ExportRansTable extends StarMacro {

  @Override
  public void execute() {
    Simulation simulation = getActiveSimulation();
    String regionName = requiredString("STAR_RANS_REGION");
    String simPath = requiredAbsolutePath("STAR_RANS_SIM_OUTPUT");
    String tablePath = requiredAbsolutePath("STAR_RANS_TABLE_OUTPUT");

    Region region = simulation.getRegionManager().getRegion(regionName);
    if (region == null) {
      throw new IllegalStateException("Required region does not exist: " + regionName);
    }

    FieldFunctionManager functions = simulation.getFieldFunctionManager();
    FieldFunction velocityFunction = functions.getFunction("Velocity");
    if (velocityFunction == null) {
      throw new IllegalStateException(
          "STAR field function 'Velocity' is unavailable");
    }
    FieldFunction pressure = functions.getFunction("Pressure");
    if (pressure == null) {
      throw new IllegalStateException("STAR field function 'Pressure' is unavailable");
    }

    XyzInternalTable table = simulation.getTableManager()
        .createTable(XyzInternalTable.class);
    table.setPresentationName("Nektar RANS initial-condition samples");
    table.getParts().setObjects(region);
    table.setFieldFunctions(new ArrayList<>(Arrays.asList(
        velocityFunction.getComponentFunction(0),
        velocityFunction.getComponentFunction(1),
        velocityFunction.getComponentFunction(2),
        pressure)));
    table.extract();
    table.export(resolvePath(tablePath), ",");

    simulation.saveState(resolvePath(simPath));

    simulation.println("STAR batch final iteration : "
        + simulation.getSimulationIterator().getCurrentIteration());
    int residualCriteria = 0;
    boolean residualsConverged = true;
    for (SolverStoppingCriterion criterion
        : simulation.getSolverStoppingCriterionManager().getObjects()) {
      if (criterion.getIsUsed()) {
        simulation.println("STAR stopping criterion    : "
            + criterion.getPresentationName()
            + ", satisfied=" + criterion.getIsSatisfied()
            + ", logic="
            + criterion.getLogicalOption().getSelectedElement());
        if (criterion.getPresentationName().startsWith("RANS Residual ")) {
          residualCriteria++;
          residualsConverged = residualsConverged
              && criterion.getIsSatisfied();
        }
      }
    }
    residualsConverged = residualCriteria > 0 && residualsConverged;
    simulation.println("STAR residual criteria count: " + residualCriteria);
    simulation.println("STAR_BATCH_RANS_RESIDUAL_CONVERGED="
        + residualsConverged);

    File tableFile = new File(tablePath);
    if (!tableFile.isFile() || tableFile.length() == 0L) {
      throw new IllegalStateException(
          "STAR did not create a non-empty RANS table: " + tablePath);
    }
    File simFile = new File(simPath);
    if (!simFile.isFile() || simFile.length() == 0L) {
      throw new IllegalStateException(
          "STAR did not save a non-empty RANS simulation: " + simPath);
    }

    simulation.println("STAR batch RANS SIM      : " + simPath);
    simulation.println("STAR batch RANS table    : " + tablePath);
    simulation.println("STAR batch table bytes   : " + tableFile.length());
    simulation.println("STAR_BATCH_RANS_EXPORT_COMPLETE");
  }

  private String requiredString(String environmentName) {
    String value = System.getenv(environmentName);
    if (value == null || value.trim().isEmpty()) {
      throw new IllegalArgumentException(
          "Required environment variable is not set: " + environmentName);
    }
    return value.trim();
  }

  private String requiredAbsolutePath(String environmentName) {
    File file = new File(requiredString(environmentName)).getAbsoluteFile();
    File parent = file.getParentFile();
    if (parent == null || !parent.isDirectory()) {
      throw new IllegalArgumentException(
          "Output parent directory does not exist for "
          + environmentName + ": " + file);
    }
    return file.getPath();
  }
}
