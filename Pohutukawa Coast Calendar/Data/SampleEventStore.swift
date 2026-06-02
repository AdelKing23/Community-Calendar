import Foundation

enum SampleEventStore {
    static var events: [LocalEvent] {
        let calendar = Calendar.current

        func date(daysFromNow: Int, hour: Int, minute: Int = 0) -> Date {
            let base = calendar.startOfDay(for: Date())
            return calendar.date(byAdding: DateComponents(day: daysFromNow, hour: hour, minute: minute), to: base) ?? Date()
        }

        func nextSunday(hour: Int, minute: Int = 0, extraWeeks: Int = 0) -> Date {
            let today = calendar.startOfDay(for: Date())
            let weekday = calendar.component(.weekday, from: today)
            let daysUntilSunday = (1 - weekday + 7) % 7
            let offset = daysUntilSunday + extraWeeks * 7
            return calendar.date(byAdding: DateComponents(day: offset, hour: hour, minute: minute), to: today) ?? Date()
        }

        func end(_ start: Date, hours: Int, minutes: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(hour: hours, minute: minutes), to: start) ?? start
        }

        let farmersStart = nextSunday(hour: 8)
        let villageStart = nextSunday(hour: 9)
        let twilightStart = date(daysFromNow: 5, hour: 17, minute: 30)
        let beachlandsMarketStart = date(daysFromNow: 6, hour: 8, minute: 30)
        let gigStart = date(daysFromNow: 3, hour: 19)
        let seniorsStart = date(daysFromNow: 2, hour: 10)
        let sportsStart = date(daysFromNow: 4, hour: 9)
        let familyStart = date(daysFromNow: 7, hour: 11)
        let workshopStart = date(daysFromNow: 8, hour: 18)
        let fundraiserStart = date(daysFromNow: 10, hour: 18, minute: 30)
        let culturalStart = date(daysFromNow: 12, hour: 12)
        let noticeStart = date(daysFromNow: 1, hour: 9)

