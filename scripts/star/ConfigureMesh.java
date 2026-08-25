// Simcenter STAR-CCM+ 20.04 batch macro.
//
// Apply an explicit set of meshing parameters before STAR's batch "mesh"
// command is executed. scripts/workflow/run_star_mesh.sh validates and supplies every
// environment variable used here.
package macro;

import star.base.neo.DoubleVector;
import star.common.Coordinate;
import star.common.GeometryPart;
import star.common.LabCoordinateSystem;
import star.common.Simulation;
import star.common.SimulationPartManager;
import star.common.StarMacro;
import star.common.Units;
import star.meshing.AutoMeshOperation;
import star.meshing.BaseSize;
import star.meshing.MaximumCellSize;
import star.meshing.MeshPartFactory;
import star.meshing.MeshOperationManager;
import star.meshing.PartsMinimumSurfaceSize;
import star.meshing.PartsTargetSurfaceSize;
import star.meshing.PartsTetPolyGrowthRate;
import star.meshing.SimpleBlockPart;
import star.meshing.SurfaceCurvature;
import star.meshing.SurfaceCustomMeshControl;
import star.meshing.VolumeControlBase;
import star.meshing.VolumeControlSize;
import star.meshing.VolumeCustomMeshControl;
import star.prismmesher.GenerateStandardPrismaticCells;
import star.prismmesher.NumPrismLayers;
import star.prismmesher.PrismLayerStretching;
import star.prismmesher.PrismThickness;

public class ConfigureMesh extends StarMacro {

