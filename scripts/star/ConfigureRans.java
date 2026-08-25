// Simcenter STAR-CCM+ 20.04 batch macro.
//
// Create (or reuse) a steady, constant-density SST k-omega continuum and
// apply explicit external-aerodynamics boundary/initial conditions. The shell
// driver validates and supplies every environment variable used here.
package macro;

import java.io.File;
import java.util.Arrays;
import java.util.List;
import java.util.Vector;

import star.base.report.MaxReport;
import star.base.report.MonitorManager;
import star.base.report.MinReport;
import star.common.Boundary;
import star.common.BoundaryInterface;
import star.common.ConstantScalarProfileMethod;
import star.common.ConstantVectorProfileMethod;
import star.common.FieldFunction;
import star.common.InletBoundary;
import star.common.MonitorIterationStoppingCriterion;
import star.common.MonitorIterationStoppingCriterionMaxLimitType;
import star.common.MonitorIterationStoppingCriterionMinLimitType;
import star.common.MonitorIterationStoppingCriterionOption;
import star.common.PhysicsContinuum;
import star.common.PressureBoundary;
import star.common.Region;
import star.common.ResidualMonitor;
import star.common.Simulation;
import star.common.SolverStoppingCriterion;
import star.common.SolverStoppingCriterionLogicalOption;
import star.common.SolverStoppingCriterionManager;
import star.common.StarMacro;
import star.common.SteadyModel;
import star.common.StepStoppingCriterion;
import star.common.SymmetryBoundary;
import star.common.WallBoundary;
import star.flow.ConstantDensityModel;
import star.flow.ConstantDensityProperty;
import star.flow.DynamicViscosityProperty;
import star.flow.InletVelocityOption;
import star.flow.StaticPressureProfile;
import star.flow.VelocityProfile;
import star.kwturb.KwAllYplusWallTreatment;
import star.kwturb.KOmegaTurbulence;
import star.kwturb.KwTurbSpecOption;
import star.kwturb.SstKwTurbModel;
import star.material.ConstantMaterialPropertyMethod;
import star.material.Gas;
import star.material.SingleComponentGasModel;
import star.metrics.ThreeDimensionalModel;
import star.segregatedflow.SegregatedFlowModel;
import star.turbulence.RansTurbulenceModel;
import star.turbulence.TurbulenceIntensityProfile;
import star.turbulence.TurbulentModel;
import star.turbulence.TurbulentViscosityRatioProfile;

public class ConfigureRans extends StarMacro {

