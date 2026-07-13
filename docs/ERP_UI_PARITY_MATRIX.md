# ERP UI and API parity matrix

Generated from `../erp/erp_new/web/src/router/index.js`, the source
`server/src/routes` directory, and `frontend/main/main.mbt`. This is an
acceptance register, not a completion claim: mounted fixture screens do
not count as connected company behavior. The generic PostgreSQL
summary/read-model adapter is not dashboard parity; the three dashboard
aliases now use the bounded connected v1 read. The connected exceptions are the local
expense/contract/payment-application/tender command, supplier-provider, supplier, and supplier-risk reads,
MDM organization/project master, budget dictionary, investment, admin governance reads, delivery, core report read,
profile read, project-plan read, and non-authorizing workflow-definition
read verticals.

- Browser routes: **56**
- Source API handlers: **338** (182 mutations)
- Target states: `{"connected_admin_audit_read": 1, "connected_admin_health_read": 1, "connected_admin_read": 1, "connected_cashflow_read": 1, "connected_command_form": 1, "connected_contract_command_form": 1, "connected_contract_read": 1, "connected_cost_read": 1, "connected_dashboard_read": 3, "connected_delivery_command_form": 2, "connected_expense_read": 1, "connected_investment_read": 1, "connected_invoice_read": 1, "connected_loan_command_form": 2, "connected_loan_read": 1, "connected_payment_application_command_form": 1, "connected_profile_read": 1, "connected_project_read": 2, "connected_rbac_user_read": 1, "connected_report_read": 1, "connected_sales_read": 5, "connected_supplier_command_form": 1, "connected_supplier_read": 1, "connected_supplier_risk_read": 1, "connected_tender_command_form": 1, "connected_workflow_definition_read": 1, "fixture_backed_form": 1, "fixture_backed_read_only": 18, "public": 1, "read_only_public": 1}`
- API states: `{"connected_admin_audit_read": 1, "connected_admin_health_read": 1, "connected_admin_read": 1, "connected_cashflow_read": 1, "connected_contract_command": 2, "connected_cost_read": 1, "connected_dashboard_read": 3, "connected_delivery_command": 2, "connected_expense_command": 1, "connected_expense_read": 1, "connected_investment_read": 1, "connected_invoice_read": 1, "connected_loan_command": 2, "connected_loan_read": 1, "connected_payment_application_command": 1, "connected_profile_read": 1, "connected_project_read": 2, "connected_rbac_user_read": 1, "connected_report_read": 1, "connected_sales_read": 5, "connected_supplier_command": 1, "connected_supplier_read": 1, "connected_supplier_risk_read": 1, "connected_tender_command": 1, "connected_workflow_definition_read": 1, "read_only_fixture_no_source_api": 21}`
- Matrix state: **functional_parity_incomplete**

## Browser routes

