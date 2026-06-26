"""End-to-end API tests (no network: scraping endpoints are not exercised)."""
from conftest import register


def test_register_requires_consent(client):
    r = register(client, "a@a.io", consent=False)
    assert r.status_code == 400


def test_register_password_policy(client):
    r = register(client, "a@a.io", pw="short")
    assert r.status_code == 400


def test_register_invalid_email(client):
    r = register(client, "not-an-email")
    assert r.status_code == 400


def test_register_login_and_me(client):
    r = register(client, "sarah@a.io")
    assert r.status_code == 200
    token = r.json()["token"]
    me = client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200 and me.json()["email"] == "sarah@a.io"


def test_cv_upload_extracts_skills(client):
    token = register(client, "s@a.io").json()["token"]
    h = {"Authorization": f"Bearer {token}"}
    r = client.post("/cv/upload", headers=h,
                    data={"text": "Python developer with django, aws and machine learning"})
    assert r.status_code == 200
    assert {"python", "django", "aws", "machine learning"} <= set(r.json()["skills"])


def test_gdpr_export_and_delete(client):
    token = register(client, "g@a.io").json()["token"]
    h = {"Authorization": f"Bearer {token}"}
    client.post("/cv/upload", headers=h, data={"text": "python aws"})
    exp = client.get("/me/export", headers=h)
    assert exp.status_code == 200 and exp.json()["user"]["consent_at"]
    assert client.delete("/me", headers=h).json()["deleted"] is True
    assert client.get("/me", headers=h).status_code == 401


def test_talents_gated_until_granted(client):
    rt = register(client, "rh@a.io", role="recruiter").json()["token"]
    h = {"Authorization": f"Bearer {rt}"}
    assert client.get("/talents", headers=h).status_code == 403
    client.post("/recruiter/request-access", headers=h, json={"company": "ACME"})
    assert client.get("/talents", headers=h).status_code == 403  # still pending
    g = client.post("/admin/grant-access", params={"email": "rh@a.io"},
                    headers={"x-admin-token": "test-admin-token"})
    assert g.status_code == 200
    assert client.get("/talents", headers=h).status_code == 200


def test_admin_token_required(client):
    register(client, "rh@a.io", role="recruiter")
    assert client.post("/admin/grant-access", params={"email": "rh@a.io"}).status_code == 403
    assert client.post("/admin/grant-access", params={"email": "rh@a.io"},
                       headers={"x-admin-token": "wrong"}).status_code == 403


def test_placement_request_flow(client):
    # freelance with a CV
    ft = register(client, "free@a.io").json()["token"]
    client.post("/cv/upload", headers={"Authorization": f"Bearer {ft}"},
                data={"text": "python django aws"})
    # recruiter granted access
    rt = register(client, "rh@a.io", role="recruiter").json()["token"]
    h = {"Authorization": f"Bearer {rt}"}
    client.post("/recruiter/request-access", headers=h, json={"company": "ACME", "phone": "06"})
    client.post("/admin/grant-access", params={"email": "rh@a.io"},
                headers={"x-admin-token": "test-admin-token"})
    cid = client.get("/talents", headers=h).json()["candidates"][0]["candidate_id"]
    # request placement
    r = client.post(f"/talents/{cid}/request", headers=h, json={"message": "mission 6 mois"})
    assert r.status_code == 200 and r.json()["status"] == "requested"
    # admin sees it
    pl = client.get("/admin/placement-requests", headers={"x-admin-token": "test-admin-token"})
    assert pl.status_code == 200 and len(pl.json()["placement_requests"]) == 1


def test_privacy_policy_public(client):
    assert client.get("/legal/privacy").status_code == 200
