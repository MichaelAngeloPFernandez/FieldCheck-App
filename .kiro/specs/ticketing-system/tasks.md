# Implementation Tasks: Ticketing System

## Overview

The backend routes (`ticketRoutes.js`, `templateRoutes.js`) and Flutter models/screens are largely in place. The remaining work is:
1. Harden the backend with missing guards and the `GET /api/tickets/employees` endpoint
2. Refactor `ticketService.js` to use correct field names
3. Add SLA finalization on close/verify transitions
4. Add missing indexes to the `Ticket` model
5. Wire the ticket screens into the admin dashboard navigation
6. Add a `TicketService.getEmployees()` method to the Flutter service
7. Update the admin ticket creation screen to support employee assignment
8. Write property-based and integration tests

---

## Tasks

- [x] 1. Harden backend `ticketRoutes.js` with missing business rules
  - [x] 1.1 Add `GET /api/tickets/employees` endpoint — returns active employees scoped to admin's company (`role: 'employee'`, `isActive: true`), fields: `_id`, `name`, `employeeId`, `status`
  - [x] 1.2 Add employee-role validation on `assignee_id` in `POST /api/tickets` — look up user, verify `role === 'employee'`, return HTTP 400 if not found or wrong role
  - [x] 1.3 Add status guard in `PATCH /api/tickets/:id` — reject data/notes/assignee updates when `status === 'closed'` or `status === 'verified'` with HTTP 400
  - [x] 1.4 Add SLA finalization in `PATCH /api/tickets/:id/status` — on transition to `closed` or `verified`, set `sla_status` to `'on_time'` if `completedAt <= sla_deadline`, else keep `'overdue'`; if `sla_deadline` is null, keep `sla_status` null
  - [x] 1.5 Add employee access guard in `GET /api/tickets/:id` — if requesting user is an employee and `ticket.assignee` does not match `req.user._id`, return HTTP 403
  - [x] 1.6 Add `ticketAssigneeChanged` Socket.IO event in `PATCH /api/tickets/:id` when `assignee_id` changes, and log `action: 'assignee_updated'` to audit log

- [x] 2. Refactor `services/ticketService.js` to align with live Mongoose models
  - [x] 2.1 Replace stale field references: `template.jsonSchema` → `template.json_schema`, `template.slaSeconds` → `template.sla_seconds`, `template.serviceType` → `template.name`
  - [x] 2.2 Remove `statusHistory`, `slaDueAt`, `ticketNumber`, `templateId`, `templateVersion`, `requestedBy`, `slaCalculatedAt` references — replace with correct field names from the live `Ticket` schema
  - [x] 2.3 Rewrite `generateTicketNumber(companyId, companyCode)` to use `Counter.getNextSequence(companyId)` and format as `<companyCode>-<NNNN>`
  - [x] 2.4 Add `finalizeSlaStatus(ticket)` static method — sets `sla_status` to `'on_time'` or keeps `'overdue'` based on `completedAt` vs `sla_deadline`

- [x] 3. Add missing Mongoose indexes to `models/Ticket.js`
  - [x] 3.1 Add compound index `{ company: 1, isArchived: 1, createdAt: -1 }` for list query performance
  - [x] 3.2 Add compound index `{ sla_deadline: 1, status: 1 }` for SLA job performance

- [x] 4. Enhance Flutter `TicketService` with employees endpoint
  - [x] 4.1 Add `getEmployees()` static method to `lib/services/ticket_service.dart` — calls `GET /api/tickets/employees`, returns `List<Map<String, dynamic>>`

- [x] 5. Update `EmployeeTicketCreateScreen` to support admin employee assignment
  - [x] 5.1 Add `isAdmin` parameter (or detect from `UserService`) to `employee_ticket_create_screen.dart`
  - [x] 5.2 When admin, load employees via `TicketService.getEmployees()` and render a `DropdownButtonFormField` for assignee selection
  - [x] 5.3 Pass selected `assigneeId` to `TicketService.createTicket()`

- [x] 6. Wire ticket screens into admin dashboard navigation
  - [x] 6.1 Confirm `AdminTicketListScreen` is already imported and used in `admin_dashboard_screen.dart` (it is — verify the tab index and label are correct)
  - [x] 6.2 Add a "Tickets" nav item to the admin navigation rail/drawer if not already present

- [x] 7. Write property-based and unit tests
  - [x] 7.1 Create `__tests__/unit/ticketing/validationService.property.test.js` — Property 2: for any schema + data, `validationService.validate()` result matches AJV directly (100 runs)
  - [x] 7.2 Create `__tests__/unit/ticketing/ticketCreation.property.test.js` — Property 3: ticket creation invariants (status=open, ticket_no format, SLA math) using fast-check (100 runs)
  - [x] 7.3 Create `__tests__/unit/ticketing/workflowTransition.property.test.js` — Property 10: workflow transition enforcement — allowed transitions return 200, disallowed return 400 (100 runs)
  - [x] 7.4 Create `__tests__/unit/ticketing/slaFinalization.unit.test.js` — unit tests for `TicketService.finalizeSlaStatus()`: on_time when completedAt ≤ sla_deadline, overdue when completedAt > sla_deadline, null when no sla_deadline

- [x] 8. Write integration test for full ticket lifecycle
  - [x] 8.1 Create `__tests__/integration/ticketing.integration.test.js` — full lifecycle: create ticket → in_progress → completed → verified → closed; assert status, completedAt, sla_status at each step; assert audit log entries exist; assert 403 on cross-company access
