# Register all LINE chatbot tools with the ToolRegistry.
# Add new tools here as they are created.
#
# Uses `to_prepare` instead of `after_initialize` because Rails development
# mode reloads autoloaded classes on each request, which wipes ToolRegistry's
# @registry instance variable. `to_prepare` re-runs after every reload,
# keeping the registry populated. In production (eager loading), it runs once.
Rails.application.config.to_prepare do
  Line::ToolRegistry.register(
    "student_lookup",
    definition: Line::Tools::StudentLookupTool::DEFINITION,
    handler: Line::Tools::StudentLookupTool,
    permission: "students.read_minimal"
  )

  Line::ToolRegistry.register(
    "staff_lookup",
    definition: Line::Tools::StaffLookupTool::DEFINITION,
    handler: Line::Tools::StaffLookupTool,
    permission: "courses.read"
  )

  Line::ToolRegistry.register(
    "course_lookup",
    definition: Line::Tools::CourseLookupTool::DEFINITION,
    handler: Line::Tools::CourseLookupTool,
    permission: "courses.read"
  )

  Line::ToolRegistry.register(
    "course_offering_lookup",
    definition: Line::Tools::CourseOfferingLookupTool::DEFINITION,
    handler: Line::Tools::CourseOfferingLookupTool,
    permission: "courses.read"
  )

  Line::ToolRegistry.register(
    "search",
    definition: Line::Tools::SearchTool::DEFINITION,
    handler: Line::Tools::SearchTool,
    permission: "courses.read"
  )

  Line::ToolRegistry.register(
    "grade_distribution",
    definition: Line::Tools::GradeDistributionTool::DEFINITION,
    handler: Line::Tools::GradeDistributionTool,
    permission: "grades.read"
  )

  Line::ToolRegistry.register(
    "cohort_gpa",
    definition: Line::Tools::CohortGpaTool::DEFINITION,
    handler: Line::Tools::CohortGpaTool,
    permission: "grades.read"
  )

  Line::ToolRegistry.register(
    "cohort_ranking",
    definition: Line::Tools::CohortRankingTool::DEFINITION,
    handler: Line::Tools::CohortRankingTool,
    permission: "grades.read"
  )

  Line::ToolRegistry.register(
    "student_grades",
    definition: Line::Tools::StudentGradesTool::DEFINITION,
    handler: Line::Tools::StudentGradesTool,
    permission: "students.read_minimal"
  )

  Line::ToolRegistry.register(
    "course_enrollment",
    definition: Line::Tools::CourseEnrollmentTool::DEFINITION,
    handler: Line::Tools::CourseEnrollmentTool,
    permission: "grades.read"
  )

  Line::ToolRegistry.register(
    "semester_overview",
    definition: Line::Tools::SemesterOverviewTool::DEFINITION,
    handler: Line::Tools::SemesterOverviewTool,
    permission: "courses.read"
  )

  Line::ToolRegistry.register(
    "room_schedule",
    definition: Line::Tools::RoomScheduleTool::DEFINITION,
    handler: Line::Tools::RoomScheduleTool,
    permission: "courses.read"
  )

  Line::ToolRegistry.register(
    "missing_enrollments",
    definition: Line::Tools::MissingEnrollmentsTool::DEFINITION,
    handler: Line::Tools::MissingEnrollmentsTool,
    permission: "grades.read"
  )

  # Not in the roles/permissions plan's table (program_lookup was added to the
  # registry after that table was drafted) — courses.read matches its sibling
  # catalog-lookup tools (course_lookup, staff_lookup, etc.) and the web UI's
  # own gate on ProgramsController/ProgramGroupsController, which use the same
  # permission for the same data.
  Line::ToolRegistry.register(
    "program_lookup",
    definition: Line::Tools::ProgramLookupTool::DEFINITION,
    handler: Line::Tools::ProgramLookupTool,
    permission: "courses.read"
  )
end
