# ERP UI and API parity matrix

Generated from `../erp/erp_new/web/src/router/index.js`, the source
`server/src/routes` directory, and `frontend/main/main.mbt`. This is an
acceptance register, not a completion claim: mounted fixture screens do
not count as connected company behavior. The generic PostgreSQL
summary/read-model adapter is not dashboard parity; the three dashboard
aliases now use the bounded connected v1 read. The connected exceptions are the local
expense/contract/payment-application/tender command, supplier-provider, supplier, and supplier-risk reads,
MDM organization/project master reads plus the local project command, budget dictionary, investment, admin governance reads, delivery, core report read,
profile read, project-plan read, non-authorizing workflow-definition, cashflow, CBS,
fund-plan, project-plan task, observed-warning, attachment-metadata, marketing metadata reads and authority-bound local commands, invoice/tax reads and authority-bound local registration, notification metadata, OCR-status, error-log, AI-analytics, AI Hub observation, webhook-configuration, and report-builder metadata read verticals.

- Browser routes: **56**
- Source API handlers: **338** (182 mutations)
- Target states: `{"connected_admin_audit_read": 1, "connected_admin_error_read": 1, "connected_admin_health_read": 1, "connected_admin_ocr_read": 1, "connected_admin_read": 1, "connected_ai_hub_read": 1, "connected_ai_stats_read": 1, "connected_attachment_read": 1, "connected_cashflow_read": 1, "connected_cbs_read": 4, "connected_command_form": 1, "connected_contract_command_form": 1, "connected_contract_read": 1, "connected_cost_dashboard_read": 1, "connected_cost_read": 1, "connected_dashboard_read": 3, "connected_delivery_command_form": 2, "connected_expense_detail_read": 1, "connected_expense_read": 1, "connected_fund_read": 1, "connected_investment_read": 1, "connected_investment_command_candidate": 0, "connected_report_export_xlsx": 0, "connected_invoice_read": 1, "connected_loan_command_form": 2, "connected_loan_read": 1, "connected_marketing_read": 1, "connected_notification_read": 2, "connected_payment_application_command_form": 1, "connected_profile_read": 1, "connected_project_read": 2, "connected_rbac_user_read": 1, "connected_report_builder_command_form": 1, "connected_report_read": 1, "connected_sales_read": 5, "connected_supplier_command_form": 1, "connected_supplier_read": 1, "connected_supplier_risk_read": 1, "connected_tender_command_form": 1, "connected_warning_command_form": 1, "connected_warning_read": 1, "connected_webhook_read": 1, "connected_workflow_definition_read": 1, "public": 1, "read_only_public": 1}`
- API states: `{"connected_admin_audit_read": 1, "connected_admin_error_read": 1, "connected_admin_health_read": 1, "connected_admin_ocr_read": 1, "connected_admin_read": 1, "connected_ai_hub_read": 1, "ai_hub_explain_candidate": 1, "connected_ai_stats_read": 1, "connected_ai_stats_badge_batch_read": 1, "connected_attachment_read": 1, "attachment_re_extract_candidate": 1, "connected_cashflow_read": 1, "connected_cashflow_ai_explain_candidate": 1, "connected_cbs_read": 4, "connected_contract_command": 2, "connected_cost_dashboard_read": 1, "connected_cost_read": 1, "connected_dashboard_read": 3, "connected_delivery_command": 2, "connected_expense_command": 1, "connected_expense_detail_read": 1, "connected_expense_read": 1, "connected_fund_read": 1, "connected_investment_read": 1, "connected_investment_ai_explain_candidate": 1, "connected_invoice_read": 1, "connected_loan_command": 2, "connected_loan_read": 1, "connected_marketing_read": 1, "connected_notification_read": 2, "connected_notification_config_command_candidate": 1, "connected_notification_webhook_test_candidate": 1, "connected_notification_email_command_candidate": 2, "connected_ai_provider_test_candidate": 3, "connected_notification_digest_dispatch_candidate": 1, "connected_payment_application_command": 1, "connected_profile_read": 1, "connected_project_read": 2, "plan_ai_suggestion_candidate": 1, "connected_rbac_user_command_candidate": 4, "connected_rbac_user_read": 1, "connected_report_builder_command": 1, "connected_report_read": 1, "connected_sales_read": 5, "connected_supplier_command": 1, "connected_supplier_read": 1, "connected_supplier_risk_read": 1, "supplier_rescore_candidate": 1, "connected_tender_command": 1, "connected_warning_command": 1, "connected_warning_custom_rule_command_candidate": 2, "connected_warning_custom_rule_preview_candidate": 1, "connected_warning_read": 1, "connected_warning_rule_command_candidate": 1, "connected_warning_scan_preview_read": 1, "connected_warning_ticket_command_candidate": 1, "connected_warning_ticket_transition_candidate": 3, "connected_webhook_config_command_candidate": 1, "connected_webhook_test_delivery_candidate": 1, "connected_webhook_overdue_scan_candidate": 1, "connected_webhook_overdue_preview_read": 1, "connected_webhook_read": 1, "connected_workflow_definition_read": 1, "connected_admin_sys_param_command_candidate": 1, "read_only_fixture_no_source_api": 2}`
- Matrix state: **functional_parity_incomplete**
- Native additions since the original matrix snapshot: `connected_cashflow_ai_explain_candidate` **1**, `connected_investment_ai_explain_candidate` **1**, `plan_ai_suggestion_candidate` **1**, `ai_hub_explain_candidate` **1**, `attachment_re_extract_candidate` **1**, `connected_warning_custom_rule_preview_candidate` **1**, `supplier_rescore_candidate` **1**, `connected_investment_command_candidate` **6**, `connected_report_export_xlsx` **1**, `connected_tender_state_candidate` **1**, and `connected_tender_award_candidate` **1**; the JSON ledger is authoritative for the full state counts.
- Workflow command state: `connected_workflow_command_candidate` **5** (start, approve, reject, cosigner, transfer); browser/production identity and operations-owner acceptance remain required.

## Browser routes

