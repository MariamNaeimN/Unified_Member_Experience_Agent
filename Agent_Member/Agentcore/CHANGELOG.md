# Changelog

All notable changes to the MemberXP AgentCore Runtime will be documented in this file.

## [1.1.0] - 2026-04-30

### Added
- Anti-hallucination system prompt with strict data accuracy rules
- Temperature set to 0.0 for deterministic responses
- Pre-computed claimsInsight with total cost in analyze Lambda
- Enhanced care gaps with `details` and `actionItems` fields

### Changed
- Improved tool search with Limit=50 for better performance
- Updated system prompt to enforce data-only responses
- Better medication adherence flagging (80% threshold)

### Fixed
- Fixed run-all-members.ps1 encoding issue (UTF-8 BOM)
- Fixed claimsInsight not including total cost

## [1.0.0] - 2026-04-28

### Added
- Initial AgentCore Runtime deployment
- 12 MCP tools for member health data access
- Streaming response with `converse_stream` API
- Active member tracking for pronoun resolution
- CLI interactive mode with streaming output
- HTTP server mode for API integration
- Tool-use loop with up to 6 rounds per question

### Tools
- `search_member` - Find members by name or ID
- `get_member_profile` - Demographics, plan, clinical data
- `get_member_analysis` - AI clinical analysis, risk assessment
- `get_member_conditions` - Active diagnoses with ICD-10 codes
- `get_member_medications` - Medications with adherence %
- `get_member_claims` - Claims history with costs
- `get_member_care_events` - Visits, ER, hospitalizations
- `get_member_care_gaps` - Open care gaps with priority
- `get_member_interventions` - Triggered workflow actions
- `get_member_notifications` - Alerts from AI analysis
- `get_all_members_summary` - All members overview
- `get_high_risk_members` - Members above risk threshold
