#!/usr/bin/env python3
"""Serve the local Rabbita surface through the authenticated company service.

The browser-side Rabbita HTTP helper intentionally has no arbitrary-header
API. This private gateway keeps the service bearer token on the server,
establishes an in-memory HttpOnly session, signs its actor assertion, converts
a JSON ``idempotency_key`` field into the required ``Idempotency-Key`` header,
and forwards only the company
read/expense (including draft update/void)/contract/payment-application/tender/source-tender-alias/supplier/supplier-provider/supplier-risk/split/sales/delivery/
loan/fund/project-plan/reports paths. Fund and project-plan commands are local
planning projections only;
cash release, accounting, and tax effects remain separate.
The default fixture mode is development-only. An opt-in trusted-upstream mode
accepts a short-lived HMAC-signed identity assertion, verifies that the source
PostgreSQL profile exists and is enabled, and binds the session actor to that
source user. It still needs a managed session store, issuer/audience policy,
rotation, and owner approval before production deployment.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import http.client
import json
import os
import re
import secrets
import sys
import time
from http.cookies import SimpleCookie
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import RLock
from typing import Any
from urllib.parse import quote, urlparse


class GatewayError(RuntimeError):
    """A local gateway configuration or forwarding error."""


EXPENSE_PATH_PREFIX = "/api/company/expenses"
BUDGET_CHECK_PATH = "/api/company/budget-check"
CONTRACT_PATH_PREFIX = "/api/company/contracts"
PAYMENT_APPLICATION_PATH_PREFIX = "/api/company/payment-applies"
TENDER_PATH_PREFIX = "/api/company/tenders"
SOURCE_TENDER_PATH_PREFIX = "/api/company/source/tender"
SUPPLIER_PATH_PREFIX = "/api/company/suppliers"
TENDER_SPLIT_PATH_PREFIX = "/api/company/tender-splits"
SALES_PATH_PREFIX = "/api/company/sales"
RECEIVABLE_PATH_PREFIX = "/api/company/receivables"
DELIVERY_PATH_PREFIX = "/api/company/delivery"
LOAN_PATH_PREFIX = "/api/company/loans"
FUND_PATH_PREFIX = "/api/company/fund"
PLAN_PATH_PREFIX = "/api/company/plan"
MARKETING_PATH_PREFIX = "/api/company/marketing"
INVOICE_PATH_PREFIX = "/api/company/source/invoice"
SOURCE_COST_PAYMENT_PATH_PREFIX = "/api/company/source/cost/payment-applies"
SOURCE_COST_DYNAMIC_PATH_PREFIX = "/api/company/cost/dynamic-cost"
READ_PATH_PREFIX = "/api/"
SESSION_COOKIE = "moonproj_session"
TRUSTED_IDENTITY_HEADER = "X-Moonproj-Identity"
TRUSTED_IDENTITY_TIMESTAMP_HEADER = "X-Moonproj-Identity-Timestamp"
TRUSTED_IDENTITY_SIGNATURE_HEADER = "X-Moonproj-Identity-Signature"
TRUSTED_IDENTITY_MAX_SKEW_SECONDS = 60


def verify_trusted_identity(
    user_code: str,
    timestamp: str,
    signature: str,
    secret: str,
    *,
    now: int | None = None,
) -> bool:
    """Verify a short-lived upstream identity assertion without logging it."""

    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", user_code):
        return False
    if not re.fullmatch(r"[0-9]{1,20}", timestamp) or not re.fullmatch(r"[0-9a-f]{64}", signature):
        return False
    try:
        issued_at = int(timestamp)
    except ValueError:
        return False
    current = int(time.time()) if now is None else now
    if abs(current - issued_at) > TRUSTED_IDENTITY_MAX_SKEW_SECONDS:
        return False
    expected = hmac.new(
        secret.encode("utf-8"),
        f"{user_code}:{timestamp}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(signature, expected)


def proxy_request(
    *,
    service_host: str,
    service_port: int,
    token: str,
    method: str,
    path: str,
    body: bytes | None,
    idempotency_key: str | None,
    actor_id: str,
    actor_signing_secret: str,
) -> tuple[int, str, bytes]:
    connection = http.client.HTTPConnection(service_host, service_port, timeout=15)
    headers = {
        "Authorization": "Bearer " + token,
        "X-Forwarded-Proto": "https",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = str(len(body))
    if idempotency_key is not None:
        headers["Idempotency-Key"] = idempotency_key
    headers["X-Moonproj-Actor"] = actor_id
    headers["X-Moonproj-Actor-Signature"] = hmac.new(
        actor_signing_secret.encode("utf-8"),
        actor_id.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    try:
        connection.request(method, path, body=body, headers=headers)
        result = connection.getresponse()
        response_body = result.read()
        content_type = result.getheader("Content-Type", "application/json; charset=utf-8")
        return result.status, content_type, response_body
    except (OSError, TimeoutError) as error:
        raise GatewayError(f"company service forwarding failed: {error}") from error
    finally:
        connection.close()


def response(
    handler: SimpleHTTPRequestHandler,
    status: int,
    payload: Any,
    headers: dict[str, str] | None = None,
) -> None:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    for name, value in (headers or {}).items():
        handler.send_header(name, value)
    handler.end_headers()
    handler.wfile.write(body)


def handler_factory(
    *,
    public_dir: Path | None,
    service_host: str,
    service_port: int,
    token: str,
    dev_user: str,
    dev_password: str,
    actor_id: str,
    actor_signing_secret: str,
    trusted_identity_secret: str | None,
) -> type[SimpleHTTPRequestHandler]:
    sessions: dict[str, str] = {}
    session_lock = RLock()

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, request, client_address, server):
            super().__init__(request, client_address, server, directory=str(public_dir) if public_dir else None)

        def _session_actor(self) -> str | None:
            cookie = SimpleCookie()
            try:
                cookie.load(self.headers.get("Cookie", ""))
            except Exception:
                return None
            morsel = cookie.get(SESSION_COOKIE)
            if morsel is None or not morsel.value:
                return None
            with session_lock:
                return sessions.get(morsel.value)

        def _trusted_identity_actor(self) -> str | None:
            if trusted_identity_secret is None:
                return None
            user_code = self.headers.get(TRUSTED_IDENTITY_HEADER, "").strip()
            timestamp = self.headers.get(TRUSTED_IDENTITY_TIMESTAMP_HEADER, "").strip()
            signature = self.headers.get(TRUSTED_IDENTITY_SIGNATURE_HEADER, "").strip().lower()
            if not verify_trusted_identity(
                user_code,
                timestamp,
                signature,
                trusted_identity_secret,
            ):
                return None
            try:
                status, _content_type, body = proxy_request(
                    service_host=service_host,
                    service_port=service_port,
                    token=token,
                    method="GET",
                    path="/api/company/auth/me?userCode=" + quote(user_code, safe=""),
                    body=None,
                    idempotency_key=None,
                    actor_id=user_code,
                    actor_signing_secret=actor_signing_secret,
                )
                payload = json.loads(body.decode("utf-8"))
                profile = payload.get("data") if isinstance(payload, dict) else None
                if status != 200 or not isinstance(profile, dict) or profile.get("enabled") is not True:
                    return None
            except (GatewayError, OSError, UnicodeDecodeError, json.JSONDecodeError):
                return None
            return user_code

        def _establish_session(self, actor: str, identity_source: str) -> None:
            session_token = secrets.token_urlsafe(32)
            with session_lock:
                sessions[session_token] = actor
            cookie_flags = "HttpOnly; Path=/; SameSite=Strict"
            if identity_source == "trusted_upstream":
                cookie_flags += "; Secure; Max-Age=900"
            response(
                self,
                200,
                {
                    "authenticated": True,
                    "actor_id": actor,
                    "identity_source": identity_source,
                },
                {"Set-Cookie": f"{SESSION_COOKIE}={session_token}; {cookie_flags}"},
            )

        def _require_session(self) -> str | None:
            actor = self._session_actor()
            if actor is None:
                response(
                    self,
                    401,
                    {"authenticated": False, "error": "session required"},
                )
            return actor

        def _json_body(self) -> dict[str, Any]:
            raw_length = self.headers.get("Content-Length", "")
            try:
                length = int(raw_length)
            except ValueError as error:
                raise GatewayError("Content-Length is required") from error
            if length <= 0 or length > 128 * 1024:
                raise GatewayError("request body is empty or too large")
            try:
                value = json.loads(self.rfile.read(length).decode("utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
                raise GatewayError("request body must be valid JSON") from error
            if not isinstance(value, dict):
                raise GatewayError("request body must be a JSON object")
            return value

        def _forward(
            self,
            method: str,
            path: str,
            body: bytes | None,
            key: str | None,
            actor: str,
        ) -> None:
            try:
                status, content_type, response_body = proxy_request(
                    service_host=service_host,
                    service_port=service_port,
                    token=token,
                    method=method,
                    path=path,
                    body=body,
                    idempotency_key=key,
                    actor_id=actor,
                    actor_signing_secret=actor_signing_secret,
                )
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(response_body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(response_body)
            except GatewayError as error:
                response(self, 503, {"error": str(error)})

        def do_OPTIONS(self) -> None:  # noqa: N802
            self.send_response(204)
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers",
                "Content-Type, Idempotency-Key, "
                + TRUSTED_IDENTITY_HEADER
                + ", "
                + TRUSTED_IDENTITY_TIMESTAMP_HEADER
                + ", "
                + TRUSTED_IDENTITY_SIGNATURE_HEADER,
            )
            self.end_headers()

        def _serve_index(self) -> None:
            if public_dir is None:
                response(self, 404, {"error": "static public directory is not configured"})
                return
            index_path = public_dir / "index.html"
            try:
                body = index_path.read_text(encoding="utf-8")
            except OSError:
                response(self, 404, {"error": "index.html is missing from the public directory"})
                return
            if "index.js" not in body:
                body = body.replace(
                    "</head>",
                    '    <script src="./index.js" type="module"></script>\n  </head>',
                    1,
                )
            encoded = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(encoded)

        def _forward_loan_method(self, method: str) -> None:
            actor = self._require_session()
            if actor is None:
                return
            parsed = urlparse(self.path)
            if not (
                re.fullmatch(r"/api/company/expenses/[A-Za-z0-9_.:-]{1,128}", parsed.path)
                or re.fullmatch(r"/api/company/loans/[A-Za-z0-9_.:-]{1,128}", parsed.path)
                or re.fullmatch(
                    r"/api/company/marketing/(campaigns|placements|channels|materials)/[A-Za-z0-9_.:-]{1,128}(?:/effect)?",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/source/invoice/(in|out)/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/sales/revenues/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/fund/plans/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/plan/tasks/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/source/cost/payment-applies/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/source/cost/contracts/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
                or re.fullmatch(
                    r"/api/company/source/cost/dynamic-cost/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                )
            ):
                response(self, 404, {"error": "development gateway command is not allow-listed"})
                return
            try:
                value = self._json_body() if self.headers.get("Content-Length") else {}
                key = value.pop("idempotency_key", None)
                if key is None:
                    key = self.headers.get("Idempotency-Key", "")
                if not isinstance(key, str) or not key.strip():
                    raise GatewayError("idempotency_key or Idempotency-Key is required")
                body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                self._forward(method, self.path, body if value else None, key.strip(), actor)
            except GatewayError as error:
                response(self, 400, {"error": str(error)})

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/api/session":
                actor = self._session_actor()
                if actor is None:
                    response(self, 401, {"authenticated": False, "error": "session required"})
                else:
                    response(self, 200, {"authenticated": True, "actor_id": actor})
                return
            if parsed.path.startswith(READ_PATH_PREFIX):
                actor = self._require_session()
                if actor is None:
                    return
                self._forward("GET", self.path, None, None, actor)
                return
            if public_dir is None:
                response(self, 404, {"error": "static public directory is not configured"})
                return
            if parsed.path in {"", "/", "/index.html"}:
                self._serve_index()
                return
            if "." not in Path(parsed.path).name:
                self._serve_index()
                return
            super().do_GET()

        def do_POST(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/api/session/login":
                if trusted_identity_secret is not None:
                    actor = self._trusted_identity_actor()
                    if actor is None:
                        response(
                            self,
                            401,
                            {"authenticated": False, "error": "trusted identity assertion rejected"},
                        )
                    else:
                        self._establish_session(actor, "trusted_upstream")
                    return
                try:
                    body = self._json_body()
                except GatewayError as error:
                    response(self, 400, {"authenticated": False, "error": str(error)})
                    return
                supplied_user = body.get("user_code")
                supplied_password = body.get("password")
                if not isinstance(supplied_user, str) or not isinstance(supplied_password, str):
                    response(
                        self,
                        400,
                        {"authenticated": False, "error": "user_code and password are required"},
                    )
                    return
                if not (
                    hmac.compare_digest(supplied_user, dev_user)
                    and hmac.compare_digest(supplied_password, dev_password)
                ):
                    response(self, 401, {"authenticated": False, "error": "invalid credentials"})
                    return
                self._establish_session(actor_id, "development_fixture")
                return
            if parsed.path == "/api/session/logout":
                cookie = SimpleCookie()
                try:
                    cookie.load(self.headers.get("Cookie", ""))
                except Exception:
                    pass
                morsel = cookie.get(SESSION_COOKIE)
                if morsel is not None:
                    with session_lock:
                        sessions.pop(morsel.value, None)
                response(
                    self,
                    200,
                    {"authenticated": False},
                    {
                        "Set-Cookie": (
                            f"{SESSION_COOKIE}=; Max-Age=0; HttpOnly; Path=/; "
                            "SameSite=Strict"
                        )
                    },
                )
                return
            actor = self._require_session()
            if actor is None:
                return
            if not (
                parsed.path == EXPENSE_PATH_PREFIX
                or parsed.path.startswith(EXPENSE_PATH_PREFIX + "/")
                or parsed.path == BUDGET_CHECK_PATH
                or parsed.path == CONTRACT_PATH_PREFIX
                or parsed.path.startswith(CONTRACT_PATH_PREFIX + "/")
                or parsed.path == PAYMENT_APPLICATION_PATH_PREFIX
                or parsed.path.startswith(PAYMENT_APPLICATION_PATH_PREFIX + "/")
                or parsed.path == TENDER_PATH_PREFIX
                or parsed.path.startswith(TENDER_PATH_PREFIX + "/")
                or parsed.path.startswith(SOURCE_TENDER_PATH_PREFIX + "/")
                or parsed.path == SUPPLIER_PATH_PREFIX
                or parsed.path.startswith(SUPPLIER_PATH_PREFIX + "/")
                or parsed.path == TENDER_SPLIT_PATH_PREFIX
                or parsed.path.startswith(TENDER_SPLIT_PATH_PREFIX + "/")
                or parsed.path == SALES_PATH_PREFIX
                or parsed.path.startswith(SALES_PATH_PREFIX + "/")
                or parsed.path == RECEIVABLE_PATH_PREFIX
                or parsed.path.startswith(RECEIVABLE_PATH_PREFIX + "/")
                or parsed.path == DELIVERY_PATH_PREFIX
                or parsed.path.startswith(DELIVERY_PATH_PREFIX + "/")
                or parsed.path == LOAN_PATH_PREFIX
                or parsed.path.startswith(LOAN_PATH_PREFIX + "/")
                or parsed.path == FUND_PATH_PREFIX
                or parsed.path.startswith(FUND_PATH_PREFIX + "/")
                or parsed.path == PLAN_PATH_PREFIX
                or parsed.path.startswith(PLAN_PATH_PREFIX + "/")
                or parsed.path == MARKETING_PATH_PREFIX
                or parsed.path.startswith(MARKETING_PATH_PREFIX + "/")
                or parsed.path == INVOICE_PATH_PREFIX
                or parsed.path.startswith(INVOICE_PATH_PREFIX + "/")
                or parsed.path == SOURCE_COST_PAYMENT_PATH_PREFIX
                or parsed.path == SOURCE_COST_DYNAMIC_PATH_PREFIX
            ):
                response(self, 404, {"error": "development gateway command is not allow-listed"})
                return
            try:
                value = self._json_body()
            except GatewayError as error:
                response(self, 400, {"error": str(error)})
                return
            key = value.pop("idempotency_key", None)
            if parsed.path == BUDGET_CHECK_PATH and key is None:
                body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                self._forward("POST", self.path, body, None, actor)
                return
            if not isinstance(key, str) or not key.strip():
                response(self, 400, {"error": "idempotency_key is required for local commands"})
                return
            body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self._forward("POST", self.path, body, key.strip(), actor)

        def do_PUT(self) -> None:  # noqa: N802
            self._forward_loan_method("PUT")

        def do_DELETE(self) -> None:  # noqa: N802
            self._forward_loan_method("DELETE")

        def log_message(self, format: str, *values: object) -> None:
            sys.stderr.write("company-dev-gateway: " + (format % values) + "\n")

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-dir", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4173)
    parser.add_argument("--service-host", default="127.0.0.1")
    parser.add_argument("--service-port", type=int, default=4174)
    parser.add_argument("--service-token-env", default="MOONPROJ_SERVICE_TOKEN")
    parser.add_argument("--dev-user-env", default="MOONPROJ_DEV_USER")
    parser.add_argument("--dev-password-env", default="MOONPROJ_DEV_PASSWORD")
    parser.add_argument("--actor-id", default=os.environ.get("MOONPROJ_DEV_ACTOR_ID", "rabbita-user"))
    parser.add_argument(
        "--actor-signing-secret-env",
        default="MOONPROJ_ACTOR_SIGNING_SECRET",
    )
    parser.add_argument(
        "--trusted-identity-secret-env",
        default=None,
        help="optional env name for the signed upstream identity mode",
    )
    args = parser.parse_args()
    if args.host in {"0.0.0.0", "::", "[::]"}:
        parser.error("development gateway must bind privately")
    if not args.public_dir.is_dir():
        parser.error(f"public directory does not exist: {args.public_dir}")
    token = os.environ.get(args.service_token_env, "")
    if not token:
        parser.error(f"service token environment variable is not set: {args.service_token_env}")
    dev_user = os.environ.get(args.dev_user_env, "")
    dev_password = os.environ.get(args.dev_password_env, "")
    if args.trusted_identity_secret_env is not None and not re.fullmatch(
        r"[A-Z][A-Z0-9_]{2,127}", args.trusted_identity_secret_env
    ):
        parser.error("--trusted-identity-secret-env must be an uppercase environment variable name")
    trusted_identity_secret = (
        os.environ.get(args.trusted_identity_secret_env, "")
        if args.trusted_identity_secret_env is not None
        else ""
    )
    if args.trusted_identity_secret_env is not None and not trusted_identity_secret:
        parser.error(
            "trusted identity secret environment variable is not set: "
            f"{args.trusted_identity_secret_env}"
        )
    if args.trusted_identity_secret_env is None and (not dev_user or not dev_password):
        parser.error(
            "development session credentials are not set: "
            f"{args.dev_user_env} and {args.dev_password_env}"
        )
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", args.actor_id):
        parser.error("--actor-id contains unsupported characters")
    actor_signing_secret = os.environ.get(args.actor_signing_secret_env, "")
    if not actor_signing_secret:
        parser.error(
            "actor signing secret environment variable is not set: "
            f"{args.actor_signing_secret_env}"
        )
    server = ThreadingHTTPServer(
        (args.host, args.port),
        handler_factory(
            public_dir=args.public_dir,
            service_host=args.service_host,
            service_port=args.service_port,
            token=token,
            dev_user=dev_user,
            dev_password=dev_password,
            actor_id=args.actor_id,
            actor_signing_secret=actor_signing_secret,
            trusted_identity_secret=trusted_identity_secret or None,
        ),
    )
    print(f"company development gateway listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