  @Override
  public void execute() {
    Simulation simulation = getActiveSimulation();

    String regionName = requiredString("STAR_RANS_REGION");
    String continuumName = requiredString("STAR_RANS_CONTINUUM");
    String wingName = requiredString("STAR_RANS_WING_BOUNDARY");
    String upstreamName = requiredString("STAR_RANS_UPSTREAM_BOUNDARY");
    String downstreamName = requiredString("STAR_RANS_DOWNSTREAM_BOUNDARY");
    String topName = requiredString("STAR_RANS_TOP_BOUNDARY");
    String bottomName = requiredString("STAR_RANS_BOTTOM_BOUNDARY");
    String spanMinName = requiredString("STAR_RANS_SPAN_MIN_BOUNDARY");
    String spanMaxName = requiredString("STAR_RANS_SPAN_MAX_BOUNDARY");
    String spanMode = requiredString("STAR_RANS_SPAN_MODE");
    String periodicInterfaceName = requiredString("STAR_RANS_PERIODIC_INTERFACE");
    String simulationOutput = requiredString("STAR_RANS_SIM_OUTPUT");

    double reynolds = requiredDouble("STAR_RANS_REYNOLDS");
    double angleDegrees = requiredDouble("STAR_RANS_ANGLE_DEG");
    // STAR still attaches SI units to these quantities, but their numerical
    // values implement the same nondimensional convention used by Nektar++.
    // With chord=1, fixing U=1 and rho=1 leaves mu=nu=1/Re.
    double velocity = 1.0;
    double density = 1.0;
    double viscosity = 1.0 / reynolds;
    double pressure = requiredDouble("STAR_RANS_REFERENCE_PRESSURE");
    double intensity = requiredDouble("STAR_RANS_TURB_INTENSITY");
    double viscosityRatio = requiredDouble("STAR_RANS_TURB_VISC_RATIO");
    int maximumSteps = requiredInteger("STAR_RANS_MAX_STEPS");
    int minimumSteps = requiredInteger("STAR_RANS_MIN_STEPS");
    double residualTolerance = requiredDouble("STAR_RANS_RESIDUAL_TOL");

    if (reynolds <= 0.0 || viscosity <= 0.0 || !Double.isFinite(viscosity)
        || intensity <= 0.0 || viscosityRatio <= 0.0 || maximumSteps <= 0
        || minimumSteps < 0 || residualTolerance <= 0.0) {
      throw new IllegalArgumentException(
          "Reynolds number, maximum steps and residual tolerance must be "
          + "positive; minimum steps must be non-negative");
    }

    Region region = simulation.getRegionManager().getRegion(regionName);
    if (region == null) {
      throw new IllegalStateException("Required region does not exist: " + regionName);
    }

    PhysicsContinuum continuum = findContinuum(simulation, continuumName);
    if (continuum == null) {
      continuum = simulation.getContinuumManager()
          .createContinuum(PhysicsContinuum.class);
      continuum.setPresentationName(continuumName);
    }

    // Calling enable on an already-enabled model is harmless. Keeping the
    // model list here makes a mesh-only template sufficient for a batch run.
    continuum.enable(ThreeDimensionalModel.class);
    continuum.enable(SteadyModel.class);
    continuum.enable(SingleComponentGasModel.class);
    continuum.enable(SegregatedFlowModel.class);
    continuum.enable(ConstantDensityModel.class);
    continuum.enable(TurbulentModel.class);
    continuum.enable(RansTurbulenceModel.class);

    // STAR 20.04/2506 requires the selectable k-omega model-family marker
    // before a concrete k-omega closure can be registered.  KwTurbModel is a
    // common implementation base, not the family-selection model in this
    // release; enabling it directly produces "no registration found".
    continuum.enable(KOmegaTurbulence.class);
    continuum.enable(SstKwTurbModel.class);
    continuum.enable(KwAllYplusWallTreatment.class);
    region.setContinuum(continuum);

    SingleComponentGasModel materialModel = continuum.getModelManager()
        .getModel(SingleComponentGasModel.class);
    Gas gas = (Gas) materialModel.getMaterial();
    ConstantMaterialPropertyMethod densityMethod =
        (ConstantMaterialPropertyMethod) gas.getMaterialProperties()
            .getMaterialProperty(ConstantDensityProperty.class).getMethod();
    densityMethod.getQuantity().setValue(density);
    ConstantMaterialPropertyMethod viscosityMethod =
        (ConstantMaterialPropertyMethod) gas.getMaterialProperties()
            .getMaterialProperty(DynamicViscosityProperty.class).getMethod();
    viscosityMethod.getQuantity().setValue(viscosity);

    double angleRadians = Math.toRadians(angleDegrees);
    double ux = velocity * Math.cos(angleRadians);
    double uy = velocity * Math.sin(angleRadians);
    double uz = 0.0;

    VelocityProfile initialVelocity = continuum.getInitialConditions()
        .get(VelocityProfile.class);
    initialVelocity.getMethod(ConstantVectorProfileMethod.class).getQuantity()
        .setComponents(ux, uy, uz);

    // Use the same turbulence specification for the volume initialization as
    // for the inlets. In STAR 20.04, TKE and omega profiles do not exist in
    // the initial-condition manager until its KwTurbSpecOption is explicitly
    // switched to K+Omega. The selectable representation used here is
    // intensity + turbulent-viscosity ratio.
    continuum.getInitialConditions().get(KwTurbSpecOption.class)
        .setSelected(KwTurbSpecOption.Type.INTENSITY_VISCOSITY_RATIO);
    TurbulenceIntensityProfile initialIntensity = continuum.getInitialConditions()
        .get(TurbulenceIntensityProfile.class);
    initialIntensity.getMethod(ConstantScalarProfileMethod.class).getQuantity()
        .setValue(intensity);
    TurbulentViscosityRatioProfile initialViscosityRatio =
        continuum.getInitialConditions().get(TurbulentViscosityRatioProfile.class);
    initialViscosityRatio.getMethod(ConstantScalarProfileMethod.class).getQuantity()
        .setValue(viscosityRatio);

    // Equivalent k and omega are diagnostics for reproducibility and for
    // comparison with Nektar++ initial-condition conventions.
    double turbulentKineticEnergy = 1.5 * Math.pow(intensity * velocity, 2.0);
    double specificDissipationRate = density * turbulentKineticEnergy
        / (viscosity * viscosityRatio);

    Boundary wing = requiredBoundary(region, wingName);
    Boundary upstream = requiredBoundary(region, upstreamName);
    Boundary top = requiredBoundary(region, topName);
    Boundary bottom = requiredBoundary(region, bottomName);
    Boundary downstream = requiredBoundary(region, downstreamName);
    Boundary spanMin = requiredBoundary(region, spanMinName);
    Boundary spanMax = requiredBoundary(region, spanMaxName);

    validateBoundaryGeometry(
        simulation, wing, upstream, downstream, top, bottom, spanMin, spanMax);

    wing.setBoundaryType(WallBoundary.class);
    configureVelocityInlet(
        upstream, velocity,
        ux / velocity, uy / velocity, uz, intensity, viscosityRatio);
    configureVelocityInlet(
        top, velocity,
        ux / velocity, uy / velocity, uz, intensity, viscosityRatio);
    configureVelocityInlet(
        bottom, velocity,
        ux / velocity, uy / velocity, uz, intensity, viscosityRatio);

    downstream.setBoundaryType(PressureBoundary.class);
    StaticPressureProfile pressureProfile = downstream.getValues()
        .get(StaticPressureProfile.class);
    pressureProfile.getMethod(ConstantScalarProfileMethod.class).getQuantity()
        .setValue(pressure);

    if ("symmetry".equals(spanMode)) {
      spanMin.setBoundaryType(SymmetryBoundary.class);
      spanMax.setBoundaryType(SymmetryBoundary.class);
    } else if ("periodic".equals(spanMode)) {
      // Periodicity is an interface relationship in STAR, not a boundary type.
      // The named periodic interface must already exist in the input template;
      // do not overwrite its two participating boundaries here.
      BoundaryInterface periodicInterface;
      try {
        periodicInterface = (BoundaryInterface) simulation.getInterfaceManager()
            .getInterface(periodicInterfaceName);
      } catch (RuntimeException error) {
        throw new IllegalStateException(
            "Required STAR periodic interface does not exist: "
            + periodicInterfaceName, error);
      }
      // Periodicity is an interface topology in this STAR release; the
      // interface type itself is normally Internal Interface.
      if (periodicInterface == null || !periodicInterface.isPeriodic()) {
        throw new IllegalStateException(
            "Interface is missing or is not periodic: " + periodicInterfaceName);
      }
    } else {
      throw new IllegalArgumentException(
          "STAR_RANS_SPAN_MODE must be symmetry or periodic: " + spanMode);
    }

    int residualCriterionCount = configureStoppingCriteria(
        simulation, maximumSteps, minimumSteps, residualTolerance);

    simulation.println("STAR_BATCH_RANS_CONFIGURATION");
    simulation.println("  region                    = " + regionName);
    simulation.println("  continuum                 = " + continuumName);
    simulation.println("  model                     = steady constant-density SST k-omega");
    simulation.println("  wall_treatment            = all-y+");
    simulation.println("  normalization             = U=1, rho=1, chord=1, mu=nu=1/Re");
    simulation.println("  nondimensional_velocity   = " + velocity);
    simulation.println("  angle_deg                 = " + angleDegrees);
    simulation.println("  nondimensional_velocity_vector = (" + ux + " " + uy + " " + uz + ")");
    simulation.println("  nondimensional_density    = " + density);
    simulation.println("  dynamic_and_kinematic_viscosity = " + viscosity);
    simulation.println("  chord_reynolds            = " + reynolds);
    simulation.println("  reference_pressure        = " + pressure);
    simulation.println("  turbulence_intensity      = " + intensity);
    simulation.println("  turbulent_viscosity_ratio = " + viscosityRatio);
    simulation.println("  initial_turbulence_spec   = intensity + viscosity ratio");
    simulation.println("  nondimensional_equivalent_k = " + turbulentKineticEnergy);
    simulation.println("  nondimensional_equivalent_omega = " + specificDissipationRate);
    simulation.println("  maximum_steps             = " + maximumSteps);
    simulation.println("  minimum_steps             = " + minimumSteps);
    simulation.println("  residual_tolerance        = " + residualTolerance);
    simulation.println("  residual_criteria         = " + residualCriterionCount);
    simulation.println("  stopping_logic            = max OR (min AND all residuals)");
    simulation.println("  span_boundary_mode        = " + spanMode);
    simulation.println("  periodic_interface        = " + periodicInterfaceName);
    simulation.println("  resolved_wing_boundary    = " + wing.getPresentationName());
    simulation.println("  resolved_upstream_boundary= " + upstream.getPresentationName());
    simulation.println("  resolved_downstream_bdry  = " + downstream.getPresentationName());
    simulation.println("  resolved_top_boundary     = " + top.getPresentationName());
    simulation.println("  resolved_bottom_boundary  = " + bottom.getPresentationName());

    // The shell driver launches configuration and solution as two separate
    // STAR processes. Saving here guarantees that a failed configuration can
    // never fall through into a solver run with stale template settings.
    simulation.saveState(resolvePath(simulationOutput));
    File configuredSimulation = new File(simulationOutput);
    if (!configuredSimulation.isFile() || configuredSimulation.length() == 0L) {
      throw new IllegalStateException(
          "STAR did not save the configured RANS simulation: " + simulationOutput);
    }
    simulation.println("STAR_BATCH_RANS_CONFIGURED");
  }