| Source route | Source view | Rabbita view | UI state | API module | GET / mutation handlers | API state | Required next |
|---|---|---|---|---|---:|---|---|
| `/login` | `../views/Login.vue` | `login_view` | `public` | `auth` | 3 / 6 | `read_only_fixture_no_source_api` | `connect_authenticated_identity_boundary` |
| `/share/:token` | `../views/ShareReport.vue` | `share_view` | `read_only_public` | `share` | 0 / 0 | `read_only_fixture_no_source_api` | `accept_public_read_scenario` |
| `/dashboard` | `../views/cockpit/index.vue` | `dashboard_view` | `connected_dashboard_read` | `dashboard` | 7 / 0 | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `/dashboard-v3` | `redirect → /dashboard` | `dashboard_view` | `connected_dashboard_read` | `dashboard` | 7 / 0 | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `/ai-hub` | `../views/AIHub.vue` | `ai_hub_view` | `fixture_backed_read_only` | `ai-hub` | 6 / 10 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/ai-stats` | `../views/AIStats.vue` | `ai_stats_view` | `fixture_backed_read_only` | `ai-stats` | 3 / 1 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/cockpit` | `redirect → /dashboard` | `dashboard_view` | `connected_dashboard_read` | `dashboard` | 7 / 0 | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `/projects` | `../views/Projects.vue` | `project_view` | `connected_project_read` | `mdm` | 3 / 3 | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `/projects/:projGuid` | `../views/ProjectDetail.vue` | `project_detail_view` | `connected_project_read` | `mdm` | 3 / 3 | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `/expenses` | `../views/ExpenseList.vue` | `expenses_view` | `connected_expense_read` | `budget` | 6 / 7 | `connected_expense_read` | `accept_browser_expense_scenario_and_production_identity` |
| `/expenses/new` | `../views/ExpenseCreate.vue` | `expense_editor_view` | `connected_command_form` | `budget` | 6 / 7 | `connected_expense_command` | `accept_production_identity_and_full_session_scenario` |
| `/expenses/:guid` | `../views/ExpenseDetail.vue` | `expense_editor_view` | `fixture_backed_form` | `budget` | 6 / 7 | `read_only_fixture_no_source_api` | `connect_authenticated_read_and_command_api_and_accept_scenario` |
| `/tasks` | `../views/Tasks.vue` | `tasks_view` | `connected_workflow_definition_read` | `workflow` | 7 / 5 | `connected_workflow_definition_read` | `accept_browser_workflow_definition_scenario_and_production_identity` |
| `/contracts` | `../views/Contracts.vue` | `contracts_view` | `connected_contract_read` | `cost` | 7 / 13 | `connected_contract_command` | `accept_browser_contract_scenario_and_production_identity` |
| `/contracts/:guid` | `../views/ContractDetail.vue` | `contract_detail_view` | `connected_contract_command_form` | `cost` | 7 / 13 | `connected_contract_command` | `accept_browser_contract_scenario_and_production_identity` |
| `/payment-applies` | `../views/PaymentApplies.vue` | `payment_applies_view` | `connected_payment_application_command_form` | `cost` | 7 / 13 | `connected_payment_application_command` | `accept_browser_payment_application_scenario_and_production_identity` |
| `/dynamic-cost` | `../views/DynamicCost.vue` | `dynamic_cost_view` | `connected_cost_read` | `cost` | 7 / 13 | `connected_cost_read` | `accept_browser_cost_scenario_and_production_identity` |
| `/loans` | `../views/LoanList.vue` | `loans_view` | `connected_loan_read` | `loan` | 2 / 6 | `connected_loan_read` | `accept_browser_loan_scenario_and_production_identity` |
| `/loans/new` | `../views/LoanCreate.vue` | `loan_editor_view` | `connected_loan_command_form` | `loan` | 2 / 6 | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `/loans/:guid` | `../views/LoanDetail.vue` | `loan_editor_view` | `connected_loan_command_form` | `loan` | 2 / 6 | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `/project-plan` | `../views/ProjectPlan.vue` | `project_plan_view` | `connected_delivery_command_form` | `plan` | 4 / 5 | `connected_delivery_command` | `accept_browser_delivery_scenario_and_production_identity` |
| `/investment` | `../views/Investment.vue` | `investment_view` | `connected_investment_read` | `investment` | 16 / 12 | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `/cost-dashboard-v3` | `../views/CostDashboardV3.vue` | `cost_dashboard_view` | `fixture_backed_read_only` | `cost` | 7 / 13 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/sales/revenues` | `../views/SalesRevenue.vue` | `sales_revenues_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/customers` | `../views/SaleCustomers.vue` | `sales_customers_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/subscriptions` | `../views/SaleSubscriptions.vue` | `sales_subscriptions_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/contracts` | `../views/SaleContracts.vue` | `sales_contracts_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/mortgages` | `../views/SaleMortgages.vue` | `sales_mortgages_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/marketing` | `../views/Marketing.vue` | `marketing_view` | `fixture_backed_read_only` | `marketing` | 4 / 9 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/fund/plan` | `../views/FundPlan.vue` | `fund_plan_view` | `fixture_backed_read_only` | `fund` | 3 / 5 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/project/progress` | `../views/ProjectProgress.vue` | `progress_view` | `connected_delivery_command_form` | `progress` | 2 / 5 | `connected_delivery_command` | `accept_browser_delivery_scenario_and_production_identity` |
| `/invoice` | `../views/Invoice.vue` | `invoice_view` | `connected_invoice_read` | `invoice` | 3 / 4 | `connected_invoice_read` | `accept_browser_invoice_scenario_and_production_identity` |
| `/tender` | `../views/TenderPlan.vue` | `tender_view` | `connected_tender_command_form` | `tender` | 3 / 5 | `connected_tender_command` | `accept_browser_tender_scenario_and_production_identity` |
| `/cbs/dict` | `../views/CbsDict.vue` | `cbs_view` | `fixture_backed_read_only` | `cbs` | 10 / 20 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/cbs/versions` | `../views/CbsVersions.vue` | `cbs_view` | `fixture_backed_read_only` | `cbs` | 10 / 20 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/cbs/r0-queue` | `../views/CbsR0Queue.vue` | `cbs_view` | `fixture_backed_read_only` | `cbs` | 10 / 20 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/cbs/approval-config` | `../views/ApprovalConfig.vue` | `cbs_view` | `fixture_backed_read_only` | `cbs` | 10 / 20 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/srm/providers` | `../views/Providers.vue` | `srm_providers_view` | `connected_supplier_command_form` | `srm` | 9 / 5 | `connected_supplier_command` | `accept_browser_supplier_scenario_and_production_identity` |
| `/srm/providers/:guid` | `../views/ProviderDetail.vue` | `provider_detail_view` | `connected_supplier_read` | `srm` | 9 / 5 | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `/srm/risk-board` | `../views/RiskBoard.vue` | `srm_risk_view` | `connected_supplier_risk_read` | `srm` | 9 / 5 | `connected_supplier_risk_read` | `accept_browser_supplier_risk_scenario_and_production_identity` |
| `/ocr-config` | `../views/OcrConfig.vue` | `ocr_view` | `fixture_backed_read_only` | `admin` | 13 / 5 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/reports` | `../views/Reports.vue` | `reports_view` | `connected_report_read` | `reports` | 7 / 3 | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `/report-builder` | `../views/ReportBuilder.vue` | `report_builder_view` | `fixture_backed_read_only` | `reports` | 7 / 3 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/warning` | `../views/WarningCenter.vue` | `warning_view` | `fixture_backed_read_only` | `warning` | 7 / 11 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/warning-rules` | `../views/WarningRules.vue` | `warning_rules_view` | `fixture_backed_read_only` | `warning` | 7 / 11 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/cashflow` | `../views/CashflowForecast.vue` | `cashflow_view` | `connected_cashflow_read` | `cashflow` | 6 / 1 | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `/attachments` | `../views/AttachmentCenter.vue` | `attachments_view` | `fixture_backed_read_only` | `attachment` | 4 / 3 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/audit-log` | `../views/AuditLog.vue` | `audit_view` | `connected_admin_audit_read` | `admin` | 13 / 5 | `connected_admin_audit_read` | `accept_browser_admin_audit_scenario_and_super_user_owner` |
| `/error-log` | `../views/ErrorLog.vue` | `error_view` | `fixture_backed_read_only` | `admin` | 13 / 5 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/system-health` | `../views/SystemHealth.vue` | `health_view` | `connected_admin_health_read` | `admin` | 13 / 5 | `connected_admin_health_read` | `accept_browser_admin_health_scenario_and_super_user_owner` |
| `/users` | `../views/UserManagement.vue` | `users_view` | `connected_rbac_user_read` | `rbac` | 5 / 7 | `connected_rbac_user_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `/profile` | `../views/Profile.vue` | `profile_view` | `connected_profile_read` | `auth` | 3 / 6 | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `/inbox` | `../views/Inbox.vue` | `inbox_view` | `fixture_backed_read_only` | `notify` | 8 / 11 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/notify-config` | `../views/NotifyConfig.vue` | `notify_view` | `fixture_backed_read_only` | `notify` | 8 / 11 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/webhook-config` | `../views/WebhookConfig.vue` | `webhook_view` | `fixture_backed_read_only` | `webhook` | 1 / 4 | `read_only_fixture_no_source_api` | `connect_authenticated_read_api_and_accept_screenshot_and_scenario` |
| `/admin` | `../views/Admin.vue` | `admin_view` | `connected_admin_read` | `admin` | 13 / 5 | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |

