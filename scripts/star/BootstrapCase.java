// Simcenter STAR-CCM+ 20.04 batch macro.
//
// Bootstrap the canonical NACA0012 fluid-domain STEP into a simulation that
// can be consumed by ConfigureMesh.java.  The macro deliberately imports the
// STEP as a CAD-backed Geometry Part: no STL or intermediate tessellated file
// is involved.
package macro;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Vector;
import star.base.neo.DoubleVector;
import star.base.report.MaxReport;
import star.base.report.MinReport;
import star.common.Boundary;
import star.common.BoundaryInterface;
import star.common.FieldFunction;
import star.common.GeometryPart;
import star.common.InterfaceConfigurationOption;
import star.common.InterfaceConnectivityOption;
import star.common.PartSurface;
import star.common.PartContactManager;
import star.common.PartSurfaceContact;
import star.common.PartSurfaceManager;
import star.common.PeriodicityOption;
import star.common.Region;
import star.common.RegionManager;
import star.common.Simulation;
import star.common.SimulationPartManager;
import star.common.StarMacro;
import star.meshing.AutoMeshOperation;
import star.meshing.CadPart;
import star.meshing.MeshOperationManager;
import star.meshing.PartImportManager;
import star.meshing.PeriodicPartSurfaceContact;
import star.meshing.PartsMinimumSurfaceSizeOption;
import star.meshing.PartsSurfaceCurvatureOption;
import star.meshing.PartsTargetSurfaceSizeOption;
import star.meshing.SurfaceCustomMeshControl;
import star.prismmesher.PartsCustomPrismsOption;
import star.prismmesher.PartsCustomizePrismMesh;

public class BootstrapCase extends StarMacro {

  private static final List<String> BOUNDARY_ORDER = Arrays.asList(
      "Wing",
      "Downstream",
      "SpanMin",
      "FarfieldTop",
      "SpanMax",
      "FarfieldBottom",
      "Upstream");