  @Override
  public void execute() {
    Simulation simulation = getActiveSimulation();

    String operationName = MacroSupport.requiredString("STAR_MESH_OPERATION");
    String wingControlName = MacroSupport.requiredString("STAR_WING_CONTROL");
    String volumeControlName = MacroSupport.requiredString("STAR_VOLUME_CONTROL");
    String volumePartName = MacroSupport.requiredString("STAR_VOLUME_PART");
    double baseSize = MacroSupport.requiredDouble("STAR_BASE_SIZE_M");
    double surfaceTarget = MacroSupport.requiredDouble("STAR_SURFACE_TARGET_PCT");
    double surfaceMinimum = MacroSupport.requiredDouble("STAR_SURFACE_MIN_PCT");
    double maximumCell = MacroSupport.requiredDouble("STAR_MAX_CELL_PCT");
    double tetGrowth = MacroSupport.requiredDouble("STAR_TET_GROWTH_RATE");
    double wingTarget = MacroSupport.requiredDouble("STAR_WING_TARGET_PCT");
    double wingMinimum = MacroSupport.requiredDouble("STAR_WING_MIN_PCT");
    double wingCurvature = MacroSupport.requiredDouble("STAR_WING_CURVATURE_POINTS");
    double prismHeight = MacroSupport.requiredDouble("STAR_PRISM_HEIGHT_M");
    int prismLayers = MacroSupport.requiredInteger("STAR_PRISM_LAYERS");
    double prismStretching = MacroSupport.requiredDouble("STAR_PRISM_STRETCHING");
    double volumeSize = MacroSupport.requiredDouble("STAR_VOLUME_SIZE_PCT");
    double volumeXMin = MacroSupport.requiredDouble("STAR_VOLUME_X_MIN_M");
    double volumeXMax = MacroSupport.requiredDouble("STAR_VOLUME_X_MAX_M");
    double volumeYMin = MacroSupport.requiredDouble("STAR_VOLUME_Y_MIN_M");
    double volumeYMax = MacroSupport.requiredDouble("STAR_VOLUME_Y_MAX_M");
    double volumeZMin = MacroSupport.requiredDouble("STAR_VOLUME_Z_MIN_M");
    double volumeZMax = MacroSupport.requiredDouble("STAR_VOLUME_Z_MAX_M");

    AutoMeshOperation operation = (AutoMeshOperation) simulation
        .get(MeshOperationManager.class).getObject(operationName);
    if (operation == null) {
      throw new IllegalStateException(
          "Required automated mesh operation does not exist: " + operationName);
    }

    SurfaceCustomMeshControl wingControl = (SurfaceCustomMeshControl) operation
        .getCustomMeshControls().getObject(wingControlName);
    if (wingControl == null) {
      throw new IllegalStateException(
          "Required surface mesh control does not exist: " + wingControlName);
    }

    SimpleBlockPart volumePart = getOrCreateRefinementBlock(
        simulation, volumePartName,
        volumeXMin, volumeXMax,
        volumeYMin, volumeYMax,
        volumeZMin, volumeZMax);

    // In STAR 20.04, getObject(name) reports a server error and aborts the
    // macro when a custom control is absent; it does not safely return null.
    // The refinement control is intentionally optional in a fresh template,
    // so inspect the manager's children before creating it.
    VolumeCustomMeshControl volumeControl = null;
    for (Object control : operation.getCustomMeshControls().getChildren()) {
      if (control instanceof VolumeCustomMeshControl
          && volumeControlName.equals(
              ((VolumeCustomMeshControl) control).getPresentationName())) {
        volumeControl = (VolumeCustomMeshControl) control;
        break;
      }
    }
    if (volumeControl == null) {
      volumeControl = operation.getCustomMeshControls().createVolumeControl();
      volumeControl.setPresentationName(volumeControlName);
    }
    volumeControl.getGeometryObjects().setObjects(volumePart);

    // VolumeControlBase is not present in the condition manager for every
    // valid volume-control state in STAR 20.04.  Calling get(Class) when it is
    // absent prints "Condition not found" and aborts the macro, even though
    // VolumeControlSize is already active and can be changed.  Inspect the
    // existing conditions first and only set the option when STAR exposes it.
    boolean volumeBaseOptionAvailable = false;
    for (Object condition : volumeControl.getCustomConditions().getChildren()) {
      if (condition instanceof VolumeControlBase) {
        ((VolumeControlBase) condition).setVolumeControlBaseSizeOption(true);
        volumeBaseOptionAvailable = true;
        break;
      }
    }
    volumeControl.getCustomValues().get(VolumeControlSize.class)
        .getRelativeSizeScalar().setValue(volumeSize);

    operation.getDefaultValues().get(BaseSize.class).setValue(baseSize);
    operation.getDefaultValues().get(PartsTargetSurfaceSize.class)
        .getRelativeSizeScalar().setValue(surfaceTarget);
    operation.getDefaultValues().get(PartsMinimumSurfaceSize.class)
        .getRelativeSizeScalar().setValue(surfaceMinimum);
    operation.getDefaultValues().get(MaximumCellSize.class)
        .getRelativeSizeScalar().setValue(maximumCell);
    operation.getDefaultValues().get(PartsTetPolyGrowthRate.class)
        .setGrowthRate(tetGrowth);

    wingControl.getCustomValues().get(PartsTargetSurfaceSize.class)
        .getRelativeSizeScalar().setValue(wingTarget);
    wingControl.getCustomValues().get(PartsMinimumSurfaceSize.class)
        .getRelativeSizeScalar().setValue(wingMinimum);
    wingControl.getCustomValues().get(SurfaceCurvature.class)
        .setNumPointsAroundCircle(wingCurvature);

    // Keep the physical macro-layer height independent of the STAR base size.
    // PrismThickness is configured as a relative value in this template, so
    // convert the requested height in metres to STAR's percentage here.
    double prismHeightPercent = 100.0 * prismHeight / baseSize;
    operation.getDefaultValues().get(PrismThickness.class)
        .getRelativeSizeScalar().setValue(prismHeightPercent);
    operation.getDefaultValues().get(NumPrismLayers.class)
        .setNumLayers(prismLayers);
    operation.getDefaultValues().get(PrismLayerStretching.class)
        .setStretching(prismStretching);
    operation.getDefaultValues().get(GenerateStandardPrismaticCells.class)
        .setGenerateStandardPrismaticCells(true);

    simulation.println("STAR_BATCH_MESH_CONFIGURATION");
    simulation.println("  operation                 = " + operationName);
    simulation.println("  base_size_m                = " + baseSize);
    simulation.println("  surface_target_pct         = " + surfaceTarget);
    simulation.println("  surface_min_pct            = " + surfaceMinimum);
    simulation.println("  max_cell_pct               = " + maximumCell);
    simulation.println("  tet_growth_rate            = " + tetGrowth);
    simulation.println("  wing_control               = " + wingControlName);
    simulation.println("  wing_target_pct            = " + wingTarget);
    simulation.println("  wing_min_pct               = " + wingMinimum);
    simulation.println("  wing_curvature_points      = " + wingCurvature);
    simulation.println("  volume_control             = " + volumeControlName);
    simulation.println("  volume_part                = " + volumePartName);
    simulation.println("  volume_base_option_exposed = "
        + volumeBaseOptionAvailable);
    simulation.println("  volume_size_pct            = " + volumeSize);
    simulation.println("  volume_size_m              = "
        + baseSize * volumeSize / 100.0);
    simulation.println("  volume_corner_1_m          = ("
        + volumeXMin + " " + volumeYMin + " " + volumeZMin + ")");
    simulation.println("  volume_corner_2_m          = ("
        + volumeXMax + " " + volumeYMax + " " + volumeZMax + ")");
    simulation.println("  prism_height_m             = " + prismHeight);
    simulation.println("  prism_height_pct           = " + prismHeightPercent);
    simulation.println("  prism_layers               = " + prismLayers);
    simulation.println("  prism_stretching           = " + prismStretching);
    simulation.println("  standard_prismatic_cells   = true");
    simulation.println("STAR_BATCH_MESH_CONFIGURED");
  }

