-- Booking validation helpers and the four booking writes (create, update, mark paid, cancel).
-- Pricing: the server decides. Hourly = round(minutes x frozen rate / 60); manual = the typed fee.
-- New bookings take the client's pricing mode; an edited booking keeps its own.

create or replace function private.validate_booking_time(
  p_client             public.clients,
  p_booking_date       date,
  p_start_minute       integer,
  p_end_minute         integer,
  p_booking_session_id integer,
  p_check_past         boolean)
returns void
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_duration     integer := p_end_minute - p_start_minute;
  v_today        date    := (now() at time zone p_client.timezone)::date;
  v_has_sessions boolean;
  v_session      public.booking_sessions;
  v_is_full_day  boolean;
  v_starts_at    timestamptz;
begin
  if p_booking_date is null or p_start_minute is null or p_end_minute is null
     or p_start_minute < 0 or p_start_minute >= 1440
     or p_end_minute <= p_start_minute or p_end_minute > 2880 then
    raise exception using errcode = 'AB021', message = 'Invalid booking time.';
  end if;

  if p_booking_date > v_today + 730 then
    raise exception using errcode = 'AB021', message = 'Bookings can be made up to 2 years ahead.';
  end if;

  select exists (select 1 from public.booking_sessions s
                  where s.client_id = p_client.client_id and s.data_status = 1)
    into v_has_sessions;

  if v_has_sessions then
    select s.* into v_session from public.booking_sessions s
     where s.booking_session_id = p_booking_session_id
       and s.client_id = p_client.client_id and s.data_status = 1;
    if not found or v_session.start_minute <> p_start_minute or v_session.end_minute <> p_end_minute then
      raise exception using errcode = 'AB021', message = 'Please choose one of the available sessions.';
    end if;
  else
    if p_booking_session_id is not null then
      raise exception using errcode = 'AB021', message = 'This business does not use sessions.';
    end if;

    v_is_full_day := p_client.offers_full_day and v_duration = 1440;

    if p_start_minute % p_client.slot_step_minutes <> 0 or v_duration % p_client.slot_step_minutes <> 0 then
      raise exception using errcode = 'AB021',
        message = format('Times must be in %s-minute steps.', p_client.slot_step_minutes);
    end if;

    if not v_is_full_day and (v_duration < p_client.min_duration_minutes
                              or v_duration > p_client.max_duration_minutes) then
      raise exception using errcode = 'AB021',
        message = format('Duration must be between %s and %s minutes.',
                         p_client.min_duration_minutes, p_client.max_duration_minutes);
    end if;

    -- opening hours may pass midnight (e.g. 960-1560 = 4 PM-2 AM); the early-morning tail
    -- of the previous night's window is the same window shifted by one day
    if p_client.open_start_minute is not null and not v_is_full_day and not (
         (p_start_minute >= p_client.open_start_minute and p_end_minute <= p_client.open_end_minute)
      or (p_start_minute >= p_client.open_start_minute - 1440 and p_end_minute <= p_client.open_end_minute - 1440)) then
      raise exception using errcode = 'AB021', message = 'This time is outside opening hours.';
    end if;
  end if;

  if p_check_past then
    v_starts_at := (p_booking_date::timestamp + make_interval(mins => p_start_minute)) at time zone p_client.timezone;
    if v_starts_at <= now() then
      raise exception using errcode = 'AB022', message = 'This time has already started. Please choose a later time.';
    end if;
  end if;
end;
$$;

create or replace function private.validate_money(p_client public.clients, p_fee integer, p_discount integer)
returns void
language plpgsql immutable set search_path = ''
as $$
begin
  if p_fee is null or p_fee <= 0 then
    raise exception using errcode = 'AB023', message = 'The price must be more than zero.';
  end if;
  if p_discount < 0 or p_discount > p_fee then
    raise exception using errcode = 'AB023', message = 'Discount must be between 0 and the fee.';
  end if;
  if p_discount > 0 and not p_client.allow_discount then
    raise exception using errcode = 'AB023', message = 'Discounts are not enabled for this business.';
  end if;