  @Override
  public void execute() {
    Simulation simulation = getActiveSimulation();
    String stepFile = MacroSupport.requiredString("STAR_STEP_INPUT");
    String outputSimulation = MacroSupport.requiredString("STAR_SIM_OUTPUT");
    String partName = MacroSupport.optionalString(
        "STAR_GEOMETRY_PART", "naca0012_domain");
    String regionName = MacroSupport.optionalString("STAR_REGION", "Fluid");
    String operationName = MacroSupport.optionalString(
        "STAR_MESH_OPERATION", "NACA0012_AutomatedMesh");
    String wingControlName = MacroSupport.optionalString(
        "STAR_WING_CONTROL", "WingSurfaceControl");
    String farfieldControlName = MacroSupport.optionalString(
        "STAR_FARFIELD_CONTROL", "NoPrismFarfieldControl");
    String periodicInterfaceName = MacroSupport.optionalString(
        "STAR_PERIODIC_INTERFACE", "SpanwisePeriodic");
    boolean periodicSpan = optionalBoolean("STAR_PERIODIC_SPAN", true);
    DoubleVector periodicTranslation = new DoubleVector(new double[] {
        MacroSupport.optionalDouble("STAR_PERIODIC_TRANSLATION_X_M", 0.0),
        MacroSupport.optionalDouble("STAR_PERIODIC_TRANSLATION_Y_M", 0.0),
        MacroSupport.optionalDouble("STAR_PERIODIC_TRANSLATION_Z_M", 0.2)});

    Collection<GeometryPart> existingParts = simulation
        .get(SimulationPartManager.class).getPartManager().getLeafParts();
    if (!existingParts.isEmpty() || !simulation.getRegionManager().getRegions().isEmpty()) {
      throw new IllegalStateException(
          "BootstrapCase must run in a new, empty STAR simulation");
    }

    simulation.println("STAR_BATCH_BOOTSTRAP");
    simulation.println("  step_file                  = " + stepFile);
    simulation.println("  periodic_span              = " + periodicSpan);

    // SharpEdges preserves the STEP BRep and its CAD association. The input
    // STEP declares millimetres; STAR converts coordinates to SI internally.
    // Imported face names/order are deliberately not trusted below.
    simulation.get(PartImportManager.class).importCadPart(
        stepFile, "SharpEdges", 30.0, 2, 1.0e-5);

    CadPart cadPart = requireSingleCadPart(simulation);
    cadPart.setPresentationName(partName);
    List<PartSurface> importedFaces = getCanonicalFaces(cadPart);
    Map<String, List<PartSurface>> surfacesByName = renameCanonicalFaces(
        simulation, importedFaces);

    // A region-level periodic interface alone couples the solver, but does
    // not force the parts-based surface remesher to create a one-to-one pair.
    // STAR represents that meshing constraint as a mesh-only periodic part
    // surface contact. Create it before the region/interface hierarchy.
    PeriodicPartSurfaceContact periodicPartContact = null;
    if (periodicSpan) {
      periodicPartContact = createPeriodicPartContact(
          simulation,
          surfacesByName.get("SpanMin").get(0),
          surfacesByName.get("SpanMax").get(0),
          periodicTranslation);
    }

    simulation.getRegionManager().newRegionsFromParts(
        Collections.<GeometryPart>singletonList(cadPart),
        "OneRegion", null,
        "OneBoundaryPerPartSurface", null,
        "OneFeatureCurve", null,
        RegionManager.CreateInterfaceMode.BOUNDARY);

    Region region = requireSingleRegion(simulation);
    region.setPresentationName(regionName);
    Map<String, Boundary> boundaries = consolidateBoundaries(
        simulation, region, surfacesByName);

    AutoMeshOperation operation = simulation.get(MeshOperationManager.class)
        .createAutoMeshOperation(
            Arrays.asList(
                "star.resurfacer.ResurfacerAutoMesher",
                "star.delaunaymesher.DelaunayAutoMesher",
                "star.prismmesher.PrismAutoMesher"),
            Collections.<GeometryPart>singletonList(cadPart));
    operation.setPresentationName(operationName);

    SurfaceCustomMeshControl wingControl = operation.getCustomMeshControls()
        .createSurfaceControl();
    wingControl.setPresentationName(wingControlName);
    wingControl.getGeometryObjects().setObjects(surfacesByName.get("Wing"), false);
    wingControl.getCustomConditions().get(PartsTargetSurfaceSizeOption.class)
        .setSelected(PartsTargetSurfaceSizeOption.Type.CUSTOM);
    wingControl.getCustomConditions().get(PartsMinimumSurfaceSizeOption.class)
        .setSelected(PartsMinimumSurfaceSizeOption.Type.CUSTOM);
    wingControl.getCustomConditions().get(PartsSurfaceCurvatureOption.class)
        .setSelected(PartsSurfaceCurvatureOption.Type.CUSTOM_VALUES);

    // Prism Layer Mesher otherwise considers every wall-like part surface.
    // Disable it explicitly on all six outer-domain surfaces; the wing keeps
    // the parent prism defaults configured later by ConfigureMesh.java.
    List<PartSurface> outerSurfaces = new ArrayList<>();
    for (String name : BOUNDARY_ORDER) {
      if (!"Wing".equals(name)) {
        outerSurfaces.addAll(surfacesByName.get(name));
      }
    }
    SurfaceCustomMeshControl farfieldControl = operation.getCustomMeshControls()
        .createSurfaceControl();
    farfieldControl.setPresentationName(farfieldControlName);
    farfieldControl.getGeometryObjects().setObjects(outerSurfaces, false);
    farfieldControl.getCustomConditions().get(PartsCustomizePrismMesh.class)
        .getCustomPrismOptions()
        .setSelected(PartsCustomPrismsOption.Type.DISABLE);

    if (periodicSpan) {
      BoundaryInterface periodicInterface = simulation.getInterfaceManager()
          .createBoundaryInterface(
              boundaries.get("SpanMin"),
              boundaries.get("SpanMax"),
              periodicInterfaceName);
      periodicInterface.getTopology().setSelected(
          InterfaceConfigurationOption.Type.PERIODIC);
      periodicInterface.getConnectivity().setSelected(
          InterfaceConnectivityOption.Type.IMPRINTED);
      periodicInterface.getPeriodicTransform().getPeriodicityOption()
          .setSelected(PeriodicityOption.Type.TRANSLATION);
      periodicInterface.getPeriodicTransform().set(
          "TranslationVector", periodicTranslation);
      periodicInterface.getPeriodicTransform().setLocked(true);
      periodicInterface.setResetOnRelativeMotion(true);
      simulation.getInterfaceManager().initializeInterfaces(
          Collections.singletonList(periodicInterface));
      // createBoundaryInterface treats its String argument as a naming base
      // in STAR 20.04 and may append " 1". Downstream RANS configuration
      // resolves the interface by this exact stable presentation name.
      periodicInterface.setPresentationName(periodicInterfaceName);
      if (!periodicInterface.isPeriodic()) {
        throw new IllegalStateException(
            "Created interface is not periodic: " + periodicInterfaceName);
      }
      DoubleVector partTranslation = periodicPartContact.getTransform()
          .getTranslationVector();
      DoubleVector interfaceTranslation = periodicInterface
          .getPeriodicTransform().getTranslationVector();
      if (vectorDistance(partTranslation, periodicTranslation) > 1.0e-12
          || vectorDistance(interfaceTranslation, periodicTranslation)
              > 1.0e-12) {
        throw new IllegalStateException(
            "Periodic translation differs from configured value "
            + periodicTranslation + ": part contact " + partTranslation
            + ", region interface " + interfaceTranslation);
      }
      simulation.println("  periodic_part_translation  = "
          + partTranslation);
      simulation.println("  periodic_interface_translation = "
          + interfaceTranslation);
      simulation.println("  resolved_periodic_interface= "
          + periodicInterface.getPresentationName());
    }

    simulation.println("  geometry_part              = " + partName);
    simulation.println("  cad_faces                  = " + importedFaces.size());
    simulation.println("  region                     = " + regionName);
    simulation.println("  physical_boundaries        = " + boundaries.size());
    simulation.println("  mesh_operation             = " + operationName);
    simulation.println("  meshers                    = Surface Remesher, Tetrahedral, Prism Layer");
    simulation.println("  wing_control               = " + wingControlName);
    simulation.println("  farfield_no_prism_control  = " + farfieldControlName);
    simulation.println("  periodic_interface         = "
        + (periodicSpan ? periodicInterfaceName : "disabled"));

    simulation.saveState(outputSimulation);
    simulation.println("  output_sim                 = " + outputSimulation);
    simulation.println("STAR_BATCH_BOOTSTRAP_COMPLETE");
  }

