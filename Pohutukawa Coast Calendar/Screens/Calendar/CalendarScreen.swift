import SwiftUI

struct CalendarScreen: View {
    @State private var monthStart = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var events: [LocalEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let calendar = Calendar.current
    private let eventService: PublishedEventFetching = SupabaseEventService()

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        monthGrid
                        selectedDaySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, PCCKeyboardSpacing.homeBottomPadding)
                }
                .refreshable {
                    await loadMonth()
                }
            }
            .navigationBarHidden(true)
            .task {
                await loadMonth()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calendar")
                .font(.system(size: 40, weight: .black, design: .serif))
                .foregroundStyle(PCCTheme.ink)

            HStack(spacing: 12) {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.black))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.78), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PCCTheme.ink)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monthTitle)
                        .font(.title2.weight(.black))
                        .foregroundStyle(PCCTheme.ink)

                    Text("Published local listings by date")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.black))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.78), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PCCTheme.ink)
            }
            .padding(16)
            .pccCardStyle()
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.ink.opacity(0.54))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(monthCells.indices, id: \.self) { index in
                    if let day = monthCells[index] {
                        CalendarDayCell(
                            day: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                            isToday: calendar.isDateInToday(day),
                            events: eventsByDay[calendar.startOfDay(for: day)] ?? []
                        ) {
                            selectedDay = calendar.startOfDay(for: day)
                        }
                    } else {
                        Color.clear
                            .frame(height: 68)
                    }
                }
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading published events")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.58))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }

            if let errorMessage {
                VStack(spacing: 10) {
                    Text(errorMessage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.68))
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        Task { await loadMonth() }
                    }
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(PCCTheme.leafGreen, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        }
        .padding(14)
        .pccCardStyle()
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title3.weight(.black))
                    .foregroundStyle(PCCTheme.ink)

                Text(selectedEvents.isEmpty ? "Nothing published for this day yet." : "\(selectedEvents.count) published listing\(selectedEvents.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.62))
            }

            if selectedEvents.isEmpty {
                CalendarEmptyDayCard()
            } else {
                VStack(spacing: 12) {
                    ForEach(selectedEvents) { event in
                        NavigationLink {
                            EventDetailScreen(event: event)
                        } label: {
                            CalendarEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.month(.wide).year())
    }

    private var selectedEvents: [LocalEvent] {
        eventsByDay[selectedDay] ?? []
    }

    private var eventsByDay: [Date: [LocalEvent]] {
        Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var monthCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyCells = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = dayRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        }
        var cells = Array(repeating: Optional<Date>.none, count: leadingEmptyCells) + days.map(Optional.some)

        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return cells
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: monthStart) else {
            return
        }

        monthStart = calendar.startOfMonth(for: nextMonth)
        if !calendar.isDate(selectedDay, equalTo: monthStart, toGranularity: .month) {
            selectedDay = monthStart
        }

        Task {
            await loadMonth()
        }
    }

    @MainActor
    private func loadMonth() async {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            events = try await eventService.fetchPublishedEvents(from: monthInterval.start, to: monthInterval.end)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Calendar events could not be loaded. Please try again soon."
        }
    }
}

private struct CalendarDayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let events: [LocalEvent]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : PCCTheme.ink)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 3) {
                    ForEach(Array(events.prefix(3)), id: \.id) { event in
                        Circle()
                            .fill(event.category.calendarMarkerColor)
                            .frame(width: 5, height: 5)
                    }

                    if events.count > 3 {
                        Text("+")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : PCCTheme.ink.opacity(0.58))
                    }
                }
                .frame(height: 9)
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(cellBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isToday ? PCCTheme.pohutukawaOrange.opacity(0.62) : .white.opacity(0.64), lineWidth: isToday ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var cellBackground: Color {
        if isSelected {
            return PCCTheme.leafGreen
        }

        if isToday {
            return PCCTheme.pohutukawaOrange.opacity(0.10)
        }

        return .white.opacity(events.isEmpty ? 0.54 : 0.80)
    }
}

private struct CalendarEventRow: View {
    let event: LocalEvent

    var body: some View {
        HStack(spacing: 12) {
            DateTile(event: event)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(event.category.shortLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.leafGreen)

                    Text(event.town.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PCCTheme.ink.opacity(0.50))
                }

                Text(event.title)
                    .font(.system(size: 19, weight: .black, design: .serif))
                    .foregroundStyle(PCCTheme.ink)
                    .lineLimit(2)

                Label(event.timeText, systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))

                Label(event.venue, systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PCCTheme.ink.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(PCCTheme.ink.opacity(0.32))
        }
        .padding(14)
        .pccCardStyle()
    }
}

private struct CalendarEmptyDayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2.weight(.bold))
                .foregroundStyle(PCCTheme.pohutukawaOrange)

            Text("No published listings are scheduled for this day.")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.ink)

            Text("New local events will appear here once they are approved.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .pccCardStyle()
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        guard let monthInterval = dateInterval(of: .month, for: date) else {
            return startOfDay(for: date)
        }

        return monthInterval.start
    }
}

private extension EventCategory {
    var calendarMarkerColor: Color {
        switch self {
        case .liveMusic, .nightlife:
            return PCCTheme.pohutukawaOrange
        case .foodDrink, .markets:
            return PCCTheme.pohutukawaRed
        case .kidsFamily, .sport:
            return Color(red: 0.13, green: 0.46, blue: 0.66)
        case .community, .fundraisers:
            return PCCTheme.leafGreen
        case .classesWorkshops, .seniors:
            return Color(red: 0.48, green: 0.36, blue: 0.12)
        case .churchMaraeCultural, .publicNotices:
            return PCCTheme.ink.opacity(0.72)
        }
    }
}
