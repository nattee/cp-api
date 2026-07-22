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
    handler: Line::Tools::StudentLookupTool
  )

  Line::ToolRegistry.register(
    "staff_lookup",
    definition: Line::Tools::StaffLookupTool::DEFINITION,
    handler: Line::Tools::StaffLookupTool
  )

  Line::ToolRegistry.register(
    "course_lookup",
    definition: Line::Tools::CourseLookupTool::DEFINITION,
    handler: Line::Tools::CourseLookupTool
  )

  Line::ToolRegistry.register(
    "course_offering_lookup",
    definition: Line::Tools::CourseOfferingLookupTool::DEFINITION,
    handler: Line::Tools::CourseOfferingLookupTool
  )

  Line::ToolRegistry.register(
    "search",
    definition: Line::Tools::SearchTool::DEFINITION,
    handler: Line::Tools::SearchTool
  )

  Line::ToolRegistry.register(
    "grade_distribution",
    definition: Line::Tools::GradeDistributionTool::DEFINITION,
    handler: Line::Tools::GradeDistributionTool
  )

  Line::ToolRegistry.register(
    "cohort_gpa",
    definition: Line::Tools::CohortGpaTool::DEFINITION,
    handler: Line::Tools::CohortGpaTool
  )

  Line::ToolRegistry.register(
    "cohort_ranking",
    definition: Line::Tools::CohortRankingTool::DEFINITION,
    handler: Line::Tools::CohortRankingTool
  )

  Line::ToolRegistry.register(
    "student_grades",
    definition: Line::Tools::StudentGradesTool::DEFINITION,
    handler: Line::Tools::StudentGradesTool
  )

  Line::ToolRegistry.register(
    "course_enrollment",
    definition: Line::Tools::CourseEnrollmentTool::DEFINITION,
    handler: Line::Tools::CourseEnrollmentTool
  )

  Line::ToolRegistry.register(
    "semester_overview",
    definition: Line::Tools::SemesterOverviewTool::DEFINITION,
    handler: Line::Tools::SemesterOverviewTool
  )

  Line::ToolRegistry.register(
    "room_schedule",
    definition: Line::Tools::RoomScheduleTool::DEFINITION,
    handler: Line::Tools::RoomScheduleTool
  )

  Line::ToolRegistry.register(
    "missing_enrollments",
    definition: Line::Tools::MissingEnrollmentsTool::DEFINITION,
    handler: Line::Tools::MissingEnrollmentsTool
  )

  Line::ToolRegistry.register(
    "program_lookup",
    definition: Line::Tools::ProgramLookupTool::DEFINITION,
    handler: Line::Tools::ProgramLookupTool
  )
end