end;
$$;

create or replace function private.validate_customer(p_name text, p_phone text, p_email text, p_notes text)
returns void
language plpgsql immutable set search_path = ''
as $$
begin
  if p_name = '' then
    raise exception using errcode = 'AB028', message = 'Customer name is required.';
  end if;
  if p_phone !~ '^[0-9]{10,11}$' then
    raise exception using errcode = 'AB028', message = 'Phone number must have 10 or 11 digits.';
  end if;
  if p_email <> '' and p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception using errcode = 'AB028', message = 'Email address is not valid.';
  end if;
  if char_length(p_notes) > 120 then
    raise exception using errcode = 'AB028', message = 'Notes can be at most 120 characters.';
  end if;
end;
$$;

create or replace function public.create_booking(
  p_request_uid        uuid,
  p_resource_id        integer,
  p_booking_date       date,
  p_start_minute       integer,
  p_end_minute         integer,
  p_booking_session_id integer,
  p_customer_name      text,
  p_customer_phone     text,
  p_customer_email     text,
  p_notes              text,
  p_manual_fee         integer,
  p_discount           integer,
  p_advance_paid       integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx        record;
  v_client     public.clients;
  v_rate       integer;
  v_fee        integer;
  v_discount   integer := coalesce(p_discount, 0);
  v_advance    integer;
  v_invoice    integer;
  v_booking_id integer;
  v_name       text := trim(coalesce(p_customer_name, ''));
  v_phone      text := regexp_replace(coalesce(p_customer_phone, ''), '\D', '', 'g');
  v_email      text := lower(trim(coalesce(p_customer_email, '')));
  v_notes      text := trim(coalesce(p_notes, ''));
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('booking.create');

  -- idempotency: the same request sent twice returns the first result
  select b.booking_id into v_booking_id from public.bookings b
   where b.request_uid = p_request_uid and b.client_id = v_ctx.o_client_id;
  if v_booking_id is not null then
    return private.booking_json(v_booking_id);
  end if;

  perform private.require_writable_license(v_ctx.o_client_id);
  select c.* into v_client from public.clients c where c.client_id = v_ctx.o_client_id;

  select t.hourly_rate into v_rate
    from public.resources r
    join public.resource_types t on t.resource_type_id = r.resource_type_id
   where r.resource_id = p_resource_id and r.client_id = v_client.client_id
     and r.data_status = 1 and t.data_status = 1;
  if not found then
    raise exception using errcode = 'AB026', message = 'This resource is not available for booking.';
  end if;

  perform private.validate_customer(v_name, v_phone, v_email, v_notes);
  perform private.validate_booking_time(v_client, p_booking_date, p_start_minute, p_end_minute,
                                        p_booking_session_id, true);

  if v_client.pricing_mode = 1 then
    if v_rate is null then
      raise exception using errcode = 'AB023', message = 'No hourly rate is set for this resource type.';
    end if;
    v_fee := round((p_end_minute - p_start_minute) * v_rate / 60.0)::integer;
  else
    v_fee := p_manual_fee;
  end if;
  perform private.validate_money(v_client, v_fee, v_discount);
  v_advance := least(greatest(coalesce(p_advance_paid, 0), 0), v_fee - v_discount);

  -- counter + insert in one sub-block: if the insert fails, the counter increment is undone too
  begin
    update public.invoice_counters ic
       set last_invoice_number = ic.last_invoice_number + 1
     where ic.client_id = v_client.client_id
    returning ic.last_invoice_number into v_invoice;   -- row lock serialises numbering per client
    if v_invoice is null then
      raise exception 'Invoice counter missing for client %', v_client.client_id;
    end if;

    insert into public.bookings (
      client_id, request_uid, invoice_number, resource_id, booking_session_id,
      booking_date, start_minute, end_minute,
      customer_name, customer_phone, customer_email, notes,
      pricing_mode, hourly_rate, total_fee, discount, advance_paid,
      created_by_user_id, updated_by_user_id)
    values (
      v_client.client_id, p_request_uid, v_invoice, p_resource_id, p_booking_session_id,
      p_booking_date, p_start_minute, p_end_minute,
      v_name, v_phone, v_email, v_notes,
      v_client.pricing_mode, case when v_client.pricing_mode = 1 then v_rate else 0 end,
      v_fee, v_discount, v_advance,
      v_ctx.o_user_id, v_ctx.o_user_id)
    returning booking_id into v_booking_id;
  exception
    when exclusion_violation then
      raise exception using errcode = 'AB020',
        message = 'This time was just booked by someone else. Please choose another slot.';
    when unique_violation then
      -- the same request_uid committed at the same instant by a retry.
      -- Fix: filter by the caller's client (spec didn't), so a reused request_uid can't return another client's booking.
      select b.booking_id into v_booking_id from public.bookings b
       where b.request_uid = p_request_uid and b.client_id = v_client.client_id;
      if v_booking_id is null then
        raise;
      end if;
  end;

  return private.booking_json(v_booking_id);
