-- Starter NZ named-place search seeds
-- Migration: 202606110003_seed_location_search_starters
--
-- Adds high-value named places to the location catalog so users can search more
-- naturally outside the initial Pōhutukawa Coast seed. This is a bridge until a
-- full official NZ locality import is prepared through location_import_staging.

begin;

insert into public.location_scopes (slug, name, scope_type, subtitle, source, sort_priority)
values
  ('howick', 'Howick', 'place', 'East Auckland village and nearby bays', 'manual_seed', 410),
  ('botany', 'Botany', 'place', 'East Auckland shopping and community area', 'manual_seed', 420),
  ('pakuranga', 'Pakuranga', 'place', 'East Auckland suburb near the Tāmaki River', 'manual_seed', 430),
  ('flat-bush', 'Flat Bush', 'place', 'South-east Auckland community area', 'manual_seed', 440),
  ('dannemora', 'Dannemora', 'place', 'East Auckland residential community', 'manual_seed', 450),
  ('half-moon-bay', 'Half Moon Bay', 'place', 'East Auckland ferry and marina area', 'manual_seed', 460),
  ('bucklands-beach', 'Bucklands Beach', 'place', 'East Auckland coastal suburb', 'manual_seed', 470),
  ('cockle-bay', 'Cockle Bay', 'place', 'East Auckland coastal suburb', 'manual_seed', 480),
  ('highland-park', 'Highland Park', 'place', 'East Auckland shopping and community area', 'manual_seed', 490),
  ('east-tamaki', 'East Tāmaki', 'place', 'East Auckland business and community area', 'manual_seed', 500),

  ('paihia', 'Paihia', 'place', 'Bay of Islands town in Northland', 'manual_seed', 9110),
  ('waitangi', 'Waitangi', 'place', 'Bay of Islands historic area in Northland', 'manual_seed', 9120),
  ('opua', 'Opua', 'place', 'Bay of Islands harbour community', 'manual_seed', 9130),
  ('russell', 'Russell', 'place', 'Bay of Islands town in Northland', 'manual_seed', 9140),
  ('kerikeri', 'Kerikeri', 'place', 'Northland town near the Bay of Islands', 'manual_seed', 9150),
  ('whangarei', 'Whangārei', 'place', 'Northland city and surrounding communities', 'manual_seed', 9160),
  ('kaitaia', 'Kaitaia', 'place', 'Far North town and service centre', 'manual_seed', 9170),
  ('dargaville', 'Dargaville', 'place', 'Kaipara town in Northland', 'manual_seed', 9180),
  ('mangawhai', 'Mangawhai', 'place', 'Northland coastal community', 'manual_seed', 9190),

  ('pukekohe', 'Pukekohe', 'place', 'Franklin town and nearby communities', 'manual_seed', 310),
  ('waiuku', 'Waiuku', 'place', 'Franklin town near the Manukau Harbour', 'manual_seed', 320),
  ('tuakau', 'Tuakau', 'place', 'Waikato town near Franklin', 'manual_seed', 9210),
  ('port-waikato', 'Port Waikato', 'place', 'Coastal Waikato settlement', 'manual_seed', 9220),
  ('hamilton', 'Hamilton', 'place', 'Waikato city and surrounding communities', 'manual_seed', 9230),
  ('cambridge', 'Cambridge', 'place', 'Waikato town near the river and lake districts', 'manual_seed', 9240),
  ('raglan', 'Raglan', 'place', 'Waikato west coast town', 'manual_seed', 9250),
  ('te-awamutu', 'Te Awamutu', 'place', 'Waikato town and surrounding communities', 'manual_seed', 9260),
  ('taupo', 'Taupō', 'place', 'Central North Island lake town', 'manual_seed', 9270),

  ('tauranga', 'Tauranga', 'place', 'Bay of Plenty city and harbour communities', 'manual_seed', 9310),
  ('mount-maunganui', 'Mount Maunganui', 'place', 'Bay of Plenty beachside community', 'manual_seed', 9320),
  ('rotorua', 'Rotorua', 'place', 'Bay of Plenty lakes and geothermal city', 'manual_seed', 9330),
  ('whakatane', 'Whakatāne', 'place', 'Eastern Bay of Plenty town', 'manual_seed', 9340),
  ('gisborne-city', 'Gisborne', 'place', 'Tairāwhiti city and surrounding communities', 'manual_seed', 9410),
  ('napier', 'Napier', 'place', 'Hawke''s Bay city', 'manual_seed', 9510),
  ('hastings', 'Hastings', 'place', 'Hawke''s Bay city and nearby communities', 'manual_seed', 9520),
  ('new-plymouth', 'New Plymouth', 'place', 'Taranaki coastal city', 'manual_seed', 9610),
  ('palmerston-north', 'Palmerston North', 'place', 'Manawatū city', 'manual_seed', 9710),
  ('whanganui-city', 'Whanganui', 'place', 'Whanganui river city', 'manual_seed', 9720),
  ('wellington-city', 'Wellington', 'place', 'Wellington city and harbour communities', 'manual_seed', 9810),
  ('lower-hutt', 'Lower Hutt', 'place', 'Hutt Valley city', 'manual_seed', 9820),
  ('porirua', 'Porirua', 'place', 'Wellington region harbour city', 'manual_seed', 9830),
  ('nelson-city', 'Nelson', 'place', 'Nelson city and nearby communities', 'manual_seed', 9911),
  ('blenheim', 'Blenheim', 'place', 'Marlborough town and wine region communities', 'manual_seed', 9921),
  ('greymouth', 'Greymouth', 'place', 'West Coast town', 'manual_seed', 9931),
  ('christchurch', 'Christchurch', 'place', 'Canterbury city and surrounding communities', 'manual_seed', 9941),
  ('timaru', 'Timaru', 'place', 'South Canterbury coastal town', 'manual_seed', 9942),
  ('queenstown', 'Queenstown', 'place', 'Otago lakeside resort town', 'manual_seed', 9951),
  ('dunedin', 'Dunedin', 'place', 'Otago city and harbour communities', 'manual_seed', 9952),
  ('wanaka', 'Wānaka', 'place', 'Otago lakeside town', 'manual_seed', 9953),
  ('invercargill', 'Invercargill', 'place', 'Southland city', 'manual_seed', 9961)