  private CadPart requireSingleCadPart(Simulation simulation) {
    List<CadPart> parts = new ArrayList<>();
    for (GeometryPart part : simulation.get(SimulationPartManager.class)
        .getPartManager().getLeafParts()) {
      if (part instanceof CadPart) {
        parts.add((CadPart) part);
      }
    }
    if (parts.size() != 1) {
      throw new IllegalStateException(
          "Expected one imported CAD part, found " + parts.size());
    }
    return parts.get(0);
  }

  private PeriodicPartSurfaceContact createPeriodicPartContact(
      Simulation simulation,
      PartSurface spanMin,
      PartSurface spanMax,
      DoubleVector translation) {
    Collection<PartSurfaceContact> contacts = simulation
        .get(PartContactManager.class).createPeriodic(spanMin, spanMax);
    if (contacts.size() != 1) {
      throw new IllegalStateException(
          "Expected one periodic part-surface contact, created "
          + contacts.size());
    }
    PartSurfaceContact contact = contacts.iterator().next();
    if (!(contact instanceof PeriodicPartSurfaceContact)) {
      throw new IllegalStateException(
          "STAR created a non-periodic part-surface contact: "
          + contact.getClass().getName());
    }
    PeriodicPartSurfaceContact periodic =
        (PeriodicPartSurfaceContact) contact;
    periodic.setMeshOnlyContact(true);
    periodic.getTransform().getPeriodicityOption()
        .setSelected(PeriodicityOption.Type.TRANSLATION);
    periodic.getTransform().set("TranslationVector", translation);
    periodic.getTransform().setLocked(true);
    simulation.println("  periodic_part_contact      = "
        + spanMin.getPresentationName() + " <-> "
        + spanMax.getPresentationName());
    return periodic;
  }

  private double vectorDistance(DoubleVector first, DoubleVector second) {
    if (first.size() != second.size()) {
      return Double.POSITIVE_INFINITY;
    }
    double sum = 0.0;
    for (int index = 0; index < first.size(); ++index) {
      double difference = first.get(index) - second.get(index);
      sum += difference * difference;
    }
    return Math.sqrt(sum);
  }