| Source route | Source view | Rabbita view | UI state | API module | GET / mutation handlers | API state | Required next |
|---|---|---|---|---|---:|---|---|
| `/login` | `../views/Login.vue` | `login_view` | `public` | `auth` | 3 / 6 | `read_only_fixture_no_source_api` | `connect_authenticated_identity_boundary` |
| `/share/:token` | `../views/ShareReport.vue` | `share_view` | `read_only_public` | `share` | 0 / 0 | `read_only_fixture_no_source_api` | `accept_public_read_scenario` |
| `/dashboard` | `../views/cockpit/index.vue` | `dashboard_view` | `connected_dashboard_read` | `dashboard` | 7 / 0 | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `/dashboard-v3` | `redirect → /dashboard` | `dashboard_view` | `connected_dashboard_read` | `dashboard` | 7 / 0 | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `/ai-hub` | `../views/AIHub.vue` | `ai_hub_view` | `connected_ai_hub_read` | `ai-hub` | 6 / 10 | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `/ai-stats` | `../views/AIStats.vue` | `ai_stats_view` | `connected_ai_stats_read` | `ai-stats` | 3 / 1 | `connected_ai_stats_read` | `accept_browser_ai_stats_scenario_and_production_identity` |
| `/cockpit` | `redirect → /dashboard` | `dashboard_view` | `connected_dashboard_read` | `dashboard` | 7 / 0 | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `/projects` | `../views/Projects.vue` | `project_view` | `connected_project_read` | `mdm` | 3 / 3 | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `/projects/:projGuid` | `../views/ProjectDetail.vue` | `project_detail_view` | `connected_project_read` | `mdm` | 3 / 3 | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `/expenses` | `../views/ExpenseList.vue` | `expenses_view` | `connected_expense_read` | `budget` | 6 / 7 | `connected_expense_read` | `accept_browser_expense_scenario_and_production_identity` |
| `/expenses/new` | `../views/ExpenseCreate.vue` | `expense_editor_view` | `connected_command_form` | `budget` | 6 / 7 | `connected_expense_command` | `accept_production_identity_and_full_session_scenario` |
| `/expenses/:guid` | `../views/ExpenseDetail.vue` | `expense_editor_view` | `connected_expense_detail_read` | `budget` | 6 / 7 | `connected_expense_detail_read` | `accept_browser_expense_detail_scenario_and_production_identity` |
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
| `/cost-dashboard-v3` | `../views/CostDashboardV3.vue` | `cost_dashboard_view` | `connected_cost_dashboard_read` | `cost` | 7 / 13 | `connected_cost_dashboard_read` | `accept_browser_cost_dashboard_scenario_and_production_identity` |
| `/sales/revenues` | `../views/SalesRevenue.vue` | `sales_revenues_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/customers` | `../views/SaleCustomers.vue` | `sales_customers_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/subscriptions` | `../views/SaleSubscriptions.vue` | `sales_subscriptions_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/contracts` | `../views/SaleContracts.vue` | `sales_contracts_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/sales/mortgages` | `../views/SaleMortgages.vue` | `sales_mortgages_view` | `connected_sales_read` | `sales` | 6 / 14 | `connected_sales_read` | `accept_browser_sales_scenario_and_production_identity` |
| `/marketing` | `../views/Marketing.vue` | `marketing_view` | `connected_marketing_read` | `marketing` | 4 / 9 | `connected_marketing_read` | `accept_browser_marketing_scenario_and_production_identity` |
| `/fund/plan` | `../views/FundPlan.vue` | `fund_plan_view` | `connected_fund_read` | `fund` | 3 / 5 | `connected_fund_read` | `accept_browser_fund_scenario_and_production_identity` |
| `/project/progress` | `../views/ProjectProgress.vue` | `progress_view` | `connected_delivery_command_form` | `progress` | 2 / 5 | `connected_delivery_command` | `accept_browser_delivery_scenario_and_production_identity` |
| `/invoice` | `../views/Invoice.vue` | `invoice_view` | `connected_invoice_read` | `invoice` | 3 / 4 | `connected_invoice_read` | `accept_browser_invoice_scenario_and_production_identity` |
| `/tender` | `../views/TenderPlan.vue` | `tender_view` | `connected_tender_command_form` | `tender` | 3 / 5 | `connected_tender_command` | `accept_browser_tender_scenario_and_production_identity` |
| `/cbs/dict` | `../views/CbsDict.vue` | `cbs_view` | `connected_cbs_read` | `cbs` | 10 / 20 | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `/cbs/versions` | `../views/CbsVersions.vue` | `cbs_view` | `connected_cbs_read` | `cbs` | 10 / 20 | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `/cbs/r0-queue` | `../views/CbsR0Queue.vue` | `cbs_view` | `connected_cbs_read` | `cbs` | 10 / 20 | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `/cbs/approval-config` | `../views/ApprovalConfig.vue` | `cbs_view` | `connected_cbs_read` | `cbs` | 10 / 20 | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `/srm/providers` | `../views/Providers.vue` | `srm_providers_view` | `connected_supplier_command_form` | `srm` | 9 / 5 | `connected_supplier_command` | `accept_browser_supplier_scenario_and_production_identity` |
| `/srm/providers/:guid` | `../views/ProviderDetail.vue` | `provider_detail_view` | `connected_supplier_read` | `srm` | 9 / 5 | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `/srm/risk-board` | `../views/RiskBoard.vue` | `srm_risk_view` | `connected_supplier_risk_read` | `srm` | 9 / 5 | `connected_supplier_risk_read` | `accept_browser_supplier_risk_scenario_and_production_identity` |
| `/ocr-config` | `../views/OcrConfig.vue` | `ocr_view` | `connected_admin_ocr_read` | `admin` | 13 / 5 | `connected_admin_ocr_read` | `accept_browser_ocr_scenario_and_super_user_owner` |
| `/reports` | `../views/Reports.vue` | `reports_view` | `connected_report_read` | `reports` | 7 / 3 | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `/report-builder` | `../views/ReportBuilder.vue` | `report_builder_view` | `connected_report_builder_command_form` | `reports` | 7 / 3 | `connected_report_builder_command` | `accept_browser_report_builder_command_scenario_and_report_owner` |
| `/warning` | `../views/WarningCenter.vue` | `warning_view` | `connected_warning_command_form` | `warning` | 7 / 11 | `connected_warning_command` | `accept_browser_warning_command_scenario_and_warning_owner` |
| `/warning-rules` | `../views/WarningRules.vue` | `warning_rules_view` | `connected_warning_read` | `warning` | 7 / 11 | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `/cashflow` | `../views/CashflowForecast.vue` | `cashflow_view` | `connected_cashflow_read` | `cashflow` | 6 / 1 | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `/attachments` | `../views/AttachmentCenter.vue` | `attachments_view` | `connected_attachment_read` | `attachment` | 4 / 3 | `connected_attachment_read` | `accept_browser_attachment_scenario_and_production_identity` |
| `/audit-log` | `../views/AuditLog.vue` | `audit_view` | `connected_admin_audit_read` | `admin` | 13 / 5 | `connected_admin_audit_read` | `accept_browser_admin_audit_scenario_and_super_user_owner` |
| `/error-log` | `../views/ErrorLog.vue` | `error_view` | `connected_admin_error_read` | `admin` | 13 / 5 | `connected_admin_error_read` | `accept_browser_error_log_scenario_and_super_user_owner` |
| `/system-health` | `../views/SystemHealth.vue` | `health_view` | `connected_admin_health_read` | `admin` | 13 / 5 | `connected_admin_health_read` | `accept_browser_admin_health_scenario_and_super_user_owner` |
| `/users` | `../views/UserManagement.vue` | `users_view` | `connected_rbac_user_read` | `rbac` | 5 / 7 | `connected_rbac_user_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `/profile` | `../views/Profile.vue` | `profile_view` | `connected_profile_read` | `auth` | 3 / 6 | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `/inbox` | `../views/Inbox.vue` | `inbox_view` | `connected_notification_read` | `notify` | 8 / 11 | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `/notify-config` | `../views/NotifyConfig.vue` | `notify_view` | `connected_notification_read` | `notify` | 8 / 11 | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `/webhook-config` | `../views/WebhookConfig.vue` | `webhook_view` | `connected_webhook_read` | `webhook` | 1 / 4 | `connected_webhook_read` | `accept_browser_webhook_scenario_and_production_identity` |
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
| `admin` | `POST` | `/dict/options` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_dictionary_command` | `accept_browser_admin_dictionary_command_scenario_and_super_user_owner` |
| `admin` | `PATCH` | `/dict/options/:guid` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_dictionary_command` | `accept_browser_admin_dictionary_command_scenario_and_super_user_owner` |
| `admin` | `GET` | `/quality/overview` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/audit/logs` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/audit/actions` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/health/tables` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/health/bpm-pool` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/backup/db` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_boundary` | `accept_backup_owner_retention_and_download_authorization` |
| `admin` | `GET` | `/health/full` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `GET` | `/error-log` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_error_read` | `accept_browser_error_log_scenario_and_super_user_owner` |
| `admin` | `GET` | `/ocr/status` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_ocr_read` | `accept_browser_ocr_scenario_and_super_user_owner` |
| `admin` | `POST` | `/ocr/test` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_ai_provider_test_candidate` | `accept_browser_ai_provider_test_candidate_and_security_owner` |
| `admin` | `GET` | `/llm/status` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `admin` | `POST` | `/llm/test` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_ai_provider_test_candidate` | `accept_browser_ai_provider_test_candidate_and_security_owner` |
| `admin` | `POST` | `/sys-param` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_sys_param_command_candidate` | `accept_browser_admin_sys_param_scenario_and_super_user_owner` |
| `admin` | `GET` | `/ai/diag` | `/ocr-config`, `/audit-log`, `/error-log`, `/system-health`, `/admin` | `connected_admin_read` | `accept_browser_admin_scenario_and_super_user_owner` |
| `ai-hub` | `POST` | `/intake` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/confirm` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/discard/:draftId` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `GET` | `/corrections` | `/ai-hub` | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `ai-hub` | `GET` | `/correction-stats` | `/ai-hub` | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `ai-hub` | `GET` | `/drafts` | `/ai-hub` | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `ai-hub` | `GET` | `/drafts/:draftId` | `/ai-hub` | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `ai-hub` | `POST` | `/query` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `GET` | `/query-log` | `/ai-hub` | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `ai-hub` | `POST` | `/explain` | `/ai-hub` | `ai_hub_explain_candidate` | `accept_browser_ai_hub_explain_scenario_and_ai_owner` |
| `ai-hub` | `POST` | `/rule-from-nl` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/approval-draft` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/global-ask` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `POST` | `/query-session` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-hub` | `GET` | `/usage-stats` | `/ai-hub` | `connected_ai_hub_read` | `accept_browser_ai_hub_scenario_and_production_identity` |
| `ai-hub` | `POST` | `/command` | `/ai-hub` | `not_connected` | `implement_authenticated_command_and_audit` |
| `ai-stats` | `GET` | `/overview` | `/ai-stats` | `connected_ai_stats_read` | `accept_browser_ai_stats_scenario_and_production_identity` |
| `ai-stats` | `GET` | `/activity` | `/ai-stats` | `connected_ai_stats_read` | `accept_browser_ai_stats_scenario_and_production_identity` |
| `ai-stats` | `GET` | `/badge` | `/ai-stats` | `connected_ai_stats_read` | `accept_browser_ai_stats_scenario_and_production_identity` |
| `ai-stats` | `POST` | `/badge/batch` | `/ai-stats` | `connected_ai_stats_badge_batch_read` | `accept_browser_ai_stats_batch_scenario_and_production_identity` |
| `attachment` | `POST` | `/upload` | `/attachments` | `not_connected` | `implement_authenticated_command_and_audit` |
| `attachment` | `GET` | `/list` | `/attachments` | `connected_attachment_read` | `accept_browser_attachment_scenario_and_production_identity` |
| `attachment` | `GET` | `/download/:guid` | `/attachments` | `connected_attachment_boundary` | `accept_binary_storage_and_production_identity` |
| `attachment` | `DELETE` | `/:guid` | `/attachments` | `not_connected` | `implement_authenticated_command_and_audit` |
| `attachment` | `POST` | `/re-extract/:guid` | `/attachments` | `attachment_re_extract_candidate` | `accept_browser_attachment_re_extract_scenario_and_ai_owner` |
| `attachment` | `GET` | `/all` | `/attachments` | `connected_attachment_read` | `accept_browser_attachment_scenario_and_production_identity` |
| `attachment` | `GET` | `/stats` | `/attachments` | `connected_attachment_read` | `accept_browser_attachment_scenario_and_production_identity` |
| `auth` | `POST` | `/login` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `GET` | `/me` | `/login`, `/profile` | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `auth` | `POST` | `/logout` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `POST` | `/change-password` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `PUT` | `/profile` | `/login`, `/profile` | `not_connected` | `implement_authenticated_command_and_audit` |
| `auth` | `GET` | `/my-initiated` | `/login`, `/profile` | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `auth` | `GET` | `/prefs` | `/login`, `/profile` | `connected_profile_read` | `accept_browser_profile_scenario_and_production_identity` |
| `auth` | `PUT` | `/prefs/:key` | `/login`, `/profile` | `connected_preference_command` | `accept_browser_preference_command_scenario_and_security_owner` |
| `auth` | `DELETE` | `/prefs/:key` | `/login`, `/profile` | `connected_preference_command` | `accept_browser_preference_command_scenario_and_security_owner` |
| `budget` | `GET` | `/dict/cost-subjects` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_read` | `accept_browser_budget_scenario_and_production_identity` |
| `budget` | `GET` | `/proceedings` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_read` | `accept_browser_budget_scenario_and_production_identity` |
| `budget` | `GET` | `/users-in-bu` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_scope_read` | `accept_browser_budget_scope_scenario_and_production_identity` |
| `budget` | `GET` | `/expenses` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_read` | `accept_browser_expense_scenario_and_production_identity` |
| `budget` | `GET` | `/expenses/:guid` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_detail_read` | `accept_browser_expense_detail_scenario_and_production_identity` |
| `budget` | `POST` | `/expenses` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_command` | `accept_browser_expense_command_scenario_and_finance_owner` |
| `budget` | `POST` | `/expenses/:guid/submit-for-approval` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_command` | `accept_browser_expense_command_scenario_and_finance_owner` |
| `budget` | `POST` | `/expenses/:guid/sync-from-workflow` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `budget` | `PUT` | `/expenses/:guid` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_command` | `accept_browser_expense_command_scenario_and_finance_owner` |
| `budget` | `DELETE` | `/expenses/:guid` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_command` | `accept_browser_expense_command_scenario_and_finance_owner` |
| `budget` | `GET` | `/my-loan-balance` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_scope_read` | `accept_browser_budget_scope_scenario_and_production_identity` |
| `budget` | `POST` | `/budget-check` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_budget_check_read` | `accept_browser_budget_check_scenario_and_finance_owner` |
| `budget` | `POST` | `/expenses/:guid/auto-offset` | `/expenses`, `/expenses/new`, `/expenses/:guid` | `connected_expense_command` | `accept_browser_expense_command_scenario_and_finance_owner` |
| `cashflow` | `GET` | `/forecast` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `GET` | `/forecast-v3` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `GET` | `/forecast/detail` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `GET` | `/inflow` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `GET` | `/net` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `GET` | `/gap-alert` | `/cashflow` | `connected_cashflow_read` | `accept_browser_cashflow_scenario_and_production_identity` |
| `cashflow` | `POST` | `/ai-explain` | `/cashflow` | `connected_cashflow_ai_explain_candidate` | `accept_browser_cashflow_ai_scenario_and_finance_owner` |
| `cbs` | `GET` | `/r-master` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `GET` | `/dict` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `POST` | `/dict` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `POST` | `/dict/batch-adjust` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `GET` | `/dict/f-balance` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `GET` | `/versions` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `POST` | `/versions/clone` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `POST` | `/versions/freeze` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `POST` | `/versions/activate` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `GET` | `/versions/compare` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `GET` | `/r0/queue` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `POST` | `/r0/resolve` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/approval-rules` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `GET` | `/approval-rules/pick` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `GET` | `/demo/contracts` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `POST` | `/demo/contracts` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `PUT` | `/demo/contracts/:id/state` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/demo/legacy` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `DELETE` | `/demo/clear` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/submit-approval` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/approve` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/reject` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/contracts/:id/mark-paid` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `GET` | `/changes` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_read` | `accept_browser_cbs_scenario_and_production_identity` |
| `cbs` | `POST` | `/changes` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/changes/:id/submit-approval` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/changes/:id/approve` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `not_connected` | `implement_authenticated_command_and_audit` |
| `cbs` | `POST` | `/approval-rules` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `PUT` | `/approval-rules/:guid` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cbs` | `DELETE` | `/approval-rules/:guid` | `/cbs/dict`, `/cbs/versions`, `/cbs/r0-queue`, `/cbs/approval-config` | `connected_cbs_command` | `accept_browser_cbs_command_scenario_and_finance_owner` |
| `cost` | `GET` | `/contracts` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `GET` | `/contracts/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `GET` | `/payment-applies` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `GET` | `/dynamic-cost` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `GET` | `/dynamic-cost/:guid/remarks` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `POST` | `/contracts` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_contract_source_command` | `accept_browser_cost_contract_source_command_scenario_and_operations_owner` |
| `cost` | `POST` | `/payment-applies` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_payment_source_command` | `accept_browser_cost_payment_source_command_scenario_and_finance_owner` |
| `cost` | `POST` | `/dynamic-cost` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_dynamic_source_command` | `accept_browser_cost_dynamic_source_command_scenario_and_operations_owner` |
| `cost` | `PUT` | `/contracts/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_contract_source_command` | `accept_browser_cost_contract_source_command_scenario_and_operations_owner` |
| `cost` | `DELETE` | `/contracts/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_contract_source_command` | `accept_browser_cost_contract_source_command_scenario_and_operations_owner` |
| `cost` | `PUT` | `/payment-applies/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_payment_source_command` | `accept_browser_cost_payment_source_command_scenario_and_finance_owner` |
| `cost` | `DELETE` | `/payment-applies/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_payment_source_command` | `accept_browser_cost_payment_source_command_scenario_and_finance_owner` |
| `cost` | `PUT` | `/dynamic-cost/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_dynamic_source_command` | `accept_browser_cost_dynamic_source_command_scenario_and_operations_owner` |
| `cost` | `DELETE` | `/dynamic-cost/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_dynamic_source_command` | `accept_browser_cost_dynamic_source_command_scenario_and_operations_owner` |
| `cost` | `GET` | `/contracts/:guid/milestones` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `POST` | `/contracts/:guid/milestones` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_milestone_source_command` | `accept_browser_cost_milestone_source_command_scenario_and_operations_owner` |
| `cost` | `PUT` | `/milestones/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_milestone_source_command` | `accept_browser_cost_milestone_source_command_scenario_and_operations_owner` |
| `cost` | `DELETE` | `/milestones/:guid` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_milestone_source_command` | `accept_browser_cost_milestone_source_command_scenario_and_operations_owner` |
| `cost` | `GET` | `/milestones/:guid/check` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_source_read` | `accept_browser_cost_source_scenario_and_production_identity` |
| `cost` | `POST` | `/milestones/:guid/trigger-event` | `/contracts`, `/contracts/:guid`, `/payment-applies`, `/dynamic-cost`, `/cost-dashboard-v3` | `connected_cost_milestone_source_command` | `accept_browser_cost_milestone_source_command_scenario_and_operations_owner` |
| `dashboard` | `GET` | `/group/overview` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/group/funnel` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/group/top-anomalies` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/project/:projGuid/kpi` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/project/:projGuid/anomalies` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/v2/group` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `dashboard` | `GET` | `/v3/group` | `/dashboard`, `/dashboard-v3`, `/cockpit` | `connected_dashboard_read` | `accept_browser_dashboard_scenario_and_production_identity` |
| `export` | `POST` | `/excel` | `/api/company/export/excel` | `connected_report_export_xlsx` | `accept_export_scope_and_production_identity` |
| `fund` | `GET` | `/plans` | `/fund/plan` | `connected_fund_read` | `accept_browser_fund_scenario_and_production_identity` |
| `fund` | `POST` | `/plans` | `/fund/plan` | `connected_fund_command_form` | `accept_browser_fund_command_scenario_and_finance_owner` |
| `fund` | `PUT` | `/plans/:guid` | `/fund/plan` | `connected_fund_command_form` | `accept_browser_fund_command_scenario_and_finance_owner` |
| `fund` | `DELETE` | `/plans/:guid` | `/fund/plan` | `connected_fund_command_form` | `accept_browser_fund_command_scenario_and_finance_owner` |
| `fund` | `GET` | `/gap-analysis` | `/fund/plan` | `connected_fund_read` | `accept_browser_fund_scenario_and_production_identity` |
| `fund` | `GET` | `/dispatches` | `/fund/plan` | `connected_fund_read` | `accept_browser_fund_scenario_and_production_identity` |
| `fund` | `POST` | `/dispatches` | `/fund/plan` | `connected_fund_command_form` | `accept_browser_fund_command_scenario_and_finance_owner` |
| `fund` | `POST` | `/dispatches/:guid/approve` | `/fund/plan` | `connected_fund_command_form` | `accept_browser_fund_command_scenario_and_finance_owner` |
| `import` | `GET` | `/:bizType/template` | — | `connected_import_template_read` | `accept_import_template_read_and_production_identity` |
| `import` | `POST` | `/:bizType` | — | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/versions` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/versions/:versionGuid/indices` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `PUT` | `/indices/:indexGuid` | `/investment` | `connected_investment_command_candidate` | `accept_browser_investment_command_scenario_and_investment_owner` |
| `investment` | `GET` | `/projects/:projGuid/profit-summary` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/meta/dimensions` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `POST` | `/projects/:projGuid/excel-imports` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/excel-imports` | `/investment` | `connected_investment_import_read` | `accept_browser_investment_import_scenario_and_production_identity` |
| `investment` | `GET` | `/excel-imports/:importGuid/bridge-plan` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/excel-imports/:importGuid` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/excel-imports/:importGuid/index-upsert-preview` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `POST` | `/excel-imports/:importGuid/index-upsert` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `POST` | `/projects/:projGuid/versions` | `/investment` | `connected_investment_command_candidate` | `accept_browser_investment_command_scenario_and_investment_owner` |
| `investment` | `POST` | `/projects/:projGuid/versions/:versionGuid/activate` | `/investment` | `connected_investment_command_candidate` | `accept_browser_investment_command_scenario_and_investment_owner` |
| `investment` | `POST` | `/versions/:versionGuid/indices` | `/investment` | `connected_investment_command_candidate` | `accept_browser_investment_command_scenario_and_investment_owner` |
| `investment` | `DELETE` | `/projects/:projGuid/versions/:versionGuid` | `/investment` | `connected_investment_command_candidate` | `accept_browser_investment_command_scenario_and_investment_owner` |
| `investment` | `DELETE` | `/indices/:indexGuid` | `/investment` | `connected_investment_command_candidate` | `accept_browser_investment_command_scenario_and_investment_owner` |
| `investment` | `GET` | `/projects/:projGuid/sensitivity` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `POST` | `/projects/:projGuid/ai-explain` | `/investment` | `connected_investment_ai_explain_candidate` | `accept_browser_investment_ai_scenario_and_investment_owner` |
| `investment` | `GET` | `/excel-imports/:importGuid/profit-table` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/excel-imports/:importGuid/plan-line-preview` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `POST` | `/excel-imports/:importGuid/plan-lines/import` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/plan-lines` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `PUT` | `/plan-lines/:lineGuid` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/subject-mappings` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `PUT` | `/projects/:projGuid/subject-mappings` | `/investment` | `not_connected` | `implement_authenticated_command_and_audit` |
| `investment` | `GET` | `/projects/:projGuid/profit-cockpit` | `/investment` | `connected_investment_read` | `accept_browser_investment_scenario_and_production_identity` |
| `investment` | `GET` | `/projects/:projGuid/profit-actual` | `/investment` | `connected_investment_boundary` | `accept_investment_actual_gate_and_finance_owner` |
| `investment` | `GET` | `/projects/:projGuid/profit-actual-v2` | `/investment` | `connected_cost_dashboard_read` | `accept_browser_cost_dashboard_scenario_and_production_identity` |
| `invoice` | `GET` | `/in` | `/invoice` | `connected_invoice_source_read` | `accept_browser_invoice_source_scenario_and_production_identity` |
| `invoice` | `POST` | `/in` | `/invoice` | `connected_invoice_command` | `accept_browser_invoice_command_scenario_and_finance_owner` |
| `invoice` | `DELETE` | `/in/:guid` | `/invoice` | `connected_invoice_command` | `accept_browser_invoice_command_scenario_and_finance_owner` |
| `invoice` | `GET` | `/out` | `/invoice` | `connected_invoice_source_read` | `accept_browser_invoice_source_scenario_and_production_identity` |
| `invoice` | `POST` | `/out` | `/invoice` | `connected_invoice_command` | `accept_browser_invoice_command_scenario_and_finance_owner` |
| `invoice` | `DELETE` | `/out/:guid` | `/invoice` | `connected_invoice_command` | `accept_browser_invoice_command_scenario_and_finance_owner` |
| `invoice` | `GET` | `/tax-ledger` | `/invoice` | `connected_invoice_source_read` | `accept_browser_invoice_source_scenario_and_production_identity` |
| `loan` | `GET` | `/loans` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_read` | `accept_browser_loan_scenario_and_production_identity` |
| `loan` | `GET` | `/loans/:guid` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_read` | `accept_browser_loan_scenario_and_production_identity` |
| `loan` | `POST` | `/loans` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `POST` | `/loans/:guid/submit-for-approval` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `POST` | `/loans/:guid/offset` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `POST` | `/loans/:guid/sync-from-workflow` | `/loans`, `/loans/new`, `/loans/:guid` | `not_connected` | `implement_authenticated_command_and_audit` |
| `loan` | `PUT` | `/loans/:guid` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `loan` | `DELETE` | `/loans/:guid` | `/loans`, `/loans/new`, `/loans/:guid` | `connected_loan_command` | `accept_browser_loan_command_scenario_and_finance_owner` |
| `marketing` | `GET` | `/campaigns` | `/marketing` | `connected_marketing_read` | `accept_browser_marketing_scenario_and_production_identity` |
| `marketing` | `POST` | `/campaigns` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `PUT` | `/campaigns/:guid` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `DELETE` | `/campaigns/:guid` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `GET` | `/placements` | `/marketing` | `connected_marketing_read` | `accept_browser_marketing_scenario_and_production_identity` |
| `marketing` | `POST` | `/placements` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `PUT` | `/placements/:guid/effect` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `GET` | `/channels` | `/marketing` | `connected_marketing_read` | `accept_browser_marketing_scenario_and_production_identity` |
| `marketing` | `POST` | `/channels` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `DELETE` | `/channels/:guid` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `GET` | `/materials` | `/marketing` | `connected_marketing_read` | `accept_browser_marketing_scenario_and_production_identity` |
| `marketing` | `POST` | `/materials` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `marketing` | `DELETE` | `/materials/:guid` | `/marketing` | `connected_marketing_command` | `accept_browser_marketing_command_scenario_and_marketing_owner` |
| `mdm` | `GET` | `/business-units/tree` | `/projects`, `/projects/:projGuid` | `connected_mdm_read` | `accept_browser_mdm_scenario_and_production_identity` |
| `mdm` | `GET` | `/projects` | `/projects`, `/projects/:projGuid` | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `mdm` | `GET` | `/projects/:projGuid/lifecycle` | `/projects`, `/projects/:projGuid` | `connected_project_read` | `accept_browser_project_scenario_and_production_identity` |
| `mdm` | `POST` | `/projects` | `/projects`, `/projects/:projGuid` | `connected_mdm_project_command` | `accept_browser_mdm_project_command_scenario_and_operations_owner` |
| `mdm` | `PUT` | `/projects/:projGuid` | `/projects`, `/projects/:projGuid` | `connected_mdm_project_command` | `accept_browser_mdm_project_command_scenario_and_operations_owner` |
| `mdm` | `DELETE` | `/projects/:projGuid` | `/projects`, `/projects/:projGuid` | `connected_mdm_project_command` | `accept_browser_mdm_project_command_scenario_and_operations_owner` |
| `notify` | `GET` | `/messages` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `GET` | `/messages/unread-count` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `POST` | `/messages/:guid/read` | `/inbox`, `/notify-config` | `connected_notification_message_command` | `accept_browser_notification_message_scenario_and_security_owner` |
| `notify` | `POST` | `/messages/read-all` | `/inbox`, `/notify-config` | `connected_notification_message_command` | `accept_browser_notification_message_scenario_and_security_owner` |
| `notify` | `GET` | `/subscriptions` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `POST` | `/subscriptions` | `/inbox`, `/notify-config` | `connected_notification_subscription_command` | `accept_browser_notification_subscription_scenario_and_security_owner` |
| `notify` | `PATCH` | `/subscriptions/:id` | `/inbox`, `/notify-config` | `connected_notification_subscription_command` | `accept_browser_notification_subscription_scenario_and_security_owner` |
| `notify` | `DELETE` | `/subscriptions/:id` | `/inbox`, `/notify-config` | `connected_notification_subscription_command` | `accept_browser_notification_subscription_scenario_and_security_owner` |
| `notify` | `GET` | `/config` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `PUT` | `/config` | `/inbox`, `/notify-config` | `connected_notification_config_command_candidate` | `accept_browser_notification_config_candidate_and_security_owner` |
| `notify` | `POST` | `/config/test-webhook` | `/inbox`, `/notify-config` | `connected_notification_webhook_test_candidate` | `accept_browser_notification_webhook_test_candidate_and_security_owner` |
| `notify` | `GET` | `/email-outbox` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `POST` | `/digest/dispatch` | `/inbox`, `/notify-config` | `connected_notification_digest_dispatch_candidate` | `accept_browser_notification_digest_candidate_and_security_owner` |
| `notify` | `GET` | `/digest/preview` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `GET` | `/digest/log` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `POST` | `/email-outbox/test` | `/inbox`, `/notify-config` | `connected_notification_email_command_candidate` | `accept_browser_notification_email_candidate_and_security_owner` |
| `notify` | `POST` | `/email-outbox/:eid/redeliver` | `/inbox`, `/notify-config` | `connected_notification_email_command_candidate` | `accept_browser_notification_email_candidate_and_security_owner` |
| `notify` | `GET` | `/llm-providers` | `/inbox`, `/notify-config` | `connected_notification_read` | `accept_browser_notification_scenario_and_production_identity` |
| `notify` | `POST` | `/llm-test` | `/inbox`, `/notify-config` | `connected_ai_provider_test_candidate` | `accept_browser_ai_provider_test_candidate_and_security_owner` |
| `plan` | `GET` | `/projects/:projGuid/tasks` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `plan` | `GET` | `/tasks/:guid` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `plan` | `POST` | `/tasks/:guid/report` | `/project-plan` | `connected_project_plan_command` | `accept_browser_project_plan_command_scenario_and_operations_owner` |
| `plan` | `GET` | `/projects/:projGuid/plan-summary` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `plan` | `POST` | `/tasks` | `/project-plan` | `connected_project_plan_command` | `accept_browser_project_plan_command_scenario_and_operations_owner` |
| `plan` | `PUT` | `/tasks/:guid` | `/project-plan` | `connected_project_plan_command` | `accept_browser_project_plan_command_scenario_and_operations_owner` |
| `plan` | `DELETE` | `/tasks/:guid` | `/project-plan` | `connected_project_plan_command` | `accept_browser_project_plan_command_scenario_and_operations_owner` |
| `plan` | `POST` | `/ai-suggest-plan` | `/project-plan` | `plan_ai_suggestion_candidate` | `accept_browser_plan_ai_scenario_and_operations_owner` |
| `plan` | `GET` | `/tasks/:guid/delay-impact` | `/project-plan` | `connected_project_plan_read` | `accept_browser_project_plan_scenario_and_production_identity` |
| `progress` | `GET` | `/progress` | `/project/progress` | `connected_delivery_source_read` | `accept_browser_delivery_source_scenario_and_production_identity` |
| `progress` | `POST` | `/progress` | `/project/progress` | `connected_delivery_command` | `accept_browser_delivery_command_scenario_and_operations_owner` |
| `progress` | `PUT` | `/progress/:guid/report` | `/project/progress` | `connected_delivery_command` | `accept_browser_delivery_command_scenario_and_operations_owner` |
| `progress` | `DELETE` | `/progress/:guid` | `/project/progress` | `connected_delivery_command` | `accept_browser_delivery_command_scenario_and_operations_owner` |
| `progress` | `GET` | `/outputs` | `/project/progress` | `connected_delivery_source_read` | `accept_browser_delivery_source_scenario_and_production_identity` |
| `progress` | `POST` | `/outputs` | `/project/progress` | `connected_delivery_command` | `accept_browser_delivery_command_scenario_and_operations_owner` |
| `progress` | `POST` | `/outputs/:guid/confirm` | `/project/progress` | `connected_delivery_command` | `accept_browser_delivery_command_scenario_and_operations_owner` |
| `rbac` | `GET` | `/me` | `/users` | `connected_rbac_observation_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `rbac` | `GET` | `/roles` | `/users` | `connected_rbac_observation_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `rbac` | `GET` | `/roles/:code` | `/users` | `connected_rbac_observation_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `rbac` | `GET` | `/users` | `/users` | `connected_rbac_user_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `rbac` | `POST` | `/users` | `/users` | `connected_rbac_user_command_candidate` | `accept_browser_user_command_scenario_and_identity_owner` |
| `rbac` | `PUT` | `/users/:userId` | `/users` | `connected_rbac_user_command_candidate` | `accept_browser_user_command_scenario_and_identity_owner` |
| `rbac` | `POST` | `/users/:userId/toggle` | `/users` | `connected_rbac_user_command_candidate` | `accept_browser_user_command_scenario_and_identity_owner` |
| `rbac` | `POST` | `/users/:userId/reset-password` | `/users` | `connected_rbac_user_command_candidate` | `accept_browser_user_command_scenario_and_identity_owner` |
| `rbac` | `POST` | `/users/:userId/roles` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `GET` | `/permission-catalog` | `/users` | `connected_rbac_observation_read` | `accept_browser_user_roster_scenario_and_super_user_owner` |
| `rbac` | `POST` | `/roles` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `rbac` | `DELETE` | `/roles/:code` | `/users` | `not_connected` | `implement_authenticated_command_and_audit` |
| `reports` | `GET` | `/cost-summary` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/contract-payment-ledger` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/supplier-analysis` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/approval-efficiency` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/project-stage-matrix` | `/reports`, `/report-builder` | `connected_report_read` | `accept_browser_report_scenario_and_production_identity` |
| `reports` | `GET` | `/templates/meta` | `/reports`, `/report-builder` | `connected_report_builder_read` | `accept_browser_report_builder_scenario_and_production_identity` |
| `reports` | `POST` | `/templates/run` | `/reports`, `/report-builder` | `connected_report_builder_command` | `accept_browser_report_builder_command_scenario_and_report_owner` |
| `reports` | `GET` | `/templates` | `/reports`, `/report-builder` | `connected_report_builder_read` | `accept_browser_report_builder_scenario_and_production_identity` |
| `reports` | `POST` | `/templates` | `/reports`, `/report-builder` | `connected_report_builder_command` | `accept_browser_report_builder_command_scenario_and_report_owner` |
| `reports` | `DELETE` | `/templates/:id` | `/reports`, `/report-builder` | `connected_report_builder_command` | `accept_browser_report_builder_command_scenario_and_report_owner` |
| `sales` | `GET` | `/revenues` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_source_read` | `accept_browser_sales_source_scenario_and_production_identity` |
| `sales` | `POST` | `/revenues` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `PUT` | `/revenues/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `DELETE` | `/revenues/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `POST` | `/revenues/:guid/confirm-received` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `GET` | `/customers` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_source_read` | `accept_browser_sales_source_scenario_and_production_identity` |
| `sales` | `POST` | `/customers` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `PUT` | `/customers/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `DELETE` | `/customers/:guid` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `not_connected` | `implement_authenticated_command_and_audit` |
| `sales` | `GET` | `/subscriptions` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_source_read` | `accept_browser_sales_source_scenario_and_production_identity` |
| `sales` | `POST` | `/subscriptions` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `POST` | `/subscriptions/:guid/convert-to-contract` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `GET` | `/contracts` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_source_read` | `accept_browser_sales_source_scenario_and_production_identity` |
| `sales` | `GET` | `/mortgages` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_source_read` | `accept_browser_sales_source_scenario_and_production_identity` |
| `sales` | `POST` | `/mortgages` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `POST` | `/mortgages/:guid/approve` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `POST` | `/mortgages/:guid/release` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `GET` | `/refunds` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_source_read` | `accept_browser_sales_source_scenario_and_production_identity` |
| `sales` | `POST` | `/refunds` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `sales` | `POST` | `/refunds/:guid/approve` | `/sales/revenues`, `/sales/customers`, `/sales/subscriptions`, `/sales/contracts`, `/sales/mortgages` | `connected_sales_command` | `accept_browser_sales_command_scenario_and_sales_finance_owner` |
| `srm` | `GET` | `/categories` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_dictionary_read` | `accept_browser_supplier_dictionary_scenario_and_production_identity` |
| `srm` | `GET` | `/dict/eval-results` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_dictionary_read` | `accept_browser_supplier_dictionary_scenario_and_production_identity` |
| `srm` | `GET` | `/dict/sources` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_dictionary_read` | `accept_browser_supplier_dictionary_scenario_and_production_identity` |
| `srm` | `GET` | `/providers` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `srm` | `GET` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `srm` | `POST` | `/providers` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_source_command` | `accept_browser_supplier_source_command_scenario_and_procurement_owner` |
| `srm` | `PATCH` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_source_command` | `accept_browser_supplier_source_command_scenario_and_procurement_owner` |
| `srm` | `GET` | `/stats/overview` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_read` | `accept_browser_supplier_scenario_and_production_identity` |
| `srm` | `PUT` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_source_command` | `accept_browser_supplier_source_command_scenario_and_procurement_owner` |
| `srm` | `DELETE` | `/providers/:guid` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_source_command` | `accept_browser_supplier_source_command_scenario_and_procurement_owner` |
| `srm` | `GET` | `/providers/:guid/risk` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_risk_read` | `accept_browser_supplier_risk_scenario_and_production_identity` |
| `srm` | `POST` | `/providers/rescore-all` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `supplier_rescore_candidate` | `accept_browser_supplier_risk_scenario_and_procurement_owner` |
| `srm` | `GET` | `/risk-board` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_risk_read` | `accept_browser_supplier_risk_scenario_and_production_identity` |
| `srm` | `GET` | `/providers/:guid/check-sign` | `/srm/providers`, `/srm/providers/:guid`, `/srm/risk-board` | `connected_supplier_boundary` | `accept_supplier_signature_gate_and_procurement_owner` |
| `tender` | `GET` | `/tenders` | `/tender` | `connected_tender_source_read` | `accept_browser_tender_source_scenario_and_production_identity` |
| `tender` | `POST` | `/tenders` | `/tender` | `connected_tender_source_command` | `accept_browser_tender_source_command_scenario_and_procurement_owner` |
| `tender` | `PUT` | `/tenders/:guid/state` | `/tender` | `connected_tender_state_candidate` | `accept_browser_tender_state_scenario_and_procurement_owner` |
| `tender` | `DELETE` | `/tenders/:guid` | `/tender` | `connected_tender_source_command` | `accept_browser_tender_source_command_scenario_and_procurement_owner` |
| `tender` | `GET` | `/awards` | `/tender` | `connected_tender_source_read` | `accept_browser_tender_source_scenario_and_production_identity` |
| `tender` | `POST` | `/awards` | `/tender` | `connected_tender_award_candidate` | `accept_browser_tender_award_scenario_and_procurement_owner` |
| `tender` | `GET` | `/splits` | `/tender` | `connected_tender_source_read` | `accept_browser_tender_source_scenario_and_production_identity` |
| `tender` | `POST` | `/splits` | `/tender` | `connected_tender_split_source_command` | `accept_browser_tender_split_command_scenario_and_procurement_owner` |
| `warning` | `GET` | `/badge` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `GET` | `/` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `GET` | `/rules` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `PATCH` | `/rules/:code` | `/warning`, `/warning-rules` | `connected_warning_rule_command_candidate` | `accept_browser_warning_rule_command_scenario_and_warning_owner` |
| `warning` | `GET` | `/scans` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `POST` | `/scan` | `/warning`, `/warning-rules` | `connected_warning_scan_preview_read` | `accept_browser_warning_scan_preview_scenario_and_warning_owner` |
| `warning` | `POST` | `/:guid/resolve` | `/warning`, `/warning-rules` | `connected_warning_command` | `accept_browser_warning_command_scenario_and_warning_owner` |
| `warning` | `POST` | `/:guid/ignore` | `/warning`, `/warning-rules` | `connected_warning_command` | `accept_browser_warning_command_scenario_and_warning_owner` |
| `warning` | `GET` | `/custom-rules` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `POST` | `/custom-rules` | `/warning`, `/warning-rules` | `connected_warning_custom_rule_command_candidate` | `accept_browser_warning_custom_rule_scenario_and_warning_owner` |
| `warning` | `DELETE` | `/custom-rules/:code` | `/warning`, `/warning-rules` | `connected_warning_custom_rule_command_candidate` | `accept_browser_warning_custom_rule_scenario_and_warning_owner` |
| `warning` | `POST` | `/custom-rules/preview` | `/warning`, `/warning-rules` | `connected_warning_custom_rule_preview_candidate` | `accept_browser_warning_custom_rule_preview_scenario_and_warning_owner` |
| `warning` | `GET` | `/rule-templates` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `POST` | `/:guid/to-ticket` | `/warning`, `/warning-rules` | `connected_warning_ticket_command_candidate` | `accept_browser_warning_ticket_scenario_and_warning_owner` |
| `warning` | `GET` | `/tickets/mine` | `/warning`, `/warning-rules` | `connected_warning_read` | `accept_browser_warning_scenario_and_production_identity` |
| `warning` | `PATCH` | `/tickets/:id/status` | `/warning`, `/warning-rules` | `connected_warning_ticket_transition_candidate` | `accept_browser_warning_ticket_scenario_and_warning_owner` |
| `warning` | `PATCH` | `/tickets/:id/reassign` | `/warning`, `/warning-rules` | `connected_warning_ticket_transition_candidate` | `accept_browser_warning_ticket_scenario_and_warning_owner` |
| `warning` | `PATCH` | `/tickets/:id/extend` | `/warning`, `/warning-rules` | `connected_warning_ticket_transition_candidate` | `accept_browser_warning_ticket_scenario_and_warning_owner` |
| `webhook` | `GET` | `/config` | `/webhook-config` | `connected_webhook_read` | `accept_browser_webhook_scenario_and_production_identity` |
| `webhook` | `PUT` | `/config/:platform` | `/webhook-config` | `connected_webhook_config_command_candidate` | `accept_browser_webhook_config_candidate_and_security_owner` |
| `webhook` | `POST` | `/test/:platform` | `/webhook-config` | `connected_webhook_test_delivery_candidate` | `accept_browser_webhook_test_candidate_and_security_owner` |
| `webhook` | `POST` | `/scan-overdue/preview` | `/webhook-config` | `connected_webhook_overdue_preview_read` | `accept_browser_webhook_preview_scenario_and_production_identity` |
| `webhook` | `POST` | `/scan-overdue` | `/webhook-config` | `connected_webhook_overdue_scan_candidate` | `accept_browser_webhook_scan_candidate_and_security_owner` |
| `workflow` | `GET` | `/tasks/mine` | `/tasks` | `connected_workflow_observation_read` | `accept_browser_workflow_observation_scenario_and_production_identity` |
| `workflow` | `GET` | `/tasks/initiated` | `/tasks` | `connected_workflow_observation_read` | `accept_browser_workflow_observation_scenario_and_production_identity` |
| `workflow` | `GET` | `/instances/by-biz` | `/tasks` | `connected_workflow_observation_read` | `accept_browser_workflow_observation_scenario_and_production_identity` |
| `workflow` | `GET` | `/instances/:piGuid` | `/tasks` | `connected_workflow_observation_read` | `accept_browser_workflow_observation_scenario_and_production_identity` |
| `workflow` | `POST` | `/instances/:piGuid/approve` | `/tasks` | `connected_workflow_command_candidate` | `accept_browser_workflow_command_candidate_and_operations_owner` |
| `workflow` | `POST` | `/instances/:piGuid/reject` | `/tasks` | `connected_workflow_command_candidate` | `accept_browser_workflow_command_candidate_and_operations_owner` |
| `workflow` | `GET` | `/process-defs` | `/tasks` | `connected_workflow_definition_read` | `accept_browser_workflow_definition_scenario_and_production_identity` |
| `workflow` | `GET` | `/process-defs/:processKey/preview` | `/tasks` | `connected_workflow_definition_read` | `accept_browser_workflow_definition_scenario_and_production_identity` |
| `workflow` | `GET` | `/tasks/my-history` | `/tasks` | `connected_workflow_observation_read` | `accept_browser_workflow_observation_scenario_and_production_identity` |
| `workflow` | `POST` | `/instances` | `/tasks` | `connected_workflow_command_candidate` | `accept_browser_workflow_command_candidate_and_operations_owner` |
| `workflow` | `POST` | `/instances/:piGuid/cosigners` | `/tasks` | `connected_workflow_command_candidate` | `accept_browser_workflow_command_candidate_and_operations_owner` |
| `workflow` | `POST` | `/instances/:piGuid/transfer` | `/tasks` | `connected_workflow_command_candidate` | `accept_browser_workflow_command_candidate_and_operations_owner` |