  private PhysicsContinuum findContinuum(
      Simulation simulation, String presentationName) {
    for (PhysicsContinuum continuum
        : simulation.getContinuumManager().getObjectsOf(PhysicsContinuum.class)) {
      if (presentationName.equals(continuum.getPresentationName())) {
        return continuum;
      }
    }
    return null;
  }

  private void validateBoundaryGeometry(
      Simulation simulation,
      Boundary wing,
      Boundary upstream,
      Boundary downstream,
      Boundary top,
      Boundary bottom,
      Boundary spanMin,
      Boundary spanMax) {
    List<Boundary> boundaries = Arrays.asList(
        wing, upstream, downstream, top, bottom, spanMin, spanMax);
    FieldFunction position = simulation.getFieldFunctionManager()
        .getFunction("Position");
    if (position == null) {
      throw new IllegalStateException(
          "STAR Position field function is unavailable for boundary validation");
    }

    MinReport minimumReport = simulation.getReportManager()
        .createReport(MinReport.class);
    MaxReport maximumReport = simulation.getReportManager()
        .createReport(MaxReport.class);
    double[][] minimum = new double[boundaries.size()][3];
    double[][] maximum = new double[boundaries.size()][3];
    try {
      simulation.println("  boundary geometry:");
      for (int index = 0; index < boundaries.size(); ++index) {
        Boundary boundary = boundaries.get(index);
        minimumReport.getParts().setObjects(boundary);
        maximumReport.getParts().setObjects(boundary);
        for (int component = 0; component < 3; ++component) {
          FieldFunction coordinate = position.getComponentFunction(component);
          minimumReport.setFieldFunction(coordinate);
          maximumReport.setFieldFunction(coordinate);
          minimum[index][component] = minimumReport.getValue();
          maximum[index][component] = maximumReport.getValue();
          if (!Double.isFinite(minimum[index][component])
              || !Double.isFinite(maximum[index][component])) {
            throw new IllegalStateException(
                "Non-finite coordinate bound for boundary "
                + boundary.getPresentationName());
          }
        }
        simulation.println(String.format(
            "    %-18s bbox=(%.9g %.9g %.9g) -> "
            + "(%.9g %.9g %.9g)",
            boundary.getPresentationName(),
            minimum[index][0], minimum[index][1], minimum[index][2],
            maximum[index][0], maximum[index][1], maximum[index][2]));
      }
    } finally {
      simulation.getReportManager().removeObjects(
          minimumReport, maximumReport);
    }

    double[] globalMinimum = new double[] {
        Double.POSITIVE_INFINITY,
        Double.POSITIVE_INFINITY,
        Double.POSITIVE_INFINITY};
    double[] globalMaximum = new double[] {
        Double.NEGATIVE_INFINITY,
        Double.NEGATIVE_INFINITY,
        Double.NEGATIVE_INFINITY};
    for (int index = 0; index < boundaries.size(); ++index) {
      for (int component = 0; component < 3; ++component) {
        globalMinimum[component] = Math.min(
            globalMinimum[component], minimum[index][component]);
        globalMaximum[component] = Math.max(
            globalMaximum[component], maximum[index][component]);
      }
    }
    double maximumExtent = 0.0;
    for (int component = 0; component < 3; ++component) {
      maximumExtent = Math.max(maximumExtent,
          globalMaximum[component] - globalMinimum[component]);
    }
    double tolerance = Math.max(1.0e-10, maximumExtent * 1.0e-7);

    requireOuterPlane(
        upstream, minimum[1], maximum[1], 0, globalMinimum[0], tolerance);
    requireOuterPlane(
        downstream, minimum[2], maximum[2], 0, globalMaximum[0], tolerance);
    requireOuterPlane(
        top, minimum[3], maximum[3], 1, globalMaximum[1], tolerance);
    requireOuterPlane(
        bottom, minimum[4], maximum[4], 1, globalMinimum[1], tolerance);
    requireOuterPlane(
        spanMin, minimum[5], maximum[5], 2, globalMinimum[2], tolerance);
    requireOuterPlane(
        spanMax, minimum[6], maximum[6], 2, globalMaximum[2], tolerance);

    // The airfoil spans the z extent but must remain strictly inside the
    // rectangular farfield in x and y.
    if (minimum[0][0] <= globalMinimum[0] + tolerance
        || maximum[0][0] >= globalMaximum[0] - tolerance
        || minimum[0][1] <= globalMinimum[1] + tolerance
        || maximum[0][1] >= globalMaximum[1] - tolerance) {
      throw new IllegalStateException(
          "Boundary named " + wing.getPresentationName()
          + " touches the outer x/y domain and is not the airfoil wall");
    }
    simulation.println("  boundary geometry validation = passed");
  }