## API actions

Every source handler remains an explicit action item until an
authenticated target read/command path, authorization decision,
idempotency key, durable audit evidence, and a role-based scenario
are attached. The JSON output contains all 338 handler rows.

| Module | Method | Source path | Browser routes | Current state | Required next |
|---|---|---|---|---|---|
| `admin` | `GET` | `/dict/groups` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/dict/options` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `POST` | `/dict/options` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `implement_authenticated_command_and_audit` |
| `admin` | `PATCH` | `/dict/options/:guid` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `implement_authenticated_command_and_audit` |
| `admin` | `GET` | `/quality/overview` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/audit/logs` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/audit/actions` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/health/tables` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/health/bpm-pool` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/backup/db` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `connect_authenticated_read_api` |
| `admin` | `GET` | `/health/full` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `connect_authenticated_read_api` |
| `admin` | `GET` | `/error-log` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `connect_authenticated_read_api` |
| `admin` | `GET` | `/ocr/status` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `connect_authenticated_read_api` |
| `admin` | `POST` | `/ocr/test` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `implement_authenticated_command_and_audit` |
| `admin` | `GET` | `/llm/status` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `connect_authenticated_read_api` |
| `admin` | `POST` | `/llm/test` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `implement_authenticated_command_and_audit` |
| `admin` | `POST` | `/sys-param` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `implement_authenticated_command_and_audit` |
| `admin` | `GET` | `/ai/diag` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `POST` | `/intake` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/confirm` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/discard/:draftId` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `GET` | `/corrections` | `/ai-hub` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `GET` | `/correction-stats` | `/ai-hub` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `GET` | `/drafts` | `/ai-hub` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `GET` | `/drafts/:draftId` | `/ai-hub` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `POST` | `/query` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `GET` | `/query-log` | `/ai-hub` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `POST` | `/explain` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/rule-from-nl` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/approval-draft` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/global-ask` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/query-session` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `GET` | `/usage-stats` | `/ai-hub` | `not_connected` | `connect_authenticated_read_api` |
| `ai-hub` | `POST` | `/command` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-stats` | `GET` | `/overview` | `/ai-stats` | `not_connected` | `connect_authenticated_read_api` |
| `ai-stats` | `GET` | `/activity` | `/ai-stats` | `not_connected` | `connect_authenticated_read_api` |
| `ai-stats` | `GET` | `/badge` | `/ai-stats` | `not_connected` | `connect_authenticated_read_api` |
| `ai-stats` | `POST` | `/badge/batch` | `/ai-stats` | `not_connected` | `implement_authenticated_command_and_audit` |
| `attachment` | `POST` | `/upload` | `/attachments` | `not_connected` | `implement_authenticated_command_and_audit` |
| `attachment` | `GET` | `/list` | `/attachments` | `not_connected` | `connect_authenticated_read_api` |
| `attachment` | `GET` | `/download/:guid` | `/attachments` | `not_connected` | `connect_authenticated_read_api` |
| `attachment` | `DELETE` | `/:guid` | `/attachments` | `not_connected` | `implement_authenticated_command_and_audit` |
| `attachment` | `POST` | `/re-extract/:guid` | `/attachments` | `not_connected` | `implement_authenticated_command_and_audit` |
| `attachment` | `GET` | `/all` | `/attachments` | `not_connected` | `connect_authenticated_read_api` |
| `attachment` | `GET` | `/stats` | `/attachments` | `not_connected` | `connect_authenticated_read_api` |
| `auth` | `POST` | `/login` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `GET` | `/me` | `/login`, `/profile` | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `auth` | `POST` | `/logout` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `POST` | `/change-password` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `PUT` | `/profile` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `GET` | `/my-initiated` | `/login`, `/profile` | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `auth` | `GET` | `/prefs` | `/login`, `/profile` | `not_connected` | `connect_authenticated_read_api` |
| `auth` | `PUT` | `/prefs/:key` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `DELETE` | `/prefs/:key` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `GET` | `/dict/cost-subjects` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_read` | `accept_browser_budget_scenario_and_production_identity` |
| `budget` | `GET` | `/proceedings` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_read` | `accept_browser_budget_scenario_and_production_identity` |
| `budget` | `GET` | `/users-in-bu` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `connect_authenticated_read_api` |
| `budget` | `GET` | `/expenses` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_read` | `accept_browser_expense_scenario_and_production_identity` |
| `budget` | `GET` | `/expenses/:guid` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `connect_authenticated_read_api` |
| `budget` | `POST` | `/expenses` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `POST` | `/expenses/:guid/submit-for-approval` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `POST` | `/expenses/:guid/sync-from-workflow` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `PUT` | `/expenses/:guid` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `DELETE` | `/expenses/:guid` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `GET` | `/my-loan-balance` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `connect_authenticated_read_api` |
| `budget` | `POST` | `/budget-check` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `POST` | `/expenses/:guid/auto-offset` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cashflow` | `GET` | `/forecast` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `GET` | `/forecast-v3` | `/cashflow` | `not_connected` | `connect_authenticated_read_api` |
| `cashflow` | `GET` | `/forecast/detail` | `/cashflow` | `not_connected` | `connect_authenticated_read_api` |
| `cashflow` | `GET` | `/inflow` | `/cashflow` | `not_connected` | `connect_authenticated_read_api` |
| `cashflow` | `GET` | `/net` | `/cashflow` | `not_connected` | `connect_authenticated_read_api` |
| `cashflow` | `GET` | `/gap-alert` | `/cashflow` | `not_connected` | `connect_authenticated_read_api` |
| `cashflow` | `POST` | `/ai-explain` | `/cashflow` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/r-master` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `GET` | `/dict` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `POST` | `/dict` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/dict/batch-adjust` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/dict/f-balance` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `GET` | `/versions` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `POST` | `/versions/clone` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/versions/freeze` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/versions/activate` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/versions/compare` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `GET` | `/r0/queue` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `POST` | `/r0/resolve` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/approval-rules` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `GET` | `/approval-rules/pick` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `GET` | `/demo/contracts` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `POST` | `/demo/contracts` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `PUT` | `/demo/contracts/:id/state` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/demo/legacy` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `DELETE` | `/demo/clear` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/submit-approval` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/approve` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/reject` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/mark-paid` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/changes` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `connect_authenticated_read_api` |
| `cbs` | `POST` | `/changes` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/changes/:id/submit-approval` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/changes/:id/approve` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/approval-rules` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `PUT` | `/approval-rules/:guid` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `DELETE` | `/approval-rules/:guid` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `GET` | `/contracts` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `GET` | `/contracts/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `GET` | `/payment-applies` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `GET` | `/dynamic-cost` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `GET` | `/dynamic-cost/:guid/remarks` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `POST` | `/contracts` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `POST` | `/payment-applies` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `POST` | `/dynamic-cost` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `PUT` | `/contracts/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `DELETE` | `/contracts/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `PUT` | `/payment-applies/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `DELETE` | `/payment-applies/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `PUT` | `/dynamic-cost/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `DELETE` | `/dynamic-cost/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `GET` | `/contracts/:guid/milestones` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `POST` | `/contracts/:guid/milestones` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `PUT` | `/milestones/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `DELETE` | `/milestones/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cost` | `GET` | `/milestones/:guid/check` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `connect_authenticated_read_api` |
| `cost` | `POST` | `/milestones/:guid/trigger-event` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `not_connected` | `implement_authenticated_command_and_audit` |
| `dashboard` | `GET` | `/group/overview` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/group/funnel` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/group/top-anomalies` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/project/:projGuid/kpi` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/project/:projGuid/anomalies` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/v2/group` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `not_connected` | `connect_authenticated_read_api` |
| `dashboard` | `GET` | `/v3/group` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `not_connected` | `connect_authenticated_read_api` |
| `export` | `POST` | `/excel` | — | `not_connected` | `implement_authenticated_command_and_audit` |
| `fund` | `GET` | `/plans` | `/fund/plan` | `not_connected` | `connect_authenticated_read_api` |
| `fund` | `POST` | `/plans` | `/fund/plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `fund` | `PUT` | `/plans/:guid` | `/fund/plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `fund` | `DELETE` | `/plans/:guid` | `/fund/plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `fund` | `GET` | `/gap-analysis` | `/fund/plan` | `not_connected` | `connect_authenticated_read_api` |
| `fund` | `GET` | `/dispatches` | `/fund/plan` | `not_connected` | `connect_authenticated_read_api` |
| `fund` | `POST` | `/dispatches` | `/fund/plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `fund` | `POST` | `/dispatches/:guid/approve` | `/fund/plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `import` | `GET` | `/:bizType/template` | — | `not_connected` | `connect_authenticated_read_api` |
| `import` | `POST` | `/:bizType` | — | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/versions` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/versions/:versionGuid/indices` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `PUT` | `/indices/:indexGuid` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/profit-summary` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/meta/dimensions` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `POST` | `/projects/:projGuid/excel-imports` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/excel-imports` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `GET` | `/excel-imports/:importGuid/bridge-plan` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `GET` | `/excel-imports/:importGuid` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `GET` | `/excel-imports/:importGuid/index-upsert-preview` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `POST` | `/excel-imports/:importGuid/index-upsert` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `POST` | `/projects/:projGuid/versions` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `POST` | `/projects/:projGuid/versions/:versionGuid/activate` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `POST` | `/versions/:versionGuid/indices` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `DELETE` | `/projects/:projGuid/versions/:versionGuid` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `DELETE` | `/indices/:indexGuid` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/sensitivity` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `POST` | `/projects/:projGuid/ai-explain` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/excel-imports/:importGuid/profit-table` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `GET` | `/excel-imports/:importGuid/plan-line-preview` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `POST` | `/excel-imports/:importGuid/plan-lines/import` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/plan-lines` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `PUT` | `/plan-lines/:lineGuid` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/subject-mappings` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `PUT` | `/projects/:projGuid/subject-mappings` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/profit-cockpit` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `GET` | `/projects/:projGuid/profit-actual` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `investment` | `GET` | `/projects/:projGuid/profit-actual-v2` | `/investment` | `not_connected` | `connect_authenticated_read_api` |
| `invoice` | `GET` | `/in` | `/invoice` | `not_connected` | `connect_authenticated_read_api` |
| `invoice` | `POST` | `/in` | `/invoice` | `not_connected` | `implement_authenticated_command_and_audit` |
| `invoice` | `DELETE` | `/in/:guid` | `/invoice` | `not_connected` | `implement_authenticated_command_and_audit` |
| `invoice` | `GET` | `/out` | `/invoice` | `not_connected` | `connect_authenticated_read_api` |
| `invoice` | `POST` | `/out` | `/invoice` | `not_connected` | `implement_authenticated_command_and_audit` |
| `invoice` | `DELETE` | `/out/:guid` | `/invoice` | `not_connected` | `implement_authenticated_command_and_audit` |
| `invoice` | `GET` | `/tax-ledger` | `/invoice` | `not_connected` | `connect_authenticated_read_api` |
| `loan` | `GET` | `/loans` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_read` | `accept_browser_loan_scenario_and_production_identity` |
| `loan` | `GET` | `/loans/:guid` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_read` | `accept_browser_loan_scenario_and_production_identity` |
| `loan` | `POST` | `/loans` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `POST` | `/loans/:guid/submit-for-approval` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `POST` | `/loans/:guid/offset` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `POST` | `/loans/:guid/sync-from-workflow` | `/loans`, `/loans/new`, `/loans/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `loan` | `PUT` | `/loans/:guid` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `DELETE` | `/loans/:guid` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `marketing` | `GET` | `/campaigns` | `/marketing` | `not_connected` | `connect_authenticated_read_api` |
| `marketing` | `POST` | `/campaigns` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `PUT` | `/campaigns/:guid` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `DELETE` | `/campaigns/:guid` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `GET` | `/placements` | `/marketing` | `not_connected` | `connect_authenticated_read_api` |
| `marketing` | `POST` | `/placements` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `PUT` | `/placements/:guid/effect` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `GET` | `/channels` | `/marketing` | `not_connected` | `connect_authenticated_read_api` |
| `marketing` | `POST` | `/channels` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `DELETE` | `/channels/:guid` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `GET` | `/materials` | `/marketing` | `not_connected` | `connect_authenticated_read_api` |
| `marketing` | `POST` | `/materials` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `marketing` | `DELETE` | `/materials/:guid` | `/marketing` | `not_connected` | `implement_authenticated_command_and_audit` |
| `mdm` | `GET` | `/business-units/tree` | `/projects`, `/projects/:projGuid` | `connected_mdm_read` | `accept_browser_mdm_scenario_and_production_identity` |
| `mdm` | `GET` | `/projects` | `/projects`, `/projects/:projGuid` | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `mdm` | `GET` | `/projects/:projGuid/lifecycle` | `/projects`, `/projects/:projGuid` | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `mdm` | `POST` | `/projects` | `/projects`, `/projects/:projGuid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `mdm` | `PUT` | `/projects/:projGuid` | `/projects`, `/projects/:projGuid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `mdm` | `DELETE` | `/projects/:projGuid` | `/projects`, `/projects/:projGuid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `GET` | `/messages` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `GET` | `/messages/unread-count` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `POST` | `/messages/:guid/read` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `POST` | `/messages/read-all` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `GET` | `/subscriptions` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `POST` | `/subscriptions` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `PATCH` | `/subscriptions/:id` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `DELETE` | `/subscriptions/:id` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `GET` | `/config` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `PUT` | `/config` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `POST` | `/config/test-webhook` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `GET` | `/email-outbox` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `POST` | `/digest/dispatch` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `GET` | `/digest/preview` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `GET` | `/digest/log` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `POST` | `/email-outbox/test` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `POST` | `/email-outbox/:eid/redeliver` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `notify` | `GET` | `/llm-providers` | `/inbox`, `/notify-config` | `not_connected` | `connect_authenticated_read_api` |
| `notify` | `POST` | `/llm-test` | `/inbox`, `/notify-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `plan` | `GET` | `/projects/:projGuid/tasks` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `plan` | `GET` | `/tasks/:guid` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `plan` | `POST` | `/tasks/:guid/report` | `/project-plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `plan` | `GET` | `/projects/:projGuid/plan-summary` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `plan` | `POST` | `/tasks` | `/project-plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `plan` | `PUT` | `/tasks/:guid` | `/project-plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `plan` | `DELETE` | `/tasks/:guid` | `/project-plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `plan` | `POST` | `/ai-suggest-plan` | `/project-plan` | `not_connected` | `implement_authenticated_command_and_audit` |
| `plan` | `GET` | `/tasks/:guid/delay-impact` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `progress` | `GET` | `/progress` | `/project/progress` | `not_connected` | `connect_authenticated_read_api` |
| `progress` | `POST` | `/progress` | `/project/progress` | `not_connected` | `implement_authenticated_command_and_audit` |
| `progress` | `PUT` | `/progress/:guid/report` | `/project/progress` | `not_connected` | `implement_authenticated_command_and_audit` |
| `progress` | `DELETE` | `/progress/:guid` | `/project/progress` | `not_connected` | `implement_authenticated_command_and_audit` |
| `progress` | `GET` | `/outputs` | `/project/progress` | `not_connected` | `connect_authenticated_read_api` |
| `progress` | `POST` | `/outputs` | `/project/progress` | `not_connected` | `implement_authenticated_command_and_audit` |
| `progress` | `POST` | `/outputs/:guid/confirm` | `/project/progress` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `GET` | `/me` | `/users` | `not_connected` | `connect_authenticated_read_api` |
| `rbac` | `GET` | `/roles` | `/users` | `not_connected` | `connect_authenticated_read_api` |
| `rbac` | `GET` | `/roles/:code` | `/users` | `not_connected` | `connect_authenticated_read_api` |
| `rbac` | `GET` | `/users` | `/users` | `connected_rbac_user_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `rbac` | `POST` | `/users` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `PUT` | `/users/:userId` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `POST` | `/users/:userId/toggle` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `POST` | `/users/:userId/reset-password` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `POST` | `/users/:userId/roles` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `GET` | `/permission-catalog` | `/users` | `not_connected` | `connect_authenticated_read_api` |
| `rbac` | `POST` | `/roles` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `DELETE` | `/roles/:code` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `reports` | `GET` | `/cost-summary` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/contract-payment-ledger` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/supplier-analysis` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/approval-efficiency` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/project-stage-matrix` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/templates/meta` | `/reports`, `/report-builder` | `not_connected` | `connect_authenticated_read_api` |
| `reports` | `POST` | `/templates/run` | `/reports`, `/report-builder` | `not_connected` | `implement_authenticated_command_and_audit` |
| `reports` | `GET` | `/templates` | `/reports`, `/report-builder` | `not_connected` | `connect_authenticated_read_api` |
| `reports` | `POST` | `/templates` | `/reports`, `/report-builder` | `not_connected` | `implement_authenticated_command_and_audit` |
| `reports` | `DELETE` | `/templates/:id` | `/reports`, `/report-builder` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `GET` | `/revenues` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `connect_authenticated_read_api` |
| `sales` | `POST` | `/revenues` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `PUT` | `/revenues/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `DELETE` | `/revenues/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `POST` | `/revenues/:guid/confirm-received` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `GET` | `/customers` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `connect_authenticated_read_api` |
| `sales` | `POST` | `/customers` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `PUT` | `/customers/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `DELETE` | `/customers/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `GET` | `/subscriptions` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `connect_authenticated_read_api` |
| `sales` | `POST` | `/subscriptions` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `POST` | `/subscriptions/:guid/convert-to-contract` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `GET` | `/contracts` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `connect_authenticated_read_api` |
| `sales` | `GET` | `/mortgages` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `connect_authenticated_read_api` |
| `sales` | `POST` | `/mortgages` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `POST` | `/mortgages/:guid/approve` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `POST` | `/mortgages/:guid/release` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `GET` | `/refunds` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `connect_authenticated_read_api` |
| `sales` | `POST` | `/refunds` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `POST` | `/refunds/:guid/approve` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `srm` | `GET` | `/categories` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `connect_authenticated_read_api` |
| `srm` | `GET` | `/dict/eval-results` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `connect_authenticated_read_api` |
| `srm` | `GET` | `/dict/sources` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `connect_authenticated_read_api` |
| `srm` | `GET` | `/providers` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `srm` | `GET` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `srm` | `POST` | `/providers` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `implement_authenticated_command_and_audit` |
| `srm` | `PATCH` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `implement_authenticated_command_and_audit` |
| `srm` | `GET` | `/stats/overview` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `srm` | `PUT` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `implement_authenticated_command_and_audit` |
| `srm` | `DELETE` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `implement_authenticated_command_and_audit` |
| `srm` | `GET` | `/providers/:guid/risk` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_risk_read` | `accept_browser_supplier_risk_scenario_and_production_identity` |
| `srm` | `POST` | `/providers/rescore-all` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `implement_authenticated_command_and_audit` |
| `srm` | `GET` | `/risk-board` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_risk_read` | `accept_browser_supplier_risk_scenario_and_production_identity` |
| `srm` | `GET` | `/providers/:guid/check-sign` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `not_connected` | `connect_authenticated_read_api` |
| `tender` | `GET` | `/tenders` | `/tender` | `not_connected` | `connect_authenticated_read_api` |
| `tender` | `POST` | `/tenders` | `/tender` | `not_connected` | `implement_authenticated_command_and_audit` |
| `tender` | `PUT` | `/tenders/:guid/state` | `/tender` | `not_connected` | `implement_authenticated_command_and_audit` |
| `tender` | `DELETE` | `/tenders/:guid` | `/tender` | `not_connected` | `implement_authenticated_command_and_audit` |
| `tender` | `GET` | `/awards` | `/tender` | `not_connected` | `connect_authenticated_read_api` |
| `tender` | `POST` | `/awards` | `/tender` | `not_connected` | `implement_authenticated_command_and_audit` |
| `tender` | `GET` | `/splits` | `/tender` | `not_connected` | `connect_authenticated_read_api` |
| `tender` | `POST` | `/splits` | `/tender` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `GET` | `/badge` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `GET` | `/` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `GET` | `/rules` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `PATCH` | `/rules/:code` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `GET` | `/scans` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `POST` | `/scan` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `POST` | `/:guid/resolve` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `POST` | `/:guid/ignore` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `GET` | `/custom-rules` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `POST` | `/custom-rules` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `DELETE` | `/custom-rules/:code` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `POST` | `/custom-rules/preview` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `GET` | `/rule-templates` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `POST` | `/:guid/to-ticket` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `GET` | `/tickets/mine` | `/warning`, `/warning-rules` | `not_connected` | `connect_authenticated_read_api` |
| `warning` | `PATCH` | `/tickets/:id/status` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `PATCH` | `/tickets/:id/reassign` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `warning` | `PATCH` | `/tickets/:id/extend` | `/warning`, `/warning-rules` | `not_connected` | `implement_authenticated_command_and_audit` |
| `webhook` | `GET` | `/config` | `/webhook-config` | `not_connected` | `connect_authenticated_read_api` |
| `webhook` | `PUT` | `/config/:platform` | `/webhook-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `webhook` | `POST` | `/test/:platform` | `/webhook-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `webhook` | `POST` | `/scan-overdue/preview` | `/webhook-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `webhook` | `POST` | `/scan-overdue` | `/webhook-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `workflow` | `GET` | `/tasks/mine` | `/tasks` | `not_connected` | `connect_authenticated_read_api` |
| `workflow` | `GET` | `/tasks/initiated` | `/tasks` | `not_connected` | `connect_authenticated_read_api` |
| `workflow` | `GET` | `/instances/by-biz` | `/tasks` | `not_connected` | `connect_authenticated_read_api` |
| `workflow` | `GET` | `/instances/:piGuid` | `/tasks` | `not_connected` | `connect_authenticated_read_api` |
| `workflow` | `POST` | `/instances/:piGuid/approve` | `/tasks` | `not_connected` | `implement_authenticated_command_and_audit` |
| `workflow` | `POST` | `/instances/:piGuid/reject` | `/tasks` | `not_connected` | `implement_authenticated_command_and_audit` |
| `workflow` | `GET` | `/process-defs` | `/tasks` | `connected_workflow_definition_read` | `accept_browser_workflow_definition_scenario_and_production_identity` |
| `workflow` | `GET` | `/process-defs/:processKey/preview` | `/tasks` | `connected_workflow_definition_read` | `accept_browser_workflow_definition_scenario_and_production_identity` |
| `workflow` | `GET` | `/tasks/my-history` | `/tasks` | `not_connected` | `connect_authenticated_read_api` |
| `workflow` | `POST` | `/instances` | `/tasks` | `not_connected` | `implement_authenticated_command_and_audit` |
| `workflow` | `POST` | `/instances/:piGuid/cosigners` | `/tasks` | `not_connected` | `implement_authenticated_command_and_audit` |
| `workflow` | `POST` | `/instances/:piGuid/transfer` | `/tasks` | `not_connected` | `implement_authenticated_command_and_audit` |
