-- Expanded New Zealand place search seed
-- Migration: 202606110004_seed_expanded_nz_places
--
-- Adds a wider set of real NZ towns, suburbs, settlements, and visitor places
-- to the location catalog. This is intentionally backend-only: it enriches the
-- location picker/search data the app already reads.
--
-- Source notes:
-- - Seed uses real NZ place names and regional grouping for app search UX.
-- - Stats NZ Datafinder Urban Rural 2023 (generalised), layer 111198, was used
--   as the official reference shape for the import direction and naming fields:
--   https://datafinder.stats.govt.nz/layer/111198-urban-rural-2023-generalised/
-- - This migration avoids geometry, coordinates, councils, and water/other-rural
--   statistical buckets because users search for places, not map entities.

begin;

create temporary table pcc_nz_place_seed (
  slug text primary key,
  name text not null,
  parent_slug text not null,
  subtitle text not null,
  aliases text[] not null default '{}',
  sort_priority integer not null default 9000
) on commit drop;

insert into pcc_nz_place_seed (slug, name, parent_slug, subtitle, aliases, sort_priority)
values
  -- Northland
  ('ahipara', 'Ahipara', 'northland', 'Northland place', '{}', 9111),
  ('coopers-beach', 'Coopers Beach', 'northland', 'Northland place', '{}', 9112),
  ('hokianga', 'Hokianga', 'northland', 'Northland harbour communities', '{}', 9113),
  ('kawakawa-northland', 'Kawakawa', 'northland', 'Northland town near the Bay of Islands', '{"Kawakawa Northland"}', 9114),
  ('kaikohe', 'Kaikohe', 'northland', 'Northland town', '{}', 9115),
  ('kaeo', 'Kaeo', 'northland', 'Northland settlement', '{}', 9116),
  ('maungatapere', 'Maungatāpere', 'northland', 'Northland rural settlement', '{"Maungatapere"}', 9117),
  ('ngawha-springs', 'Ngāwhā Springs', 'northland', 'Northland rural settlement', '{"Ngawha Springs"}', 9118),
  ('oakura-northland', 'Ōakura', 'northland', 'Northland coastal settlement', '{"Oakura Northland","Okura"}', 9119),
  ('waipu', 'Waipū', 'northland', 'Northland town', '{"Waipu"}', 9120),
  ('whangaroa', 'Whangaroa', 'northland', 'Northland harbour community', '{}', 9121),
  ('tutukaka', 'Tutukaka', 'northland', 'Northland coastal community', '{}', 9122),

  -- Auckland
  ('albany', 'Albany', 'auckland', 'Auckland place', '{}', 9010),
  ('avondale', 'Avondale', 'auckland', 'Auckland place', '{}', 9011),
  ('bethells-beach', 'Bethells Beach', 'auckland', 'West Auckland coastal settlement', '{"Te Henga"}', 9012),
  ('birkenhead', 'Birkenhead', 'auckland', 'Auckland place', '{}', 9013),
  ('devonport', 'Devonport', 'auckland', 'Auckland place', '{}', 9014),
  ('glen-eden', 'Glen Eden', 'auckland', 'Auckland place', '{}', 9015),
  ('helensville', 'Helensville', 'auckland', 'Auckland region town', '{}', 9016),
  ('henderson', 'Henderson', 'auckland', 'Auckland place', '{}', 9017),
  ('kumeu', 'Kumeū', 'auckland', 'Auckland region town', '{"Kumeu"}', 9018),
  ('manukau', 'Manukau', 'auckland', 'South Auckland place', '{}', 9019),
  ('mangere', 'Māngere', 'auckland', 'Auckland place', '{"Mangere"}', 9020),
  ('mount-eden', 'Mount Eden', 'auckland', 'Auckland place', '{"Mt Eden"}', 9021),
  ('newmarket', 'Newmarket', 'auckland', 'Auckland place', '{}', 9022),
  ('onehunga', 'Onehunga', 'auckland', 'Auckland place', '{}', 9023),
  ('orewa', 'Ōrewa', 'auckland', 'Auckland coastal town', '{"Orewa"}', 9024),
  ('parnell', 'Parnell', 'auckland', 'Auckland place', '{}', 9025),
  ('ponsonby', 'Ponsonby', 'auckland', 'Auckland place', '{}', 9026),
  ('puhoi', 'Puhoi', 'auckland', 'Auckland rural settlement', '{"Pūhoi"}', 9027),
  ('takapuna', 'Takapuna', 'auckland', 'Auckland place', '{}', 9028),
  ('waiheke-island', 'Waiheke Island', 'auckland', 'Auckland island communities', '{"Waiheke"}', 9029),
  ('waitakere-village', 'Waitākere Village', 'auckland', 'West Auckland village', '{"Waitakere Village"}', 9030),
  ('warkworth', 'Warkworth', 'auckland', 'Auckland region town', '{}', 9031),

  -- Waikato
  ('coromandel-town', 'Coromandel Town', 'waikato', 'Waikato/Coromandel place', '{"Coromandel"}', 9211),
  ('hahei', 'Hahei', 'waikato', 'Coromandel coastal settlement', '{}', 9212),
  ('huntly', 'Huntly', 'waikato', 'Waikato town', '{}', 9213),
  ('karapiro', 'Karāpiro', 'waikato', 'Waikato lake community', '{"Karapiro"}', 9214),
  ('matamata', 'Matamata', 'waikato', 'Waikato town', '{}', 9215),
  ('morrinsville', 'Morrinsville', 'waikato', 'Waikato town', '{}', 9216),
  ('ngaruawahia', 'Ngāruawāhia', 'waikato', 'Waikato town', '{"Ngaruawahia"}', 9217),
  ('paeroa', 'Paeroa', 'waikato', 'Waikato town', '{}', 9218),
  ('taupo-town', 'Taupō', 'waikato', 'Central North Island lake town', '{"Taupo"}', 9219),
  ('te-arai', 'Te Ārai', 'waikato', 'Waikato/Coromandel coastal area', '{"Te Arai"}', 9220),
  ('te-kauwhata', 'Te Kauwhata', 'waikato', 'Waikato town', '{}', 9221),
  ('te-kuiti', 'Te Kūiti', 'waikato', 'Waikato town', '{"Te Kuiti"}', 9222),
  ('thames', 'Thames', 'waikato', 'Coromandel town', '{}', 9223),
  ('tirau', 'Tīrau', 'waikato', 'Waikato town', '{"Tirau"}', 9224),
  ('tokoroa', 'Tokoroa', 'waikato', 'Waikato town', '{}', 9225),
  ('waihi', 'Waihī', 'waikato', 'Waikato/Coromandel town', '{"Waihi"}', 9226),
  ('whangamata', 'Whangamatā', 'waikato', 'Coromandel beach town', '{"Whangamata"}', 9227),
  ('whitianga', 'Whitianga', 'waikato', 'Coromandel town', '{}', 9228),

  -- Bay of Plenty
  ('edgecumbe', 'Edgecumbe', 'bay-of-plenty', 'Bay of Plenty town', '{}', 9311),
  ('katikati', 'Katikati', 'bay-of-plenty', 'Bay of Plenty town', '{}', 9312),
  ('kawerau', 'Kawerau', 'bay-of-plenty', 'Bay of Plenty town', '{}', 9313),
  ('maketu', 'Maketu', 'bay-of-plenty', 'Bay of Plenty coastal settlement', '{"Maketū"}', 9314),
  ('matata', 'Matatā', 'bay-of-plenty', 'Bay of Plenty coastal settlement', '{"Matata"}', 9315),
  ('murupara', 'Murupara', 'bay-of-plenty', 'Bay of Plenty town', '{}', 9316),
  ('omokoroa', 'Ōmokoroa', 'bay-of-plenty', 'Bay of Plenty peninsula community', '{"Omokoroa"}', 9317),
  ('opotiki', 'Ōpōtiki', 'bay-of-plenty', 'Eastern Bay of Plenty town', '{"Opotiki"}', 9318),
  ('papamoa', 'Pāpāmoa', 'bay-of-plenty', 'Bay of Plenty coastal community', '{"Papamoa"}', 9319),
  ('taneatua', 'Tāneatua', 'bay-of-plenty', 'Bay of Plenty rural settlement', '{"Taneatua"}', 9320),
  ('te-puke', 'Te Puke', 'bay-of-plenty', 'Bay of Plenty town', '{}', 9321),
  ('waihi-beach', 'Waihī Beach', 'bay-of-plenty', 'Bay of Plenty beach town', '{"Waihi Beach"}', 9322),

  -- Gisborne / Tairawhiti
  ('matawai', 'Matawai', 'gisborne', 'Tairāwhiti settlement', '{}', 9411),
  ('nuhaka', 'Nūhaka', 'gisborne', 'Tairāwhiti settlement', '{"Nuhaka"}', 9412),
  ('ruatoria', 'Ruatoria', 'gisborne', 'East Coast township', '{"Ruatōria"}', 9413),
  ('te-karaka', 'Te Karaka', 'gisborne', 'Tairāwhiti settlement', '{}', 9414),
  ('tolaga-bay', 'Tolaga Bay', 'gisborne', 'Tairāwhiti coastal community', '{"Uawa"}', 9415),
  ('tokomaru-bay', 'Tokomaru Bay', 'gisborne', 'Tairāwhiti coastal community', '{}', 9416),

  -- Hawke's Bay
  ('clive', 'Clive', 'hawkes-bay', 'Hawke''s Bay place', '{}', 9511),
  ('dannevirke', 'Dannevirke', 'hawkes-bay', 'Hawke''s Bay/Tararua town', '{}', 9512),
  ('havelock-north', 'Havelock North', 'hawkes-bay', 'Hawke''s Bay town', '{}', 9513),
  ('waipawa', 'Waipawa', 'hawkes-bay', 'Central Hawke''s Bay town', '{}', 9514),
  ('waipukurau', 'Waipukurau', 'hawkes-bay', 'Central Hawke''s Bay town', '{}', 9515),
  ('wairoa', 'Wairoa', 'hawkes-bay', 'Northern Hawke''s Bay town', '{}', 9516),

  -- Taranaki
  ('eltham', 'Eltham', 'taranaki', 'Taranaki town', '{}', 9611),
  ('hawera', 'Hāwera', 'taranaki', 'South Taranaki town', '{"Hawera"}', 9612),
  ('inglewood', 'Inglewood', 'taranaki', 'Taranaki town', '{}', 9613),
  ('mokau', 'Mōkau', 'taranaki', 'Taranaki coastal settlement', '{"Mokau"}', 9614),
  ('oakura-taranaki', 'Ōakura', 'taranaki', 'Taranaki coastal community', '{"Oakura Taranaki"}', 9615),
  ('opunake', 'Ōpunake', 'taranaki', 'Taranaki coastal town', '{"Opunake"}', 9616),
  ('stratford', 'Stratford', 'taranaki', 'Taranaki town', '{}', 9617),
  ('waitara', 'Waitara', 'taranaki', 'Taranaki town', '{}', 9618),

  -- Manawatū-Whanganui
  ('bulls', 'Bulls', 'manawatu-whanganui', 'Rangitīkei town', '{}', 9711),
  ('feilding', 'Feilding', 'manawatu-whanganui', 'Manawatū town', '{}', 9712),
  ('foxton', 'Foxton', 'manawatu-whanganui', 'Horowhenua town', '{}', 9713),
  ('levin', 'Levin', 'manawatu-whanganui', 'Horowhenua town', '{}', 9714),
  ('marton', 'Marton', 'manawatu-whanganui', 'Rangitīkei town', '{}', 9715),
  ('ohakune', 'Ohakune', 'manawatu-whanganui', 'Central North Island town', '{}', 9716),
  ('pahiatua', 'Pahiatua', 'manawatu-whanganui', 'Tararua town', '{}', 9717),
  ('raetihi', 'Raetihi', 'manawatu-whanganui', 'Central North Island town', '{}', 9718),
  ('taihape', 'Taihape', 'manawatu-whanganui', 'Rangitīkei town', '{}', 9719),
  ('waiouru', 'Waiōuru', 'manawatu-whanganui', 'Central North Island settlement', '{"Waiouru"}', 9720),
  ('woodville', 'Woodville', 'manawatu-whanganui', 'Tararua town', '{}', 9721),

  -- Wellington
  ('camborne', 'Camborne', 'wellington', 'Wellington region place', '{}', 9811),
  ('carterton', 'Carterton', 'wellington', 'Wairarapa town', '{}', 9812),
  ('eastbourne', 'Eastbourne', 'wellington', 'Lower Hutt harbour community', '{}', 9813),
  ('featherston', 'Featherston', 'wellington', 'Wairarapa town', '{}', 9814),
  ('greytown', 'Greytown', 'wellington', 'Wairarapa town', '{}', 9815),
  ('kapiti', 'Kāpiti', 'wellington', 'Kāpiti Coast communities', '{"Kapiti","Kāpiti Coast","Kapiti Coast"}', 9816),
  ('masterton', 'Masterton', 'wellington', 'Wairarapa town', '{}', 9817),
  ('martinborough', 'Martinborough', 'wellington', 'Wairarapa town', '{}', 9818),
  ('otaki', 'Ōtaki', 'wellington', 'Kāpiti Coast town', '{"Otaki"}', 9819),
  ('paekakariki', 'Paekākāriki', 'wellington', 'Kāpiti Coast settlement', '{"Paekakariki"}', 9820),
  ('paraparaumu', 'Paraparaumu', 'wellington', 'Kāpiti Coast town', '{}', 9821),
  ('upper-hutt', 'Upper Hutt', 'wellington', 'Hutt Valley city', '{}', 9822),

  -- Tasman / Nelson / Marlborough
  ('collingwood', 'Collingwood', 'tasman', 'Tasman place', '{}', 9901),
  ('motueka', 'Motueka', 'tasman', 'Tasman town', '{}', 9902),
  ('murchison', 'Murchison', 'tasman', 'Tasman town', '{}', 9903),
  ('pohara', 'Pōhara', 'tasman', 'Tasman coastal settlement', '{"Pohara"}', 9904),
  ('takaka', 'Tākaka', 'tasman', 'Golden Bay town', '{"Takaka"}', 9905),
  ('mapua', 'Māpua', 'tasman', 'Tasman coastal village', '{"Mapua"}', 9906),
  ('stoke', 'Stoke', 'nelson', 'Nelson place', '{}', 9912),
  ('havelock', 'Havelock', 'marlborough', 'Marlborough town', '{}', 9922),
  ('picton', 'Picton', 'marlborough', 'Marlborough Sounds town', '{}', 9924),
  ('renwick', 'Renwick', 'marlborough', 'Marlborough town', '{}', 9925),
  ('seddon', 'Seddon', 'marlborough', 'Marlborough town', '{}', 9926),

  -- West Coast
  ('blackball', 'Blackball', 'west-coast', 'West Coast settlement', '{}', 9931),
  ('dobson', 'Dobson', 'west-coast', 'West Coast settlement', '{}', 9932),
  ('fox-glacier', 'Fox Glacier', 'west-coast', 'West Coast glacier settlement', '{}', 9933),
  ('franz-josef', 'Franz Josef', 'west-coast', 'West Coast glacier settlement', '{"Franz Josef Glacier"}', 9934),
  ('hokitika', 'Hokitika', 'west-coast', 'West Coast town', '{}', 9935),
  ('karamea', 'Karamea', 'west-coast', 'West Coast settlement', '{}', 9936),
  ('reefton', 'Reefton', 'west-coast', 'West Coast town', '{}', 9937),
  ('westport', 'Westport', 'west-coast', 'West Coast town', '{}', 9938),

  -- Canterbury
  ('akaroa', 'Akaroa', 'canterbury', 'Banks Peninsula town', '{}', 9941),
  ('amberley', 'Amberley', 'canterbury', 'North Canterbury town', '{}', 9942),
  ('ashburton', 'Ashburton', 'canterbury', 'Canterbury town', '{}', 9943),
  ('castle-hill', 'Castle Hill', 'canterbury', 'Canterbury alpine village', '{}', 9944),
  ('darfield', 'Darfield', 'canterbury', 'Canterbury town', '{}', 9945),
  ('geraldine', 'Geraldine', 'canterbury', 'South Canterbury town', '{}', 9946),
  ('hanmer-springs', 'Hanmer Springs', 'canterbury', 'North Canterbury alpine village', '{}', 9947),
  ('kaiapoi', 'Kaiapoi', 'canterbury', 'Canterbury town', '{}', 9948),
  ('kaikoura', 'Kaikōura', 'canterbury', 'Canterbury coastal town', '{"Kaikoura"}', 9949),
  ('methven', 'Methven', 'canterbury', 'Canterbury town', '{}', 9949),
  ('rangiora-town', 'Rangiora', 'canterbury', 'North Canterbury town', '{}', 9950),
  ('rolleston', 'Rolleston', 'canterbury', 'Canterbury town', '{}', 9951),
  ('temuka', 'Temuka', 'canterbury', 'South Canterbury town', '{}', 9952),
  ('waimate', 'Waimate', 'canterbury', 'South Canterbury town', '{}', 9953),
  ('waimakariri', 'Waimakariri', 'canterbury', 'North Canterbury communities', '{}', 9954),
  ('winchester', 'Winchester', 'canterbury', 'South Canterbury settlement', '{}', 9955),

  -- Otago
  ('alexandra', 'Alexandra', 'otago', 'Central Otago town', '{}', 9961),
  ('arrowtown', 'Arrowtown', 'otago', 'Otago heritage town', '{}', 9962),
  ('balclutha', 'Balclutha', 'otago', 'Otago town', '{}', 9963),
  ('cromwell', 'Cromwell', 'otago', 'Central Otago town', '{}', 9964),
  ('glenorchy', 'Glenorchy', 'otago', 'Otago lakeside settlement', '{}', 9965),
  ('herbert', 'Herbert', 'otago', 'North Otago settlement', '{}', 9966),
  ('lawrence', 'Lawrence', 'otago', 'Otago town', '{}', 9967),
  ('middlemarch', 'Middlemarch', 'otago', 'Otago settlement', '{}', 9968),
  ('milton', 'Milton', 'otago', 'Otago town', '{}', 9969),
  ('mosgiel', 'Mosgiel', 'otago', 'Dunedin area town', '{}', 9970),
  ('oamaru', 'Oamaru', 'otago', 'North Otago town', '{}', 9971),
  ('omarama', 'Omarama', 'otago', 'Waitaki/Mackenzie settlement', '{}', 9972),
  ('palmerston-otago', 'Palmerston', 'otago', 'Otago town', '{"Palmerston Otago"}', 9973),
  ('queenstown-lakes', 'Queenstown Lakes', 'otago', 'Otago lake district communities', '{}', 9974),
  ('twizel', 'Twizel', 'otago', 'Mackenzie basin town', '{}', 9976),

  -- Southland
  ('bluff', 'Bluff', 'southland', 'Southland port town', '{}', 9981),
  ('gore', 'Gore', 'southland', 'Southland town', '{}', 9982),
  ('lumsden', 'Lumsden', 'southland', 'Southland town', '{}', 9983),
  ('manapouri', 'Manapōuri', 'southland', 'Fiordland lake settlement', '{"Manapouri"}', 9984),
  ('riverton', 'Riverton', 'southland', 'Southland coastal town', '{}', 9985),
  ('stewart-island', 'Stewart Island', 'southland', 'Southland island communities', '{"Rakiura"}', 9986),
  ('te-anau', 'Te Ānau', 'southland', 'Fiordland lake town', '{"Te Anau"}', 9987),
  ('winton', 'Winton', 'southland', 'Southland town', '{}', 9988),

  -- Chatham Islands
  ('waitangi-chatham-islands', 'Waitangi', 'chatham-islands', 'Chatham Islands settlement', '{"Waitangi Chatham Islands"}', 9991);