end;
$$;

-- Edits an upcoming booking. p_expected_updated_at is the row's updated_at when the phone loaded it.
create or replace function public.update_booking(
  p_booking_id          integer,
  p_expected_updated_at timestamptz,
  p_resource_id         integer,
  p_booking_date        date,
  p_start_minute        integer,
  p_end_minute          integer,
  p_booking_session_id  integer,
  p_customer_name       text,
  p_customer_phone      text,
  p_customer_email      text,
  p_notes               text,
  p_manual_fee          integer,
  p_discount            integer,
  p_amount_received     integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx          record;
  v_client       public.clients;
  v_old          public.bookings;
  v_old_type_id  integer;
  v_new_type_id  integer;
  v_type_rate    integer;
  v_rate         integer;
  v_fee          integer;
  v_discount     integer := coalesce(p_discount, 0);
  v_received     integer;
  v_time_changed boolean;
  v_name         text := trim(coalesce(p_customer_name, ''));
  v_phone        text := regexp_replace(coalesce(p_customer_phone, ''), '\D', '', 'g');
  v_email        text := lower(trim(coalesce(p_customer_email, '')));
  v_notes        text := trim(coalesce(p_notes, ''));
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('booking.edit');
  perform private.require_writable_license(v_ctx.o_client_id);
  select c.* into v_client from public.clients c where c.client_id = v_ctx.o_client_id;

  select b.* into v_old from public.bookings b
   where b.booking_id = p_booking_id and b.client_id = v_client.client_id and b.data_status = 1
  for update;
  if not found then
    raise exception using errcode = 'AB040', message = 'Booking not found.';
  end if;
  -- Fix: "is distinct from" (spec used <>), so a null p_expected_updated_at can't skip the stale check.
  if v_old.updated_at is distinct from p_expected_updated_at then
    raise exception using errcode = 'AB025',
      message = 'Someone else changed this booking. It has been refreshed; please review and try again.';
  end if;
  if v_old.cancelled_at is not null then
    raise exception using errcode = 'AB024', message = 'Cancelled bookings cannot be edited.';
  end if;
  if v_old.booking_date < (now() at time zone v_client.timezone)::date then
    raise exception using errcode = 'AB024', message = 'Past bookings cannot be edited.';
  end if;

  select r.resource_type_id into v_old_type_id from public.resources r where r.resource_id = v_old.resource_id;

  -- the booking may keep its current resource even if it was disabled since
  select r.resource_type_id, t.hourly_rate into v_new_type_id, v_type_rate
    from public.resources r
    join public.resource_types t on t.resource_type_id = r.resource_type_id
   where r.resource_id = p_resource_id and r.client_id = v_client.client_id
     and (r.resource_id = v_old.resource_id or (r.data_status = 1 and t.data_status = 1));
  if not found then
    raise exception using errcode = 'AB026', message = 'This resource is not available for booking.';
  end if;

  perform private.validate_customer(v_name, v_phone, v_email, v_notes);

  -- rule: an edit may keep time it already had, even if it has started or the policy changed
  v_time_changed := (p_booking_date, p_start_minute, p_end_minute, p_booking_session_id)
                    is distinct from
                    (v_old.booking_date, v_old.start_minute::integer, v_old.end_minute::integer, v_old.booking_session_id);
  if v_time_changed then
    perform private.validate_booking_time(v_client, p_booking_date, p_start_minute, p_end_minute,
                                          p_booking_session_id, true);
  end if;

  if v_old.pricing_mode = 1 then
    -- keep the agreed rate unless the resource type changed
    v_rate := case when v_new_type_id = v_old_type_id then v_old.hourly_rate else v_type_rate end;
    if v_rate is null then
      raise exception using errcode = 'AB023', message = 'No hourly rate is set for this resource type.';
    end if;
    v_fee := round((p_end_minute - p_start_minute) * v_rate / 60.0)::integer;
  else
    v_rate := 0;
    v_fee  := p_manual_fee;
  end if;
  perform private.validate_money(v_client, v_fee, v_discount);
  v_received := least(greatest(coalesce(p_amount_received, 0), 0), v_fee - v_discount);

  begin
    update public.bookings set
      resource_id        = p_resource_id,
      booking_date       = p_booking_date,
      start_minute       = p_start_minute,
      end_minute         = p_end_minute,
      booking_session_id = p_booking_session_id,
      customer_name      = v_name,
      customer_phone     = v_phone,
      customer_email     = v_email,
      notes              = v_notes,
      hourly_rate        = v_rate,
      total_fee          = v_fee,
      discount           = v_discount,
      advance_paid       = v_received,
      balance_settled_at = null,            -- edit clears Mark Paid; trigger re-evaluates status
      updated_by_user_id = v_ctx.o_user_id
    where booking_id = p_booking_id;
  exception
    when exclusion_violation then
      raise exception using errcode = 'AB020',
        message = 'This time is already booked. Please choose another slot.';
  end;

  return private.booking_json(p_booking_id);
end;
$$;

create or replace function public.mark_booking_paid(p_booking_id integer)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx record;
  v_b   public.bookings;
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('booking.mark_paid');
  perform private.require_writable_license(v_ctx.o_client_id);

  select b.* into v_b from public.bookings b
   where b.booking_id = p_booking_id and b.client_id = v_ctx.o_client_id and b.data_status = 1
  for update;
  if not found then
    raise exception using errcode = 'AB040', message = 'Booking not found.';
  end if;
  if v_b.cancelled_at is not null then
    raise exception using errcode = 'AB024', message = 'Cancelled bookings cannot be marked as paid.';
  end if;

  if v_b.booking_status_id = 1 then            -- idempotent: already paid → no change
    update public.bookings
       set balance_settled_at = now(), updated_by_user_id = v_ctx.o_user_id
     where booking_id = p_booking_id;
  end if;

  return private.booking_json(p_booking_id);
end;
$$;

create or replace function public.cancel_booking(
  p_booking_id       integer,
  p_cancel_reason    text,
  p_advance_returned boolean)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ctx    record;
  v_b      public.bookings;
  v_reason text := trim(coalesce(p_cancel_reason, ''));
begin
  select * into v_ctx from private.require_session();
  perform private.require_permission('booking.cancel');
  perform private.require_writable_license(v_ctx.o_client_id);

  select b.* into v_b from public.bookings b
   where b.booking_id = p_booking_id and b.client_id = v_ctx.o_client_id and b.data_status = 1
  for update;
  if not found then
    raise exception using errcode = 'AB040', message = 'Booking not found.';
  end if;
  if v_b.cancelled_at is not null then            -- idempotent
    return private.booking_json(p_booking_id);
  end if;
  if v_reason = '' then
    raise exception using errcode = 'AB027', message = 'Please enter a reason for cancelling.';
  end if;

  update public.bookings
     set cancelled_at = now(),
         cancel_reason = v_reason,
         advance_returned = coalesce(p_advance_returned, false),
         cancelled_by_user_id = v_ctx.o_user_id,
         updated_by_user_id = v_ctx.o_user_id
   where booking_id = p_booking_id;

  return private.booking_json(p_booking_id);
end;
$$;
