# =============================================================================
# Step Functions — Member Experience Orchestration Workflow
#
# Flow:
#   Fetch Profile → Check if reanalysis needed
#     YES → Analyze with Bedrock → Write Results → Success
#     NO  → Return cached results → Success
#
# Input:  { "memberId": "M-10042", "forceReanalyze": false }
# =============================================================================

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project_name}-orchestration-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_sfn_state_machine" "member_orchestration" {
  name     = "${var.project_name}-orchestration-${var.environment}"
  role_arn = aws_iam_role.sfn_role.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  definition = jsonencode({
    Comment = "Unified Member Experience Orchestration with smart caching"
    StartAt = "FetchProfile"
    States = {

      # --- Step 1: Fetch all member data + check staleness ---
      FetchProfile = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.fetch_profile.arn
          Payload = {
            "memberId.$"       = "$.memberId"
            "forceReanalyze.$" = "$.forceReanalyze"
            "userMessage.$"    = "$.userMessage"
            "sessionId.$"      = "$.sessionId"
          }
        }
        ResultPath = "$.fetchResult"
        ResultSelector = {
          "memberId.$"        = "$.Payload.memberId"
          "profile.$"         = "$.Payload.profile"
          "needsReanalysis.$" = "$.Payload.needsReanalysis"
          "cachedResult.$"    = "$.Payload.cachedResult"
          "chatHistory.$"     = "$.Payload.chatHistory"
          "userMessage.$"     = "$.Payload.userMessage"
          "sessionId.$"       = "$.Payload.sessionId"
          "error.$"           = "$.Payload.error"
        }
        Retry = [{
          ErrorEquals     = ["States.TaskFailed", "Lambda.ServiceException"]
          IntervalSeconds = 2
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "CheckProfileExists"
      }

      # --- Check if profile was found ---
      CheckProfileExists = {
        Type = "Choice"
        Choices = [{
          Variable  = "$.fetchResult.profile"
          IsPresent = true
          Next      = "CheckProfileNotNull"
        }]
        Default = "ProfileNotFound"
      }

      CheckProfileNotNull = {
        Type = "Choice"
        Choices = [{
          Variable = "$.fetchResult.profile"
          IsNull   = false
          Next     = "CheckNeedsReanalysis"
        }]
        Default = "ProfileNotFound"
      }

      ProfileNotFound = {
        Type  = "Fail"
        Error = "ProfileNotFound"
        Cause = "No member profile found in DynamoDB"
      }

      # --- Decision: reanalyze or return cached? ---
      CheckNeedsReanalysis = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.fetchResult.needsReanalysis"
          BooleanEquals = true
          Next          = "AnalyzeProfile"
        }]
        Default = "ReturnCached"
      }

      # --- Path A: Return cached AI results (no Bedrock call) ---
      ReturnCached = {
        Type = "Pass"
        Parameters = {
          "memberId.$"  = "$.fetchResult.memberId"
          "result.$"    = "$.fetchResult.cachedResult"
          "status"      = "cached"
          "message"     = "Profile unchanged since last analysis. Returning cached AI results."
        }
        Next = "Success"
      }

      # --- Path B: Run Bedrock analysis ---
      # Step 2: Send profile to Bedrock for AI analysis
      AnalyzeProfile = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.analyze_profile.arn
          Payload = {
            "memberId.$"    = "$.fetchResult.memberId"
            "profile.$"     = "$.fetchResult.profile"
            "chatHistory.$" = "$.fetchResult.chatHistory"
            "userMessage.$" = "$.fetchResult.userMessage"
            "sessionId.$"   = "$.fetchResult.sessionId"
          }
        }
        ResultPath = "$.analyzeResult"
        ResultSelector = {
          "memberId.$" = "$.Payload.memberId"
          "profile.$"  = "$.Payload.profile"
          "aiResult.$" = "$.Payload.aiResult"
        }
        Retry = [{
          ErrorEquals     = ["States.TaskFailed", "Lambda.ServiceException"]
          IntervalSeconds = 3
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "WriteResults"
      }

      # Step 3: Write AI results back to DynamoDB
      WriteResults = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.write_results.arn
          Payload = {
            "memberId.$"    = "$.analyzeResult.memberId"
            "profile.$"     = "$.analyzeResult.profile"
            "aiResult.$"    = "$.analyzeResult.aiResult"
            "userMessage.$" = "$.fetchResult.userMessage"
            "sessionId.$"   = "$.fetchResult.sessionId"
          }
        }
        ResultPath = "$.writeResult"
        ResultSelector = {
          "memberId.$"       = "$.Payload.memberId"
          "decisionId.$"     = "$.Payload.decisionId"
          "sessionId.$"      = "$.Payload.sessionId"
          "recordsWritten.$" = "$.Payload.recordsWritten"
          "careGaps.$"       = "$.Payload.careGaps"
          "interventions.$"  = "$.Payload.interventions"
          "agentResponse.$"  = "$.Payload.agentResponse"
          "status.$"         = "$.Payload.status"
        }
        Retry = [{
          ErrorEquals     = ["States.TaskFailed", "Lambda.ServiceException"]
          IntervalSeconds = 2
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "ExecuteWorkflows"
      }

      # Step 4: Route interventions to downstream systems (SNS)
      ExecuteWorkflows = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.execute_workflows.arn
          Payload = {
            "memberId.$" = "$.analyzeResult.memberId"
            "aiResult.$" = "$.analyzeResult.aiResult"
            "sessionId.$" = "$.fetchResult.sessionId"
          }
        }
        ResultPath = "$.workflowResult"
        ResultSelector = {
          "memberId.$"          = "$.Payload.memberId"
          "workflowsExecuted.$" = "$.Payload.workflowsExecuted"
          "workflowsFailed.$"   = "$.Payload.workflowsFailed"
          "results.$"           = "$.Payload.results"
          "status.$"            = "$.Payload.status"
        }
        Retry = [{
          ErrorEquals     = ["States.TaskFailed", "Lambda.ServiceException"]
          IntervalSeconds = 2
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "Success"
      }

      # --- Success ---
      Success = {
        Type = "Succeed"
      }

      # --- Error Handler ---
      HandleError = {
        Type  = "Fail"
        Error = "OrchestrationFailed"
        Cause = "An error occurred during member profile orchestration"
      }
    }
  })

  tags = {
    Name = "${var.project_name}-orchestration"
    Role = "Member Experience Orchestration Workflow"
  }
}