on conflict (slug)
do update set
  name = excluded.name,
  scope_type = excluded.scope_type,
  subtitle = excluded.subtitle,
  source = excluded.source,
  sort_priority = excluded.sort_priority,
  updated_at = now();

insert into public.location_aliases (location_scope_id, alias, source)
select ls.id, alias_value, 'manual_seed'
from public.location_scopes ls
join (
  values
    ('east-auckland', 'Howick'),
    ('east-auckland', 'Botany'),
    ('east-auckland', 'Pakuranga'),
    ('east-auckland', 'Flat Bush'),
    ('howick', 'Howick Village'),
    ('flat-bush', 'Ormiston'),
    ('east-tamaki', 'East Tamaki'),
    ('paihia', 'Bay of Islands'),
    ('waitangi', 'Treaty Grounds'),
    ('whangarei', 'Whangarei'),
    ('whangarei', 'Whangārei'),
    ('taupo', 'Taupo'),
    ('tauranga', 'The Mount'),
    ('mount-maunganui', 'Mt Maunganui'),
    ('rotorua', 'Rotorua Lakes'),
    ('whakatane', 'Whakatane'),
    ('gisborne-city', 'Tairawhiti'),
    ('gisborne-city', 'Tairāwhiti'),
    ('palmerston-north', 'Palmy'),
    ('wellington-city', 'Wellington CBD'),
    ('christchurch', 'Ōtautahi'),
    ('dunedin', 'Ōtepoti'),
    ('wanaka', 'Wanaka')
) aliases(slug, alias_value)
  on aliases.slug = ls.slug
on conflict (location_scope_id, normalized_alias) do nothing;

insert into public.location_scope_links (child_scope_id, parent_scope_id, relationship_type, sort_order)
select child.id, parent.id, 'widens_to', link.sort_order
from (
  values
    ('howick', 'east-auckland', 10),
    ('botany', 'east-auckland', 10),
    ('pakuranga', 'east-auckland', 10),
    ('flat-bush', 'east-auckland', 10),
    ('dannemora', 'east-auckland', 10),
    ('half-moon-bay', 'east-auckland', 10),
    ('bucklands-beach', 'east-auckland', 10),
    ('cockle-bay', 'east-auckland', 10),
    ('highland-park', 'east-auckland', 10),
    ('east-tamaki', 'east-auckland', 10),

    ('paihia', 'northland', 10),
    ('waitangi', 'northland', 10),
    ('opua', 'northland', 10),
    ('russell', 'northland', 10),
    ('kerikeri', 'northland', 10),
    ('whangarei', 'northland', 10),
    ('kaitaia', 'northland', 10),
    ('dargaville', 'northland', 10),
    ('mangawhai', 'northland', 10),

    ('pukekohe', 'franklin', 10),
    ('waiuku', 'franklin', 10),
    ('tuakau', 'waikato', 10),
    ('port-waikato', 'waikato', 10),
    ('hamilton', 'waikato', 10),
    ('cambridge', 'waikato', 10),
    ('raglan', 'waikato', 10),
    ('te-awamutu', 'waikato', 10),
    ('taupo', 'waikato', 10),

    ('tauranga', 'bay-of-plenty', 10),
    ('mount-maunganui', 'bay-of-plenty', 10),
    ('rotorua', 'bay-of-plenty', 10),
    ('whakatane', 'bay-of-plenty', 10),
    ('gisborne-city', 'gisborne', 10),
    ('napier', 'hawkes-bay', 10),
    ('hastings', 'hawkes-bay', 10),
    ('new-plymouth', 'taranaki', 10),
    ('palmerston-north', 'manawatu-whanganui', 10),
    ('whanganui-city', 'manawatu-whanganui', 10),
    ('wellington-city', 'wellington', 10),
    ('lower-hutt', 'wellington', 10),
    ('porirua', 'wellington', 10),
    ('nelson-city', 'nelson', 10),
    ('blenheim', 'marlborough', 10),
    ('greymouth', 'west-coast', 10),
    ('christchurch', 'canterbury', 10),
    ('timaru', 'canterbury', 10),
    ('queenstown', 'otago', 10),
    ('dunedin', 'otago', 10),
    ('wanaka', 'otago', 10),
    ('invercargill', 'southland', 10)
) link(child_slug, parent_slug, sort_order)
join public.location_scopes child on child.slug = link.child_slug
join public.location_scopes parent on parent.slug = link.parent_slug
on conflict (child_scope_id, parent_scope_id, relationship_type)
do update set sort_order = excluded.sort_order;

commit;
