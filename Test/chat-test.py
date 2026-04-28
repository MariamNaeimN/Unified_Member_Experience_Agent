"""
Member Experience Agent — Interactive Chat Test
Authenticates via Cognito, then lets you chat with the agent.
"""
import boto3
import requests
import json
import sys
import os

# --- Config ---
REGION = "us-east-1"
API_URL = "https://87slbidh3k.execute-api.us-east-1.amazonaws.com/dev"
CLIENT_ID = "3ru1bf0hq0027uc49v8d38mvtu"
USER_POOL_ID = "us-east-1_vvcOmWFgl"
USERNAME = "sarah@example.com"
PASSWORD = "TestPass123!"


def get_token():
    """Authenticate with Cognito and return JWT token."""
    client = boto3.client("cognito-idp", region_name=REGION)
    try:
        resp = client.initiate_auth(
            ClientId=CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": USERNAME, "PASSWORD": PASSWORD},
        )
        return resp["AuthenticationResult"]["IdToken"]
    except client.exceptions.NotAuthorizedException:
        print("[!] Invalid credentials. Check USERNAME/PASSWORD.")
        sys.exit(1)
    except Exception as e:
        print(f"[!] Auth error: {e}")
        sys.exit(1)


def chat(token, member_id, message, session_id=None):
    """Send a chat message to the agent."""
    headers = {"Authorization": token, "Content-Type": "application/json"}
    body = {"memberId": member_id, "message": message}
    if session_id:
        body["sessionId"] = session_id

    print(f"\n{'='*60}")
    print(f"  You: {message}")
    print(f"  Member: {member_id}")
    print(f"{'='*60}")
    print("  [Waiting for agent... this takes ~30-50 seconds]")

    try:
        resp = requests.post(f"{API_URL}/chat", headers=headers, json=body, timeout=90)
        data = resp.json()

        if resp.status_code == 200:
            print(f"\n{'─'*60}")
            print(f"  Agent Response (Decision: {data.get('decisionId', 'N/A')})")
            print(f"  Care Gaps: {data.get('careGaps', 0)} | Interventions: {data.get('interventions', 0)}")
            print(f"  Cached: {data.get('cached', False)}")
            print(f"{'─'*60}")
            print(f"\n{data.get('agentResponse', 'No response')}\n")
            return data.get("sessionId", "")
        else:
            print(f"\n[!] Error {resp.status_code}: {data}")
            return session_id
    except requests.exceptions.Timeout:
        print("\n[!] Request timed out (>90s). The agent may still be processing.")
        return session_id
    except Exception as e:
        print(f"\n[!] Request failed: {e}")
        return session_id


def search_members(token, query):
    """Search for members."""
    headers = {"Authorization": token}
    resp = requests.get(f"{API_URL}/members", headers=headers, params={"search": query}, timeout=15)
    data = resp.json()
    print(f"\n  Search results for '{query}':")
    for m in data.get("members", []):
        print(f"    {m['memberId']} — {m['firstName']} {m['lastName']} ({m['planName']}, {m['coverageStatus']})")
    if not data.get("members"):
        print("    No members found.")
    return data


def get_notifications(token, member_id=None):
    """Get notifications."""
    headers = {"Authorization": token}
    params = {}
    if member_id:
        params["memberId"] = member_id
    resp = requests.get(f"{API_URL}/notifications", headers=headers, params=params, timeout=15)
    data = resp.json()
    print(f"\n  Notifications (unread: {data.get('unread', 0)}):")
    for n in data.get("notifications", []):
        status_icon = "🔴" if n["status"] == "unread" else "✅"
        print(f"    {status_icon} {n['title']} — {n['priority']}")
    if not data.get("notifications"):
        print("    No notifications.")
    return data


def main():
    print("\n" + "=" * 60)
    print("  Member Experience Agent — Chat Test")
    print("=" * 60)

    # Authenticate
    print("\n  Authenticating as Sarah...")
    token = get_token()
    print("  ✓ Authenticated\n")

    session_id = None
    current_member = None

    print("  Commands:")
    print("    /search <query>     — Search members (e.g., /search John Smith)")
    print("    /member <id>        — Set active member (e.g., /member M-10042)")
    print("    /notifications      — View notifications")
    print("    /profile            — View current member profile")
    print("    /quit               — Exit")
    print("    <anything else>     — Chat with the agent about the active member")
    print()

    while True:
        try:
            user_input = input("  Sarah > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  Goodbye!")
            break

        if not user_input:
            continue

        if user_input.lower() in ("/quit", "/exit", "/q"):
            print("  Goodbye!")
            break

        elif user_input.lower().startswith("/search ") or user_input.lower().startswith("search "):
            query = user_input.split(" ", 1)[1].strip() if " " in user_input else ""
            search_members(token, query)

        elif user_input.lower().startswith("/member ") or user_input.lower().startswith("member "):
            parts = user_input.split(" ", 1)
            current_member = parts[1].strip().upper() if len(parts) > 1 else ""
            if not current_member.startswith("M-"):
                current_member = "M-" + current_member
            print(f"  ✓ Active member set to {current_member}")
            session_id = None

        elif user_input.lower() in ("/notifications", "notifications", "notification", "/notification"):
            get_notifications(token, current_member)

        elif user_input.lower() in ("/profile", "profile"):
            if not current_member:
                print("  [!] Set a member first: /member M-10042")
                continue
            headers = {"Authorization": token}
            resp = requests.get(f"{API_URL}/members/profile", headers=headers, params={"memberId": current_member}, timeout=15)
            data = resp.json()
            member = data.get("member", {})
            patient = data.get("patient", {})
            print(f"\n  Profile: {member.get('firstName', '')} {member.get('lastName', '')} ({current_member})")
            print(f"  DOB: {member.get('dob', '')} | Plan: {member.get('planName', '')} | Risk: {patient.get('riskScore', 'N/A')}/100")
            print(f"  Conditions: {len(data.get('conditions', []))} | Claims: {len(data.get('claims', []))} | Meds: {len(data.get('pharmacy', []))}")

        else:
            # Extract member ID from message if present
            import re
            match = re.search(r"M-\d{5}", user_input.upper())
            if match:
                current_member = match.group()
                print(f"  ✓ Detected member {current_member}")
                session_id = None
            elif not current_member:
                print("  [!] Set a member first: /member M-10042")
                continue

            session_id = chat(token, current_member, user_input, session_id)


if __name__ == "__main__":
    main()