insert into public.location_scopes (slug, name, scope_type, subtitle, source, source_id, sort_priority)
select
  slug,
  name,
  'place',
  subtitle,
  'expanded_nz_place_seed',
  '202606110004',
  sort_priority
from pcc_nz_place_seed
on conflict (slug)
do update set
  name = excluded.name,
  scope_type = excluded.scope_type,
  subtitle = excluded.subtitle,
  source = excluded.source,
  source_id = excluded.source_id,
  sort_priority = excluded.sort_priority,
  is_public = true,
  is_selectable = true,
  updated_at = now();

insert into public.location_aliases (location_scope_id, alias, source)
select ls.id, alias_value, 'expanded_nz_place_seed'
from pcc_nz_place_seed seed
join public.location_scopes ls on ls.slug = seed.slug
cross join lateral unnest(seed.aliases) as alias_values(alias_value)
where alias_value <> ''
on conflict (location_scope_id, normalized_alias) do nothing;

insert into public.location_scope_links (child_scope_id, parent_scope_id, relationship_type, sort_order)
select child.id, parent.id, 'widens_to', 10
from pcc_nz_place_seed seed
join public.location_scopes child on child.slug = seed.slug
join public.location_scopes parent on parent.slug = seed.parent_slug
on conflict (child_scope_id, parent_scope_id, relationship_type)
do update set sort_order = excluded.sort_order;

commit;
