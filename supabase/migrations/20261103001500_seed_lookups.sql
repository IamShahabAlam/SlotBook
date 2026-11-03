-- Lookup rows with fixed ids (needed in every environment). Dart mirrors these ids as constants.
-- business_profiles values are generated from lib/app/config/business/profiles.dart.

insert into public.roles (role_id, role_code, name, is_full_access, sort_order) values
  (1, 'owner', 'Owner', true,  1),
  (2, 'staff', 'Staff', false, 2);

insert into public.permissions (permission_id, permission_code, name, sort_order) values
  (1, 'booking.create',    'Create bookings',                      1),
  (2, 'booking.edit',      'Edit bookings',                        2),
  (3, 'booking.mark_paid', 'Mark bookings as paid',                3),
  (4, 'booking.cancel',    'Cancel bookings',                      4),
  (5, 'revenue.view',      'See revenue totals',                   5),
  (6, 'settings.edit',     'Change rates and business settings',   6),
  (7, 'users.manage',      'Manage staff and their rights',        7);

-- Default template for Staff (Owner has full access and is never stored here)
insert into public.role_permissions (role_permission_id, role_id, permission_id, is_allowed) values
  (1, 2, 1, true),   -- booking.create
  (2, 2, 2, true),   -- booking.edit
  (3, 2, 3, true),   -- booking.mark_paid
  (4, 2, 4, false),  -- booking.cancel
  (5, 2, 5, false),  -- revenue.view
  (6, 2, 6, false),  -- settings.edit
  (7, 2, 7, false);  -- users.manage

insert into public.booking_statuses (booking_status_id, status_code, name, color_key, sort_order) values
  (1, 'pending',   'Pending',   'warning', 1),
  (2, 'paid',      'Paid',      'success', 2),
  (3, 'cancelled', 'Cancelled', 'neutral', 3),
  (4, 'refunded',  'Refunded',  'info',    4);

-- Prices are placeholders until the owner sets them
insert into public.plans (plan_id, plan_code, name, duration_days, price, max_users, sort_order) values
  (1, 'trial',    'Trial',    14,   0, 2, 1),
  (2, 'monthly',  'Monthly',  30,   0, 3, 2),
  (3, 'yearly',   'Yearly',   365,  0, 3, 3),
  (4, 'lifetime', 'Lifetime', null, 0, 5, 4);

insert into public.business_profiles (
  business_profile_id, profile_code, name, default_terms,
  slot_step_minutes, min_duration_minutes, max_duration_minutes, default_duration_minutes,
  open_start_minute, open_end_minute, offers_full_day,
  pricing_mode, allow_discount, show_entry_pass, default_sessions, sort_order) values
  (1, 'sports_venue', 'Sports Venue', $json${
      "subject": "Ground", "resource": "Court", "resources": "Courts",
      "resource_type": "Sport", "customer": "Player", "fee": "Ground Fee",
      "place": "arena", "pass_hint": "Show at arena entry",
      "receipt_thanks": "Thank you for playing at ArenaBook grounds! Present this receipt at entry.",
      "cancel_reason_hint": "e.g. Player requested cancellation due to rain"}$json$,
   30, 30, 1440, 60, null, null, false, 1, true, true, '[]', 1),
  (2, 'space_rental', 'Space Rental', $json${
      "subject": "Space", "resource": "Space", "resources": "Spaces",
      "resource_type": "Property", "customer": "Customer", "fee": "Rental Fee",
      "place": "property", "pass_hint": "Show at reception",
      "receipt_thanks": "Thank you for booking with us! Show this receipt at reception.",
      "cancel_reason_hint": "e.g. Customer changed their plans"}$json$,
   60, 60, 1440, 120, null, null, true, 1, true, true, '[]', 2),
  (3, 'event_venue', 'Event Venue', $json${
      "subject": "Event", "resource": "Hall", "resources": "Halls",
      "resource_type": "Venue", "customer": "Client", "fee": "Venue Fee",
      "place": "venue", "pass_hint": "Show at the venue entrance",
      "receipt_thanks": "Thank you for choosing us for your event! Show this receipt at the venue.",
      "cancel_reason_hint": "e.g. Client postponed the event"}$json$,
   60, 60, 1440, 240, null, null, false, 2, true, true, $json$[
      {"label": "Lunch",    "start_minute": 720,  "end_minute": 1080, "sort_order": 1},
      {"label": "Dinner",   "start_minute": 1140, "end_minute": 1440, "sort_order": 2},
      {"label": "Full Day", "start_minute": 600,  "end_minute": 1380, "sort_order": 3}]$json$, 3),
  (4, 'vehicle_rental', 'Vehicle Rental', $json${
      "subject": "Rental", "resource": "Vehicle", "resources": "Vehicles",
      "resource_type": "Vehicle", "customer": "Customer", "fee": "Rental Fee",
      "place": "business", "pass_hint": "Show at vehicle pickup",
      "receipt_thanks": "Thank you for renting with us! Show this receipt at pickup.",
      "cancel_reason_hint": "e.g. Customer changed travel plans"}$json$,
   60, 60, 1440, 120, null, null, false, 1, true, true, '[]', 4);

-- keep identity sequences ahead of the explicit ids
select setval(pg_get_serial_sequence('public.roles', 'role_id'), (select max(role_id) from public.roles));
select setval(pg_get_serial_sequence('public.permissions', 'permission_id'), (select max(permission_id) from public.permissions));
select setval(pg_get_serial_sequence('public.role_permissions', 'role_permission_id'), (select max(role_permission_id) from public.role_permissions));
select setval(pg_get_serial_sequence('public.booking_statuses', 'booking_status_id'), (select max(booking_status_id) from public.booking_statuses));
select setval(pg_get_serial_sequence('public.plans', 'plan_id'), (select max(plan_id) from public.plans));
select setval(pg_get_serial_sequence('public.business_profiles', 'business_profile_id'), (select max(business_profile_id) from public.business_profiles));