  private List<PartSurface> getCanonicalFaces(CadPart cadPart) {
    PartSurfaceManager surfaceManager = cadPart.hasPartSurfaceManager();
    PartSurface defaultSurface = surfaceManager.getDefaultPartSurface();

    // importCadPart can preserve the STEP as a proper CAD BRep while still
    // assigning every CAD face to one Default part surface. Split that group
    // along the imported CAD part curves, which exposes the nine underlying
    // STEP faces without triangulating or losing CAD association.
    if (cadPart.getPartSurfaces().size() == 1
        && defaultSurface != null
        && !cadPart.getPartCurves().isEmpty()) {
      cadPart.getSimulation().println(
          "  splitting Default surface along "
          + cadPart.getPartCurves().size() + " CAD part curves");
      surfaceManager.splitPartSurfacesByPartCurves(
          Collections.singletonList(defaultSurface),
          cadPart.getPartCurves());
    }

    List<PartSurface> faces = new ArrayList<>();
    for (PartSurface surface : cadPart.getPartSurfaces()) {
      // splitPartSurfacesByPartCurves may retain one real CAD face in the
      // object that used to be Default. In the canonical blunt-TE geometry
      // this is the small trailing-edge face, so excluding Default by object
      // identity silently leaves part of the wall in a separate boundary.
      if (cadPart.getNumFacesInPartSurface(surface) > 0) {
        faces.add(surface);
      }
    }
    faces.sort(Comparator.comparingLong(PartSurface::getObjectId));
    if (faces.size() < BOUNDARY_ORDER.size() || faces.size() > 9) {
      throw new IllegalStateException(
          "Canonical NACA0012 STEP must import as seven to nine nonempty "
          + "part surfaces; found " + faces.size());
    }
    return faces;
  }

  private Map<String, List<PartSurface>> renameCanonicalFaces(
      Simulation simulation, List<PartSurface> faces) {
    Map<String, List<PartSurface>> grouped = new LinkedHashMap<>();
    for (String name : BOUNDARY_ORDER) {
      grouped.put(name, new ArrayList<PartSurface>());
    }

    // STEP face names are not reliably preserved by STAR's CAD translator,
    // and object IDs reflect split/creation history rather than geometry.
    // Classify the six rectangular outer faces from their coordinate bounds;
    // every remaining face belongs to the airfoil wall. This also handles
    // either grouped or individual upper/lower/trailing-edge wall surfaces.
    List<SurfaceBounds> bounds = measureSurfaceBounds(simulation, faces);
    double[] globalMinimum = new double[] {
        Double.POSITIVE_INFINITY,
        Double.POSITIVE_INFINITY,
        Double.POSITIVE_INFINITY};
    double[] globalMaximum = new double[] {
        Double.NEGATIVE_INFINITY,
        Double.NEGATIVE_INFINITY,
        Double.NEGATIVE_INFINITY};
    for (SurfaceBounds item : bounds) {
      for (int component = 0; component < 3; ++component) {
        globalMinimum[component] = Math.min(
            globalMinimum[component], item.minimum[component]);
        globalMaximum[component] = Math.max(
            globalMaximum[component], item.maximum[component]);
      }
    }
    double maximumExtent = 0.0;
    for (int component = 0; component < 3; ++component) {
      maximumExtent = Math.max(maximumExtent,
          globalMaximum[component] - globalMinimum[component]);
    }
    double tolerance = Math.max(1.0e-10, maximumExtent * 1.0e-7);

    int wingIndex = 0;
    for (int index = 0; index < bounds.size(); ++index) {
      SurfaceBounds item = bounds.get(index);
      PartSurface face = item.surface;
      String conceptualName = classifySurface(
          item, globalMinimum, globalMaximum, tolerance);
      String uniqueName = conceptualName;
      if ("Wing".equals(conceptualName)) {
        uniqueName = "WingFace" + (++wingIndex);
      }
      face.setPresentationName(uniqueName);
      grouped.get(conceptualName).add(face);
      simulation.println(String.format(
          "  cad_surface[%d]          = %-16s object=%d "
          + "bbox=(%.9g %.9g %.9g) -> (%.9g %.9g %.9g)",
          index, uniqueName, face.getObjectId(),
          item.minimum[0], item.minimum[1], item.minimum[2],
          item.maximum[0], item.maximum[1], item.maximum[2]));
    }
    for (String name : BOUNDARY_ORDER) {
      if (grouped.get(name).isEmpty()
          || (!"Wing".equals(name) && grouped.get(name).size() != 1)) {
        throw new IllegalStateException(
            "Geometric CAD classification expected one " + name
            + " surface group; found " + grouped.get(name).size());
      }
    }
    return grouped;
  }

