-- DEV / LOCAL ONLY: the four demo clients, from lib/app/config/clients/<id>.dart. Never run on prod.
-- icon_key is the Material icon name (without _rounded/_outlined); Dart maps it to IconData.
-- Demo logins: create the auth user (Studio → Authentication → Add user, auto-confirm), then e.g.
--   select public.admin_add_user((select client_id from public.clients where client_code = 'demo'),
--                                'owner@example.com', 'Demo Owner', 'owner');

select public.admin_create_client($json$
{
  "client_code": "demo",
  "name": "Apex Arena",
  "tagline": "Premier Indoor Arena Facility",
  "address": "Sector F-11/1, Islamabad",
  "phone": "+92 341 2757081",
  "business_profile_code": "sports_venue",
  "plan_code": "monthly",
  "resource_types": [
    { "name": "Indoor Cricket", "short_name": "Cricket", "icon_key": "sports_cricket", "tone": "emerald",
      "hourly_rate": 3500, "emoji": "🏏", "sort_order": 1,
      "resources": [
        { "name": "Turf Pitch 1 (Main)", "description": "Full-length lane · floodlit · team matches", "sort_order": 1 },
        { "name": "Turf Pitch 2 (Express)", "description": "Short lane · bowling machine · net practice", "sort_order": 2 },
        { "name": "Turf Pitch 3 (VIP Indoor)", "description": "Private · air-conditioned · lounge seating", "sort_order": 3 } ] },
    { "name": "Padel Court", "short_name": "Padel", "icon_key": "sports_tennis", "tone": "blue",
      "hourly_rate": 3000, "emoji": "🎾", "sort_order": 2,
      "resources": [
        { "name": "Court A Glass Panoramic", "description": "All-glass walls · spectator view", "sort_order": 1 },
        { "name": "Court B Indoor Sky", "description": "Roofed · open in rain and heat", "sort_order": 2 },
        { "name": "Court C Center Court", "description": "Main court · seating for matches", "sort_order": 3 } ] }
  ]
}
$json$::jsonb);

select public.admin_create_client($json$
{
  "client_code": "demo_space",
  "name": "The Loft Workspaces & Studio",
  "tagline": "Creative Rooms, Studios & Gaming Lounge",
  "address": "Main Boulevard, Gulberg III, Lahore",
  "phone": "+92 300 1234567",
  "business_profile_code": "space_rental",
  "plan_code": "monthly",
  "show_entry_pass": false,
  "resource_types": [
    { "name": "Hall Rooms", "short_name": "Rooms", "icon_key": "meeting_room", "tone": "emerald",
      "hourly_rate": 4000, "emoji": "🛏️", "sort_order": 1,
      "resources": [
        { "name": "G Floor Room 1", "description": "Up to 20 seats · projector · step-free", "sort_order": 1 },
        { "name": "G Floor Room 2", "description": "Up to 8 seats · TV · whiteboard", "sort_order": 2 },
        { "name": "1st Floor Room 1", "description": "Photo studio · backdrops · lights", "sort_order": 3 },
        { "name": "1st Floor Room 2", "description": "Podcast booth · 2 mics · soundproof", "sort_order": 4 },
        { "name": "2nd Floor Room 1", "description": "Up to 12 seats · daylight · balcony", "sort_order": 5 } ] },
    { "name": "Playstation", "short_name": "Playstation", "icon_key": "videogame_asset", "tone": "blue",
      "hourly_rate": 2000, "emoji": "🎮", "sort_order": 2,
      "resources": [
        { "name": "Playstation", "description": "PS5 · 4 controllers · 55\" TV", "sort_order": 1 } ] }
  ]
}
$json$::jsonb);

-- Manual pricing (event_venue profile): no hourly rate; sessions come from the profile.
select public.admin_create_client($json$
{
  "client_code": "demo_event",
  "name": "Grand Imperial Banquet",
  "tagline": "Luxury Halls & Event Spaces",
  "address": "Club Road, Civil Lines, Karachi",
  "phone": "+92 321 9876543",
  "business_profile_code": "event_venue",
  "plan_code": "monthly",
  "resource_types": [
    { "name": "Banquet Hall", "short_name": "Banquet", "icon_key": "event", "tone": "emerald",
      "hourly_rate": null, "emoji": "💒", "sort_order": 1,
      "resources": [
        { "name": "Main Banquet Hall", "description": "Up to 300 guests · stage · bridal room", "sort_order": 1 },
        { "name": "Small Banquet Hall", "description": "Up to 250 guests · private entrance", "sort_order": 2 },
        { "name": "Banquet Hall", "description": "Up to 550 guests · lawn access", "sort_order": 3 } ] }
  ]
}
$json$::jsonb);

-- Its logo is uploaded to Storage client-assets/<client_id>/logo.png, then logo_path is set.
select public.admin_create_client($json$
{
  "client_code": "demo_vehicle",
  "name": "Prime Drive Car Rental",
  "tagline": "Self-Drive & Chauffeur Fleet",
  "address": "Airport Avenue, Islamabad",
  "phone": "+92 333 5551234",
  "business_profile_code": "vehicle_rental",
  "plan_code": "monthly",
  "resource_types": [
    { "name": "Hatchback", "short_name": "Hatchback", "icon_key": "directions_car", "tone": "emerald",
      "hourly_rate": 2500, "emoji": "🚘", "sort_order": 1,
      "resources": [
        { "name": "Alto Grey 2022", "description": "Manual · 4 seats · fuel saver", "sort_order": 1 },
        { "name": "Mira White 2019", "description": "Automatic · 4 seats · fuel saver", "sort_order": 2 },
        { "name": "Cultus Black 2024", "description": "Manual · 5 seats · AC", "sort_order": 3 } ] },
    { "name": "Sedan", "short_name": "Sedan", "icon_key": "local_taxi", "tone": "blue",
      "hourly_rate": 3500, "emoji": "🚗", "sort_order": 2,
      "resources": [
        { "name": "Camry White 2022", "description": "Automatic · 5 seats · leather interior", "sort_order": 1 },
        { "name": "Corolla Black 2019", "description": "Automatic · 5 seats · AC", "sort_order": 2 },
        { "name": "Prius Green 2024", "description": "Automatic · 5 seats · hybrid", "sort_order": 3 } ] },
    { "name": "Premium", "short_name": "Premium", "icon_key": "fire_truck", "tone": "orange",
      "hourly_rate": 5000, "emoji": "🚙", "sort_order": 3,
      "resources": [
        { "name": "Jaecoo J5 White 2022", "description": "Automatic · 5 seats · panoramic roof", "sort_order": 1 },
        { "name": "Oshan x7 Black 2023", "description": "Automatic · 7 seats · family SUV", "sort_order": 2 },
        { "name": "Hilux Silver 2026", "description": "Automatic · 5 seats · 4x4 pickup", "sort_order": 3 } ] }
  ]
}
$json$::jsonb);
