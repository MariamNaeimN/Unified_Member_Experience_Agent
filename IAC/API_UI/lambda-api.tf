# =============================================================================
# Lambda: chat-api — REMOVED
# =============================================================================
# The chat-api Lambda has been replaced by WebSocket Lambda functions:
#   - lambda-ws-connect.tf  — Connection authentication ($connect)
#   - lambda-ws-disconnect.tf — Connection cleanup ($disconnect)
#   - lambda-ws-chat.tf    — Chat streaming (sendMessage route)
#   - lambda-ws-api.tf     — Non-chat operations (getMembers, getMemberProfile, etc.)
#
# The Lambda logic has been moved to these new files.
# =============================================================================
