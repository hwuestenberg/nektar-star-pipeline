// Simcenter STAR-CCM+ 20.04 batch macro.
//
// The CCM export calls were recorded with STAR-CCM+ 20.04.007-R8. Paths are
// supplied by scripts/workflow/run_star_mesh.sh so this file contains no host-specific
// directory names.
package macro;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;

import star.base.neo.ClientServerObject;
import star.base.neo.NeoProperty;
import star.common.Boundary;
import star.common.FieldFunction;
import star.common.ImportManager;
import star.common.Part;
import star.common.PartSurface;
import star.common.Region;
import star.common.Simulation;
import star.common.SolutionExportFormat;
import star.common.StarMacro;

public class ExportCcm extends StarMacro {

  private static final String REGION_NAME = "Fluid";
  private static final String CCM_ENV = "STAR_CCM_OUTPUT";
  private static final String SIM_ENV = "STAR_SIM_OUTPUT";

  @Override
  public void execute() {
    Simulation simulation = getActiveSimulation();
    String ccmPath = requiredAbsolutePath(CCM_ENV);
    String simPath = requiredAbsolutePath(SIM_ENV);

    Region region = simulation.getRegionManager().getRegion(REGION_NAME);
    if (region == null) {
      throw new IllegalStateException(
          "Required STAR region does not exist: " + REGION_NAME);
    }

    simulation.println("STAR batch export region : " + REGION_NAME);
    simulation.println("STAR batch output SIM    : " + simPath);
    simulation.println("STAR batch output CCM    : " + ccmPath);

    // Preserve the generated mesh even if the subsequent external export
    // fails. The shell wrapper stages this file before publishing it.
    simulation.saveState(resolvePath(simPath));

    ImportManager importManager = simulation.getImportManager();
    importManager.setExportPath(ccmPath);
    importManager.setFormatType(SolutionExportFormat.Type.CCM);
    importManager.setExportParts(
        new ArrayList<>(Collections.<ClientServerObject>emptyList()));
    importManager.setExportPartSurfaces(
        new ArrayList<>(Collections.<ClientServerObject>emptyList()));
    importManager.setExportBoundaries(
        new ArrayList<>(Collections.<ClientServerObject>emptyList()));
    importManager.setExportRegions(
        new ArrayList<>(Arrays.<ClientServerObject>asList(region)));
    importManager.setExportScalars(
        new ArrayList<>(Collections.<ClientServerObject>emptyList()));
    importManager.setExportVectors(
        new ArrayList<>(Collections.<ClientServerObject>emptyList()));
    importManager.setExportOptionAppendToFile(false);
    importManager.setExportOptionDataAtVerts(false);
    importManager.setExportOptionSolutionOnly(false);

    importManager.export(
        resolvePath(ccmPath),
        new ArrayList<>(Arrays.<Region>asList(region)),
        new ArrayList<>(Collections.<Boundary>emptyList()),
        new ArrayList<>(Collections.<Part>emptyList()),
        new ArrayList<>(Collections.<PartSurface>emptyList()),
        new ArrayList<>(Collections.<FieldFunction>emptyList()),
        NeoProperty.fromString(
            "{'exportFormatType': 0, 'appendToFile': false, "
                + "'solutionOnly': false, 'dataAtVerts': false}"));

    File ccmFile = new File(ccmPath);
    if (!ccmFile.isFile() || ccmFile.length() == 0L) {
      throw new IllegalStateException(
          "STAR reported completion but did not create a non-empty CCM file: "
              + ccmPath);
    }

    simulation.println("STAR batch CCM bytes     : " + ccmFile.length());
    simulation.println("STAR_BATCH_EXPORT_COMPLETE");
  }

  private String requiredAbsolutePath(String environmentName) {
    String value = System.getenv(environmentName);
    if (value == null || value.trim().isEmpty()) {
      throw new IllegalArgumentException(
          "Required environment variable is not set: " + environmentName);
    }

    File file = new File(value).getAbsoluteFile();
    if (!file.isAbsolute()) {
      throw new IllegalArgumentException(
          environmentName + " must resolve to an absolute path: " + value);
    }

    File parent = file.getParentFile();
    if (parent == null || !parent.isDirectory()) {
      throw new IllegalArgumentException(
          "Output parent directory does not exist for "
              + environmentName + ": " + value);
    }
    return file.getPath();
  }
}
