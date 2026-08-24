// Simcenter STAR-CCM+ 20.04 batch macro.
//
// Print coordinate bounds for every region boundary. This is intentionally
// read-only and is useful for checking that generic CAD faces received the
// expected physical names before boundary conditions are assigned.
package macro;

import java.util.Collections;

import star.base.report.MaxReport;
import star.base.report.MinReport;
import star.common.Boundary;
import star.common.FieldFunction;
import star.common.Region;
import star.common.Simulation;
import star.common.StarMacro;

public class InspectBoundaryGeometry extends StarMacro {

  @Override
  public void execute() {
    Simulation simulation = getActiveSimulation();
    FieldFunction position = simulation.getFieldFunctionManager()
        .getFunction("Position");
    if (position == null) {
      throw new IllegalStateException("STAR Position field function is unavailable");
    }

    MinReport minimum = simulation.getReportManager().createReport(MinReport.class);
    MaxReport maximum = simulation.getReportManager().createReport(MaxReport.class);

    simulation.println("STAR_BOUNDARY_GEOMETRY");
    for (Region region : simulation.getRegionManager().getRegions()) {
      for (Boundary boundary : region.getBoundaryManager().getBoundaries()) {
        double[] low = new double[3];
        double[] high = new double[3];
        minimum.getParts().setObjects(Collections.singletonList(boundary));
        maximum.getParts().setObjects(Collections.singletonList(boundary));
        for (int component = 0; component < 3; ++component) {
          FieldFunction coordinate = position.getComponentFunction(component);
          minimum.setFieldFunction(coordinate);
          maximum.setFieldFunction(coordinate);
          low[component] = minimum.getValue();
          high[component] = maximum.getValue();
        }
        simulation.println(String.format(
            "  %-20s bbox=(%.9g %.9g %.9g) -> (%.9g %.9g %.9g)",
            boundary.getPresentationName(),
            low[0], low[1], low[2], high[0], high[1], high[2]));
      }
    }
    simulation.getReportManager().removeObjects(minimum, maximum);
    simulation.println("STAR_BOUNDARY_GEOMETRY_COMPLETE");
  }
}
