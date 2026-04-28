environment         = "dev"
project_name        = "member-experience"
aws_region          = "us-east-1"
dynamodb_table_name = "member-experience-unified-profile-dev"
# Get from Data Stack:  terraform output -raw dynamodb_table_arn
dynamodb_table_arn  = ""
# Get from Orch Stack:  terraform output -raw step_function_arn
step_function_arn   = ""