  private SimpleBlockPart getOrCreateRefinementBlock(
      Simulation simulation,
      String partName,
      double xMin, double xMax,
      double yMin, double yMax,
      double zMin, double zMax) {
    SimulationPartManager partManager = simulation.get(SimulationPartManager.class);
    GeometryPart existingPart = null;
    try {
      existingPart = partManager.getPart(partName);
    } catch (RuntimeException ignored) {
      // STAR throws for a missing named part in some releases.
    }

    SimpleBlockPart block;
    if (existingPart == null) {
      block = simulation.get(MeshPartFactory.class).createNewBlockPart(partManager);
      block.setPresentationName(partName);
    } else if (existingPart instanceof SimpleBlockPart) {
      block = (SimpleBlockPart) existingPart;
    } else {
      throw new IllegalStateException(
          "Refinement part exists but is not a block: " + partName
          + " (" + existingPart.getClass().getName() + ")");
    }

    Units metres = (Units) simulation.getUnitsManager().getObject("m");
    if (metres == null) {
      throw new IllegalStateException("STAR length unit 'm' is unavailable");
    }
    LabCoordinateSystem lab = simulation.getCoordinateSystemManager()
        .getLabCoordinateSystem();

    block.setDoNotRetessellate(true);
    block.setCoordinateSystem(lab);
    setCoordinate(block.getCorner1(), lab, metres, xMin, yMin, zMin);
    setCoordinate(block.getCorner2(), lab, metres, xMax, yMax, zMax);
    block.rebuildSimpleShapePart();
    block.setDoNotRetessellate(false);
    return block;
  }

  private void setCoordinate(
      Coordinate coordinate,
      LabCoordinateSystem coordinateSystem,
      Units units,
      double x, double y, double z) {
    coordinate.setCoordinateSystem(coordinateSystem);
    coordinate.setCoordinate(
        units, units, units, new DoubleVector(new double[] {x, y, z}));
  }
}
