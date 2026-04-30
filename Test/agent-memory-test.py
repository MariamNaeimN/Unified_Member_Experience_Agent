"""
Agent Memory Test — Tests conversation memory across multiple turns
Verifies the agent correctly tracks member context when:
  1. User asks about a member by name
  2. User asks follow-up with pronouns ("his", "her")
  3. User switches to a different member
  4. User asks follow-up about the NEW member
  5. User asks by member ID
  6. User asks "what are the next steps"

Run: python Test/agent-memory-test.py
"""

import sys
import os
import json
import time

# Add Agent_Member to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "Agent_Member"))

from agent import run_agent, _active_member

# ── Test Scenarios ───────────────────────────────────────────────────────────

TEST_CONVERSATIONS = [
    # ── Conversation 1: Name lookup + follow-ups ──
    {
        "title": "Member by Name + Follow-up Pronouns",
        "questions": [
            "Tell me about John Smith",
            "What are his conditions?",
            "And his medications?",
            "What are the next steps?",
        ],
        "expect_member_tracked": True,
    },
    # ── Conversation 2: Switch to different member ──
    {
        "title": "Switch to Different Member by Name",
        "questions": [
            "Tell me about Maria Garcia",
            "What are her care gaps?",
        ],
        "expect_member_tracked": True,
    },
    # ── Conversation 3: Member by ID ──
    {
        "title": "Member by ID + Follow-up",
        "questions": [
            "Show me the profile for M-10044",
            "What are his claims?",
        ],
        "expect_member_tracked": True,
    },
    # ── Conversation 4: High risk members (no specific member) ──
    {
        "title": "Population Query (No Member Context)",
        "questions": [
            "Who are the high risk members?",
        ],
        "expect_member_tracked": False,
    },
    # ── Conversation 5: All members summary ──
    {
        "title": "All Members Summary",
        "questions": [
            "Show me all members",
        ],
        "expect_member_tracked": False,
    },
]


def run_test():
    """Run all test conversations and report results."""
    print("\n" + "=" * 70)
    print("  🧪 Agent Memory Test — Testing Conversation Context Tracking")
    print("=" * 70)

    total_questions = 0
    total_success = 0
    total_errors = 0

    for conv_idx, conv in enumerate(TEST_CONVERSATIONS):
        print(f"\n{'─' * 70}")
        print(f"  📋 Test {conv_idx + 1}: {conv['title']}")
        print(f"{'─' * 70}")

        # Reset memory between conversations
        _active_member["memberId"] = None
        _active_member["name"] = None
        history = []

        for q_idx, question in enumerate(conv["questions"]):
            total_questions += 1
            print(f"\n  💬 Q{q_idx + 1}: {question}")

            # Show active member before the question
            if _active_member["memberId"]:
                print(f"  📌 Active member before: {_active_member['name']} ({_active_member['memberId']})")
            else:
                print(f"  📌 Active member before: None")

            try:
                start = time.time()
                answer, history = run_agent(question, history)
                elapsed = time.time() - start

                # Show active member after the question
                if _active_member["memberId"]:
                    print(f"  📌 Active member after:  {_active_member['name']} ({_active_member['memberId']})")
                else:
                    print(f"  📌 Active member after:  None")

                # Truncate long answers for readability
                answer_preview = answer[:300] + "..." if len(answer) > 300 else answer
                print(f"  🤖 Answer ({elapsed:.1f}s): {answer_preview}")

                # Check for errors in the answer
                if "error" in answer.lower() and "not found" in answer.lower():
                    print(f"  ❌ FAIL — Agent returned an error")
                    total_errors += 1
                elif "which member" in answer.lower() or "please specify" in answer.lower():
                    print(f"  ❌ FAIL — Agent lost context (asked which member)")
                    total_errors += 1
                else:
                    print(f"  ✅ OK")
                    total_success += 1

            except Exception as e:
                print(f"  ❌ ERROR: {str(e)}")
                total_errors += 1

    # ── Summary ──
    print(f"\n{'=' * 70}")
    print(f"  📊 Results: {total_success}/{total_questions} passed, {total_errors} errors")
    print(f"{'=' * 70}\n")

    return total_errors == 0


if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