        return [
            LocalEvent(
                title: "Clevedon Farmers Market",
                category: .markets,
                town: .clevedon,
                venue: "Clevedon Showgrounds",
                startDate: farmersStart,
                endDate: end(farmersStart, hours: 5),
                priceLabel: "Free entry",
                isFree: true,
                audience: "Everyone",
                shortDescription: "Fresh local produce, coffee, food stalls, and a relaxed rural Sunday morning.",
                longDescription: "A weekly Sunday market listing with fresh produce, prepared food, coffee, parking nearby, and seasonal changes through the year.",
                contactPhone: "021 523 616",
                contactEmail: "info@clevedonfarmersmarket.co.nz",
                isFeatured: true,
                isPaidPush: true
            ),
            LocalEvent(
                title: "Clevedon Village Craft Market",
                category: .markets,
                town: .clevedon,
                venue: "Clevedon Community Hall",
                startDate: villageStart,
                endDate: end(villageStart, hours: 5),
                priceLabel: "Free entry",
                isFree: true,
                audience: "Families, visitors, locals",
                shortDescription: "Arts, crafts, plants, food, handmade goods, and Sunday village browsing.",
                longDescription: "A smaller village market with handmade goods, plants, crafts, food, and a relaxed community-hall feel.",
                contactPhone: nil,
                contactEmail: "clevedonvillagemarket@gmail.com",
                isFeatured: true,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Beachlands Community Market",
                category: .markets,
                town: .beachlands,
                venue: "Beachlands Village",
                startDate: beachlandsMarketStart,
                endDate: end(beachlandsMarketStart, hours: 4),
                priceLabel: "Free entry",
                isFree: true,
                audience: "Everyone",
                shortDescription: "Local stalls, community catch-ups, food, and weekend browsing.",
                longDescription: "A local market-style weekend listing for Beachlands, with stalls, food, and easy community browsing.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Country Twilight Food & Music Night",
                category: .foodDrink,
                town: .clevedon,
                venue: "Clevedon A&P Showgrounds",
                startDate: twilightStart,
                endDate: end(twilightStart, hours: 3),
                priceLabel: "Free entry",
                isFree: true,
                audience: "Whānau friendly",
                shortDescription: "Food trucks, music, evening lights, and a country-style night out.",
                longDescription: "A coastal-country evening with food trucks, live music, evening lights, and room for friends and families to settle in.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: true,
                isPaidPush: true
            ),
            LocalEvent(
                title: "Friday Live at the Local",
                category: .liveMusic,
                town: .maraetai,
                venue: "Maraetai Local Venue",
                startDate: gigStart,
                endDate: end(gigStart, hours: 3),
                priceLabel: "Free / venue spend",
                isFree: true,
                audience: "Adults",
                shortDescription: "Easy local live music listing for Friday night plans.",
                longDescription: "A Friday night local music listing with clear time, venue, cost guidance, and an easygoing coastal crowd.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Seniors Morning Tea",
                category: .seniors,
                town: .beachlands,
                venue: "Te Puru Community Centre",
                startDate: seniorsStart,
                endDate: end(seniorsStart, hours: 2),
                priceLabel: "Koha",
                isFree: false,
                audience: "Seniors",
                shortDescription: "A relaxed local catch-up with tea, conversation, and community support.",
                longDescription: "A clear, friendly community listing for seniors with time, place, price, and contact details kept easy to find.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Saturday Junior Sport Morning",
                category: .sport,
                town: .maraetai,
                venue: "Local Sports Ground",
                startDate: sportsStart,
                endDate: end(sportsStart, hours: 3),
                priceLabel: "Free spectator entry",
                isFree: true,
                audience: "Families",
                shortDescription: "Weekend sport, coffee carts, families, and community sideline energy.",
                longDescription: "A weekend sport listing for families, spectators, coffee carts, club mornings, and community sideline energy.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Family Sunday Funday",
                category: .kidsFamily,
                town: .whitford,
                venue: "Whitford Community Hall",
                startDate: familyStart,
                endDate: end(familyStart, hours: 4),
                priceLabel: "Free entry",
                isFree: true,
                audience: "Kids and families",
                shortDescription: "Games, stalls, sausage sizzle, music, and family-friendly activities.",
                longDescription: "A family-focused listing with age suitability and cost kept obvious for parents planning the day.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: true,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Local Art & Craft Workshop",
                category: .classesWorkshops,
                town: .beachlands,
                venue: "Beachlands Memorial Hall",
                startDate: workshopStart,
                endDate: end(workshopStart, hours: 2),
                priceLabel: "$20",
                isFree: false,
                audience: "Adults and teens",
                shortDescription: "Hands-on local workshop with limited spaces.",
                longDescription: "A hands-on local workshop with booking notes, capacity, price, materials, and organiser contact details.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Community Fundraiser Dinner",
                category: .fundraisers,
                town: .maraetai,
                venue: "Maraetai Community Hall",
                startDate: fundraiserStart,
                endDate: end(fundraiserStart, hours: 3),
                priceLabel: "$25 ticket",
                isFree: false,
                audience: "Community",
                shortDescription: "Dinner, raffles, local causes, and a warm community night.",
                longDescription: "A community fundraiser with the cause, organiser, ticket price, sponsor notes, and contact details easy to scan.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Local Culture & Kai Day",
                category: .churchMaraeCultural,
                town: .whitford,
                venue: "Community Venue",
                startDate: culturalStart,
                endDate: end(culturalStart, hours: 4),
                priceLabel: "Koha",
                isFree: false,
                audience: "Everyone welcome",
                shortDescription: "Community kai, kōrero, culture, and connection.",
                longDescription: "A public cultural and community gathering with kai, kōrero, connection, and clear host details.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            ),
            LocalEvent(
                title: "Mobile Library Stop",
                category: .publicNotices,
                town: .beachlands,
                venue: "Wakelin Road",
                startDate: noticeStart,
                endDate: end(noticeStart, hours: 1),
                priceLabel: "Free",
                isFree: true,
                audience: "Everyone",
                shortDescription: "Useful local notice-style listing for regular community services.",
                longDescription: "A useful recurring community service listing for library stops, council visits, drop-ins, and public notices.",
                contactPhone: nil,
                contactEmail: nil,
                isFeatured: false,
                isPaidPush: false
            )
        ]
    }
}
