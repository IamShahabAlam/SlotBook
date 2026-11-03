-- Read model. The app reads bookings only through this view; security_invoker makes it obey the tables' RLS.
-- payable = total_fee - discount; balance_due = 0 unless pending; amount_collected = money actually kept.

create view public.booking_details
with (security_invoker = true) as
select
  b.booking_id,
  b.client_id,
  b.request_uid,
  b.invoice_number,
  b.invoice_no,
  b.resource_id,
  r.name                     as resource_name,
  r.resource_type_id,
  rt.name                    as resource_type_name,
  rt.short_name              as resource_type_short_name,
  b.booking_session_id,
  s.label                    as booking_session_label,
  b.booking_date,
  b.start_minute,
  b.end_minute,
  b.duration_minutes,
  b.starts_at,
  b.ends_at,
  b.customer_name,
  b.customer_phone,
  b.customer_email,
  b.notes,
  b.pricing_mode,
  b.hourly_rate,
  b.total_fee,
  b.discount,
  b.advance_paid,
  (b.total_fee - b.discount) as payable,
  case when b.booking_status_id = 1
       then b.total_fee - b.discount - b.advance_paid else 0 end as balance_due,
  case b.booking_status_id
       when 2 then b.total_fee - b.discount     -- paid: full payable collected
       when 3 then b.advance_paid               -- cancelled, advance kept
       when 4 then 0                            -- refunded
       else b.advance_paid                      -- pending
  end                        as amount_collected,
  b.balance_settled_at,
  b.booking_status_id,
  bs.status_code             as booking_status_code,
  b.cancelled_at,
  b.cancel_reason,
  b.advance_returned,
  b.created_by_user_id,
  cu.full_name               as created_by_name,
  b.updated_by_user_id,
  b.cancelled_by_user_id,
  b.data_status,
  b.created_at,
  b.updated_at
from public.bookings b
join public.resources r         on r.resource_id = b.resource_id
join public.resource_types rt   on rt.resource_type_id = r.resource_type_id
join public.booking_statuses bs on bs.booking_status_id = b.booking_status_id
left join public.booking_sessions s on s.booking_session_id = b.booking_session_id
left join public.users cu       on cu.user_id = b.created_by_user_id;

grant select on public.booking_details to authenticated;

-- Full booking row from the read model, used as the return value of booking RPCs.
create or replace function private.booking_json(p_booking_id integer)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select to_jsonb(d) from public.booking_details d where d.booking_id = p_booking_id
$$;
