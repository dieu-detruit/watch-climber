"""Read back Apple's processing/compliance status without exposing credentials."""
import os
import sys
import time

import jwt
import requests


def get(path, params=None):
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 120,
         "aud": "appstoreconnect-v1"},
        os.environ["APP_STORE_CONNECT_PRIVATE_KEY"], algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]},
    )
    response = requests.get(
        "https://api.appstoreconnect.apple.com/v1/" + path,
        params=params, headers={"Authorization": "Bearer " + token}, timeout=30,
    )
    if not response.ok:
        raise RuntimeError(f"Apple status query failed: HTTP {response.status_code}")
    return response.json()


def main():
    apps = get("apps", {"filter[bundleId]": os.environ["APP_BUNDLE_ID"]})["data"]
    if len(apps) != 1:
        raise RuntimeError("Expected exactly one App Store Connect app")
    app_id = apps[0]["id"]
    if app_id != "6820979760":
        raise RuntimeError("Bundle ID does not match the confirmed Watch Climber App Store Connect app")
    if "--check-app-only" in sys.argv:
        print("Confirmed Watch Climber App Store Connect app 6820979760")
        return
    version = os.environ["BUILD_NUMBER"]
    # Upload success and TestFlight eligibility are separate. Allow processing time.
    for attempt in range(60):
        result = get("builds", {"filter[app]": app_id, "filter[version]": version,
                                "include": "buildBetaDetail"})
        builds = result["data"]
        if builds:
            attributes = builds[0]["attributes"]
            state = attributes["processingState"]
            if state in ("FAILED", "INVALID"):
                raise RuntimeError(f"Apple rejected build {version}: {state}")
            if state == "VALID":
                if attributes.get("usesNonExemptEncryption") is not False:
                    raise RuntimeError("Apple has not accepted the exempt-only encryption declaration")
                details = [item["attributes"] for item in result.get("included", [])
                           if item["type"] == "buildBetaDetails"]
                internal_state = details[0].get("internalBuildState") if details else None
                if internal_state in ("READY_FOR_BETA_TESTING", "IN_BETA_TESTING"):
                    print(f"Build {version}: VALID, usesNonExemptEncryption=false, {internal_state}", flush=True)
                    groups = get(f"apps/{app_id}/betaGroups")["data"]
                    internal = [g["attributes"] for g in groups if g["attributes"].get("isInternalGroup")]
                    print("Internal groups:", [{"name": g["name"], "automaticDistribution": g.get("hasAccessToAllBuilds")} for g in internal], flush=True)
                    return
                print(f"Build {version}: {state}, internal state={internal_state}", flush=True)
        if attempt % 6 == 0:
            print(f"Waiting for Apple to process build {version} ({attempt * 10}s)", flush=True)
        time.sleep(10)
    raise RuntimeError("Apple processing not confirmed within 10 minutes; check TestFlight")


if __name__ == "__main__":
    main()