  private List<SurfaceBounds> measureSurfaceBounds(
      Simulation simulation, List<PartSurface> surfaces) {
    FieldFunction position = simulation.getFieldFunctionManager()
        .getFunction("Position");
    if (position == null) {
      throw new IllegalStateException(
          "STAR Position field function is unavailable for CAD classification");
    }

    MinReport minimumReport = simulation.getReportManager()
        .createReport(MinReport.class);
    MaxReport maximumReport = simulation.getReportManager()
        .createReport(MaxReport.class);
    List<SurfaceBounds> result = new ArrayList<>();
    try {
      for (PartSurface surface : surfaces) {
        minimumReport.getParts().setObjects(surface);
        maximumReport.getParts().setObjects(surface);
        double[] minimum = new double[3];
        double[] maximum = new double[3];
        for (int component = 0; component < 3; ++component) {
          FieldFunction coordinate = position.getComponentFunction(component);
          minimumReport.setFieldFunction(coordinate);
          maximumReport.setFieldFunction(coordinate);
          minimum[component] = minimumReport.getValue();
          maximum[component] = maximumReport.getValue();
          if (!Double.isFinite(minimum[component])
              || !Double.isFinite(maximum[component])) {
            throw new IllegalStateException(
                "Non-finite coordinate bound for part surface "
                + surface.getPresentationName());
          }
        }
        result.add(new SurfaceBounds(surface, minimum, maximum));
      }
    } finally {
      simulation.getReportManager().removeObjects(
          minimumReport, maximumReport);
    }
    return result;
  }

  private String classifySurface(
      SurfaceBounds bounds,
      double[] globalMinimum,
      double[] globalMaximum,
      double tolerance) {
    if (constantAt(bounds, 0, globalMinimum[0], tolerance)) {
      return "Upstream";
    }
    if (constantAt(bounds, 0, globalMaximum[0], tolerance)) {
      return "Downstream";
    }
    if (constantAt(bounds, 1, globalMinimum[1], tolerance)) {
      return "FarfieldBottom";
    }
    if (constantAt(bounds, 1, globalMaximum[1], tolerance)) {
      return "FarfieldTop";
    }
    if (constantAt(bounds, 2, globalMinimum[2], tolerance)) {
      return "SpanMin";
    }
    if (constantAt(bounds, 2, globalMaximum[2], tolerance)) {
      return "SpanMax";
    }
    return "Wing";
  }

  private boolean constantAt(
      SurfaceBounds bounds, int component, double value, double tolerance) {
    return Math.abs(bounds.minimum[component] - value) <= tolerance
        && Math.abs(bounds.maximum[component] - value) <= tolerance;
  }

  private static final class SurfaceBounds {
    private final PartSurface surface;
    private final double[] minimum;
    private final double[] maximum;

    private SurfaceBounds(
        PartSurface surface, double[] minimum, double[] maximum) {
      this.surface = surface;
      this.minimum = minimum;
      this.maximum = maximum;
    }
  }

  private Region requireSingleRegion(Simulation simulation) {
    Collection<Region> regions = simulation.getRegionManager().getRegions();
    if (regions.size() != 1) {
      throw new IllegalStateException(
          "Expected one fluid region, found " + regions.size());
    }
    return regions.iterator().next();
  }

  private Map<String, Boundary> consolidateBoundaries(
      Simulation simulation,
      Region region,
      Map<String, List<PartSurface>> surfacesByName) {
    Map<String, Boundary> result = new LinkedHashMap<>();
    List<Boundary> redundantWingBoundaries = new ArrayList<>();

    for (String name : BOUNDARY_ORDER) {
      List<PartSurface> surfaces = surfacesByName.get(name);
      Boundary boundary = surfaces.get(0).getBoundary();
      if (boundary == null) {
        throw new IllegalStateException(
            "Part surface was not assigned to a boundary: "
            + surfaces.get(0).getPresentationName());
      }
      boundary.setPresentationName(name);
      if (surfaces.size() > 1) {
        for (int index = 1; index < surfaces.size(); ++index) {
          Boundary other = surfaces.get(index).getBoundary();
          if (other != null && other != boundary) {
            redundantWingBoundaries.add(other);
          }
        }
        boundary.getPartSurfaceGroup().setObjects(surfaces);
      }
      result.put(name, boundary);
    }

    if (!redundantWingBoundaries.isEmpty()) {
      region.getBoundaryManager().removeBoundaries(
          new Vector<Boundary>(redundantWingBoundaries));
    }

    // BoundaryManager does not support reorderObjects in STAR-CCM+ 20.04.
    // No downstream stage relies on tree order: boundaries are resolved by
    // their stable presentation names.
    simulation.println("  named_boundaries           = " + BOUNDARY_ORDER);
    return result;
  }

  private boolean optionalBoolean(String name, boolean fallback) {
    String value = System.getenv(name);
    if (value == null || value.trim().isEmpty()) {
      return fallback;
    }
    if ("true".equalsIgnoreCase(value) || "1".equals(value)) {
      return true;
    }
    if ("false".equalsIgnoreCase(value) || "0".equals(value)) {
      return false;
    }
    throw new IllegalArgumentException(
        "Environment variable must be true or false: " + name + "=" + value);
  }
}