  private void requireOuterPlane(
      Boundary boundary,
      double[] minimum,
      double[] maximum,
      int component,
      double expected,
      double tolerance) {
    if (Math.abs(minimum[component] - expected) > tolerance
        || Math.abs(maximum[component] - expected) > tolerance) {
      throw new IllegalStateException(
          "Boundary " + boundary.getPresentationName()
          + " is not on its expected outer-domain plane; coordinate bounds "
          + minimum[component] + " to " + maximum[component]
          + ", expected " + expected);
    }
  }

  private int configureStoppingCriteria(
      Simulation simulation,
      int maximumSteps,
      int minimumSteps,
      double residualTolerance) {
    SolverStoppingCriterionManager manager =
        simulation.getSolverStoppingCriterionManager();

    SolverStoppingCriterion maximumObject =
        manager.hasSolverStoppingCriterion("Maximum Steps");
    if (!(maximumObject instanceof StepStoppingCriterion)) {
      throw new IllegalStateException(
          "STAR stopping criterion 'Maximum Steps' is unavailable or has "
          + "an unexpected type");
    }
    StepStoppingCriterion maximumCriterion =
        (StepStoppingCriterion) maximumObject;
    maximumCriterion.setMaximumNumberSteps(maximumSteps);
    maximumCriterion.setIsUsed(true);
    maximumCriterion.getLogicalOption()
        .setSelected(SolverStoppingCriterionLogicalOption.Type.OR);

    // FixedStepsStoppingCriterion is visible in the 20.04 Java API but its
    // native manager rejects attempts to create it. Use the built-in
    // iteration monitor with a maximum-limit criterion instead: it becomes
    // satisfied once Iteration >= minimumSteps and acts as the AND gate for
    // the residual criteria.
    String minimumName = "RANS Minimum Steps Gate";
    SolverStoppingCriterion minimumObject =
        manager.hasSolverStoppingCriterion(minimumName);
    MonitorIterationStoppingCriterion minimumCriterion;
    if (minimumObject == null) {
      minimumCriterion = manager.createIterationStoppingCriterion(
          simulation.getMonitorManager().getIterationMonitor());
      minimumCriterion.setPresentationName(minimumName);
    } else if (minimumObject instanceof MonitorIterationStoppingCriterion) {
      minimumCriterion = (MonitorIterationStoppingCriterion) minimumObject;
      minimumCriterion.setMonitor(
          simulation.getMonitorManager().getIterationMonitor());
    } else {
      throw new IllegalStateException(
          "Stopping criterion has an unexpected type: " + minimumName);
    }
    minimumCriterion.getCriterionOption().setSelected(
        MonitorIterationStoppingCriterionOption.Type.MAXIMUM);
    if (!(minimumCriterion.getCriterionType()
        instanceof MonitorIterationStoppingCriterionMaxLimitType)) {
      throw new IllegalStateException(
          "STAR did not activate an iteration maximum-limit criterion");
    }
    MonitorIterationStoppingCriterionMaxLimitType iterationLimit =
        (MonitorIterationStoppingCriterionMaxLimitType)
            minimumCriterion.getCriterionType();
    iterationLimit.getLimit().setValue(minimumSteps);
    minimumCriterion.setIsUsed(true);
    minimumCriterion.getLogicalOption()
        .setSelected(SolverStoppingCriterionLogicalOption.Type.AND);

    Vector<ResidualMonitor> residualMonitors = simulation.getMonitorManager()
        .getResidualMonitors();
    if (residualMonitors.isEmpty()) {
      throw new IllegalStateException(
          "No active residual monitors are available for convergence criteria");
    }

    int count = 0;
    for (ResidualMonitor monitor : residualMonitors) {
      String criterionName = "RANS Residual " + monitor.getPresentationName();
      SolverStoppingCriterion existing =
          manager.hasSolverStoppingCriterion(criterionName);
      MonitorIterationStoppingCriterion criterion;
      if (existing == null) {
        criterion = manager.createIterationStoppingCriterion(monitor);
        criterion.setPresentationName(criterionName);
      } else if (existing instanceof MonitorIterationStoppingCriterion) {
        criterion = (MonitorIterationStoppingCriterion) existing;
        criterion.setMonitor(monitor);
      } else {
        throw new IllegalStateException(
            "Stopping criterion has an unexpected type: " + criterionName);
      }

      criterion.getCriterionOption().setSelected(
          MonitorIterationStoppingCriterionOption.Type.MINIMUM);
      if (!(criterion.getCriterionType()
          instanceof MonitorIterationStoppingCriterionMinLimitType)) {
        throw new IllegalStateException(
            "STAR did not activate a minimum-limit criterion for residual "
            + monitor.getPresentationName());
      }
      MonitorIterationStoppingCriterionMinLimitType minimumType =
          (MonitorIterationStoppingCriterionMinLimitType)
              criterion.getCriterionType();
      minimumType.getLimit().setValue(residualTolerance);
      criterion.setIsUsed(true);
      criterion.getLogicalOption()
          .setSelected(SolverStoppingCriterionLogicalOption.Type.AND);
      simulation.println("  residual criterion        = "
          + monitor.getPresentationName() + " < " + residualTolerance);
      count++;
    }
    return count;
  }

  private Boundary requiredBoundary(Region region, String name) {
    Boundary suffixMatch = null;
    String suffix = "." + name;
    StringBuilder available = new StringBuilder();
    for (Boundary candidate : region.getBoundaryManager().getBoundaries()) {
      String candidateName = candidate.getPresentationName();
      if (available.length() > 0) {
        available.append(", ");
      }
      available.append(candidateName);
      if (candidateName.equals(name)) {
        return candidate;
      }
      if (name.indexOf('.') < 0 && candidateName.endsWith(suffix)) {
        if (suffixMatch != null) {
          throw new IllegalStateException(
              "Short boundary name is ambiguous in region "
              + region.getPresentationName() + ": " + name);
        }
        suffixMatch = candidate;
      }
    }
    if (suffixMatch != null) {
      return suffixMatch;
    }
    throw new IllegalStateException(
        "Required boundary does not exist in region "
        + region.getPresentationName() + ": " + name
        + ". Available boundaries: " + available.toString());
  }

  private void configureVelocityInlet(
      Boundary boundary,
      double magnitude,
      double dirX,
      double dirY,
      double dirZ,
      double turbulenceIntensity,
      double turbulentViscosityRatio) {
    boundary.setBoundaryType(InletBoundary.class);
    boundary.getConditions().get(KwTurbSpecOption.class)
        .setSelected(KwTurbSpecOption.Type.INTENSITY_VISCOSITY_RATIO);
    boundary.getConditions().get(InletVelocityOption.class)
        .setSelected(InletVelocityOption.Type.COMPONENTS);
    boundary.getValues().get(VelocityProfile.class)
        .getMethod(ConstantVectorProfileMethod.class).getQuantity()
        .setComponents(magnitude * dirX, magnitude * dirY, magnitude * dirZ);
    boundary.getValues().get(TurbulenceIntensityProfile.class)
        .getMethod(ConstantScalarProfileMethod.class).getQuantity()
        .setValue(turbulenceIntensity);
    boundary.getValues().get(TurbulentViscosityRatioProfile.class)
        .getMethod(ConstantScalarProfileMethod.class).getQuantity()
        .setValue(turbulentViscosityRatio);
  }

  private String requiredString(String name) {
    String value = System.getenv(name);
    if (value == null || value.trim().isEmpty()) {
      throw new IllegalArgumentException(
          "Required environment variable is not set: " + name);
    }
    return value.trim();
  }

  private double requiredDouble(String name) {
    String value = requiredString(name);
    try {
      return Double.parseDouble(value);
    } catch (NumberFormatException error) {
      throw new IllegalArgumentException(
          "Environment variable is not a number: " + name + "=" + value,
          error);
    }
  }

  private int requiredInteger(String name) {
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
