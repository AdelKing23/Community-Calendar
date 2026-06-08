import Foundation

enum SupabaseServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case authFailed
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .authFailed:
            return "Login failed."
        case .requestFailed:
            return "The events service is unavailable."
        }
    }
}

protocol EventListingSubmitting {
    func submitPendingListing(_ draft: PendingListingDraft, accessToken: String) async throws -> UUID
    func uploadListingImage(_ image: ListingPhotoUpload, eventID: UUID, userID: UUID, position: Int, accessToken: String) async throws
}

protocol UserListingFetching {
    func fetchUserListings(userID: UUID, accessToken: String) async throws -> [LocalEvent]
}

protocol EventChangeRequesting {
    func createEditRequest(event: LocalEvent, draft: ListingEditDraft, requesterID: UUID, requesterNote: String?, accessToken: String) async throws
    func createRemovalRequest(event: LocalEvent, requesterID: UUID, requesterNote: String?, accessToken: String) async throws
    func fetchMyChangeRequests(userID: UUID, accessToken: String) async throws -> [EventChangeRequest]
}

protocol PublishedEventFetching {
    func fetchPublishedEvents() async throws -> [LocalEvent]
    func fetchPublishedEvents(from rangeStart: Date, to rangeEnd: Date) async throws -> [LocalEvent]
}

protocol OwnerAuthenticating {
    func signInOwner(email: String, password: String) async throws -> OwnerSession
    func refreshOwnerSession(refreshToken: String) async throws -> OwnerSession
}

protocol OwnerEventReviewing {
    func fetchOwnerEvents(accessToken: String) async throws -> [LocalEvent]
    func updateEventStatus(id: UUID, status: ListingStatus, accessToken: String) async throws
    func fetchSupportChangeRequests(accessToken: String) async throws -> [EventChangeRequest]
    func supportApproveChangeRequest(_ request: EventChangeRequest, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws
    func supportRejectChangeRequest(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws
    func supportMarkApplied(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws
}

struct OwnerSession: Hashable {
    let accessToken: String
    let refreshToken: String
    let email: String?
    let expiresAt: Date?

    var shouldRefreshSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(300)
    }
}

struct SupabaseEventService: EventListingSubmitting, UserListingFetching, EventChangeRequesting, PublishedEventFetching, OwnerAuthenticating, OwnerEventReviewing {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = Self.fractionalISODateFormatter.date(from: value) ?? Self.isoDateFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        encoder.dateEncodingStrategy = .iso8601
    }

    func fetchPublishedEvents() async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "end_at", value: "gte.\(Self.isoDateFormatter.string(from: Date()))"),
            URLQueryItem(name: "order", value: "is_paid_push.desc,is_featured.desc,start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return await events(from: try decoder.decode([SupabaseEventRecord].self, from: data), accessToken: nil, logContext: "public")
    }

    func fetchPublishedEvents(from rangeStart: Date, to rangeEnd: Date) async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "end_at", value: "gte.\(Self.isoDateFormatter.string(from: rangeStart))"),
            URLQueryItem(name: "start_at", value: "lt.\(Self.isoDateFormatter.string(from: rangeEnd))"),
            URLQueryItem(name: "order", value: "start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url))
        try validate(response)
        return await events(from: try decoder.decode([SupabaseEventRecord].self, from: data), accessToken: nil, logContext: "public range")
    }

    func submitPendingListing(_ draft: PendingListingDraft, accessToken: String) async throws -> UUID {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "id")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(PendingEventInsert(draft: draft))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode)
        }

        guard let inserted = try decoder.decode([InsertedEventResponse].self, from: data).first else {
            throw SupabaseServiceError.invalidResponse
        }

        return inserted.id
    }

    func uploadListingImage(_ image: ListingPhotoUpload, eventID: UUID, userID: UUID, position: Int, accessToken: String) async throws {
        let imageID = UUID()
        let storagePath = "\(userID.uuidString.lowercased())/\(eventID.uuidString.lowercased())/\(imageID.uuidString.lowercased()).jpg"

        try await uploadStorageObject(data: image.data, storagePath: storagePath, mimeType: image.mimeType, accessToken: accessToken)
        try await insertEventImageMetadata(
            image: image,
            eventID: eventID,
            storagePath: storagePath,
            position: position,
            accessToken: accessToken
        )
    }

    func fetchUserListings(userID: UUID, accessToken: String) async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "submitted_by", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc,start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return await events(from: try decoder.decode([SupabaseEventRecord].self, from: data), accessToken: accessToken, logContext: "user listings")
    }

    func createEditRequest(
        event: LocalEvent,
        draft: ListingEditDraft,
        requesterID: UUID,
        requesterNote: String?,
        accessToken: String
    ) async throws {
        try await insertChangeRequest(
            EventChangeRequestInsert(
                eventID: event.id,
                requestedBy: requesterID,
                changeType: .editRequest,
                proposedChanges: draft.proposedChanges,
                requesterNote: requesterNote?.trimmed.nilIfEmpty
            ),
            accessToken: accessToken
        )
    }

    func createRemovalRequest(
        event: LocalEvent,
        requesterID: UUID,
        requesterNote: String?,
        accessToken: String
    ) async throws {
        try await insertChangeRequest(
            EventChangeRequestInsert(
                eventID: event.id,
                requestedBy: requesterID,
                changeType: .removalRequest,
                proposedChanges: [:],
                requesterNote: requesterNote?.trimmed.nilIfEmpty
            ),
            accessToken: accessToken
        )
    }

    func fetchMyChangeRequests(userID: UUID, accessToken: String) async throws -> [EventChangeRequest] {
        guard var components = eventChangeRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,events(*,event_images(*))"),
            URLQueryItem(name: "requested_by", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return await changeRequests(from: try decoder.decode([SupabaseEventChangeRequestRecord].self, from: data), accessToken: accessToken)
    }

    func signInOwner(email: String, password: String) async throws -> OwnerSession {
        guard let authURL = SupabaseConfiguration.authURL?.appendingPathComponent("token"),
              var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              SupabaseConfiguration.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "password")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(OwnerPasswordLogin(email: email.trimmed, password: password))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.authFailed
        }

        let token = try decoder.decode(SupabaseAuthTokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken else {
            throw SupabaseServiceError.authFailed
        }

        return OwnerSession(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func refreshOwnerSession(refreshToken: String) async throws -> OwnerSession {
        guard let authURL = SupabaseConfiguration.authURL?.appendingPathComponent("token"),
              var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              SupabaseConfiguration.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(OwnerRefreshLogin(refreshToken: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.authFailed
        }

        let token = try decoder.decode(SupabaseAuthTokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken else {
            throw SupabaseServiceError.authFailed
        }

        return OwnerSession(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func fetchOwnerEvents(accessToken: String) async throws -> [LocalEvent] {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,event_images(*)"),
            URLQueryItem(name: "order", value: "created_at.desc,start_at.asc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        let records = try decoder.decode([SupabaseEventRecord].self, from: data)
        return await events(from: records, accessToken: accessToken, logContext: "owner")
    }

    private func events(from records: [SupabaseEventRecord], accessToken: String?, logContext: String) async -> [LocalEvent] {
        var events: [LocalEvent] = []

        for record in records {
            let imageRecords = record.eventImages ?? []
            let signedImages = await signedEventImages(from: imageRecords, eventID: record.id, accessToken: accessToken)
            if let event = record.localEvent(images: signedImages) {
                events.append(event)
            }
        }

        return events
    }

    func updateEventStatus(id: UUID, status: ListingStatus, accessToken: String) async throws {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(OwnerStatusUpdate(status: status.rawValue))

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func fetchSupportChangeRequests(accessToken: String) async throws -> [EventChangeRequest] {
        guard var components = eventChangeRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "select", value: "*,events(*,event_images(*))"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        let (data, response) = try await session.data(for: request(url: url, accessToken: accessToken))
        try validate(response)
        return await changeRequests(from: try decoder.decode([SupabaseEventChangeRequestRecord].self, from: data), accessToken: accessToken)
    }

    func supportApproveChangeRequest(_ request: EventChangeRequest, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        switch request.changeType {
        case .editRequest:
            try await updateEvent(id: request.eventID, proposedChanges: request.proposedChanges, accessToken: accessToken)
            try await updateChangeRequest(
                id: request.id,
                update: EventChangeRequestUpdate(status: .applied, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: Date()),
                accessToken: accessToken
            )
        case .removalRequest:
            try await updateEventStatus(id: request.eventID, status: .archived, accessToken: accessToken)
            try await updateChangeRequest(
                id: request.id,
                update: EventChangeRequestUpdate(status: .applied, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: Date()),
                accessToken: accessToken
            )
        }
    }

    func supportRejectChangeRequest(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        try await updateChangeRequest(
            id: id,
            update: EventChangeRequestUpdate(status: .rejected, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: nil),
            accessToken: accessToken
        )
    }

    func supportMarkApplied(id: UUID, reviewReason: EventReviewReason, supportNote: String?, accessToken: String) async throws {
        try await updateChangeRequest(
            id: id,
            update: EventChangeRequestUpdate(status: .applied, reviewReason: reviewReason, supportNote: supportNote, reviewedAt: Date(), appliedAt: Date()),
            accessToken: accessToken
        )
    }

    private func insertChangeRequest(_ insert: EventChangeRequestInsert, accessToken: String) async throws {
        guard let url = eventChangeRequestsURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(insert)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func changeRequests(from records: [SupabaseEventChangeRequestRecord], accessToken: String?) async -> [EventChangeRequest] {
        var requests: [EventChangeRequest] = []

        for record in records {
            let eventImages = record.event?.eventImages ?? []
            let signedImages = await signedEventImages(from: eventImages, eventID: record.eventID, accessToken: accessToken)
            requests.append(record.changeRequest(event: record.event?.localEvent(images: signedImages)))
        }

        return requests
    }

    private func updateEvent(id: UUID, proposedChanges: [String: EventChangeValue], accessToken: String) async throws {
        guard var components = eventsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(proposedChanges)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func updateChangeRequest(id: UUID, update: EventChangeRequestUpdate, accessToken: String) async throws {
        guard var components = eventChangeRequestsURLComponents else {
            throw SupabaseServiceError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(update)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func uploadStorageObject(data: Data, storagePath: String, mimeType: String, accessToken: String) async throws {
        guard let url = storageObjectURL(storagePath: storagePath) else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        try validatePhotoUploadResponse(response, data: responseData, step: "storage upload", storagePath: storagePath)
    }

    private func insertEventImageMetadata(
        image: ListingPhotoUpload,
        eventID: UUID,
        storagePath: String,
        position: Int,
        accessToken: String
    ) async throws {
        guard let url = eventImagesURLComponents?.url else {
            throw SupabaseServiceError.notConfigured
        }

        let metadata = EventImageInsert(
            eventID: eventID,
            storagePath: storagePath,
            position: position,
            mimeType: image.mimeType,
            byteSize: image.byteSize,
            width: image.width,
            height: image.height
        )

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(metadata)

        let (responseData, response) = try await session.data(for: request)
        try validatePhotoUploadResponse(response, data: responseData, step: "event_images insert", storagePath: storagePath)
    }

    private func signedEventImages(from records: [SupabaseEventImageRecord], eventID: UUID, accessToken: String?) async -> [EventImage] {
        var images: [EventImage] = []

        for record in records.sorted(by: { $0.position < $1.position }) {
            let signedURL: URL?
            do {
                signedURL = try await signedStorageURL(storagePath: record.storagePath, accessToken: accessToken)
            } catch {
                signedURL = nil
                debugPhotoUpload(
                    step: "signed URL",
                    message: "failed event=\(eventID.redactedForLog), image=\(record.id.redactedForLog), path=\(record.storagePath)"
                )
            }

            images.append(record.eventImage(signedURL: signedURL))
        }

        return images
    }

    private func signedStorageURL(storagePath: String, accessToken: String?) async throws -> URL? {
        guard let url = storageSignURL(storagePath: storagePath) else {
            throw SupabaseServiceError.notConfigured
        }

        var request = request(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(StorageSignRequest(expiresIn: 3600))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            debugPhotoUpload(step: "signed URL", message: "invalid response, path=\(storagePath)")
            throw SupabaseServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable response body>"
            debugPhotoUpload(step: "signed URL", message: "failed status=\(httpResponse.statusCode), path=\(storagePath), body=\(body)")
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode)
        }

        let signed = try decoder.decode(StorageSignedURLResponse.self, from: data)
        guard let signedURL = signed.signedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !signedURL.isEmpty else {
            debugPhotoUpload(step: "signed URL", message: "empty response status=\(httpResponse.statusCode), path=\(storagePath)")
            return nil
        }

        return absoluteSignedStorageURL(from: signedURL)
    }

    private func absoluteSignedStorageURL(from signedURL: String) -> URL? {
        if let absoluteURL = URL(string: signedURL), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let projectURL = SupabaseConfiguration.projectURL else {
            return nil
        }

        let path = signedURL.hasPrefix("/") ? String(signedURL.dropFirst()) : signedURL

        if path.hasPrefix("storage/v1/") {
            return URL(string: path, relativeTo: projectURL)?.absoluteURL
        }

        if path.hasPrefix("object/") {
            return URL(string: "storage/v1/\(path)", relativeTo: projectURL)?.absoluteURL
        }

        return URL(string: "storage/v1/object/sign/listing-images/\(path)", relativeTo: projectURL)?.absoluteURL
    }

    private var eventsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("events"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventImagesURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_images"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private var eventChangeRequestsURLComponents: URLComponents? {
        guard let restURL = SupabaseConfiguration.restURL?.appendingPathComponent("event_change_requests"),
              SupabaseConfiguration.isConfigured else {
            return nil
        }

        return URLComponents(url: restURL, resolvingAgainstBaseURL: false)
    }

    private func storageObjectURL(storagePath: String) -> URL? {
        storagePath.split(separator: "/").reduce(
            SupabaseConfiguration.storageURL?
            .appendingPathComponent("object")
            .appendingPathComponent("listing-images")
        ) { partialURL, pathPart in
            partialURL?.appendingPathComponent(String(pathPart))
        }
    }

    private func storageSignURL(storagePath: String) -> URL? {
        storagePath.split(separator: "/").reduce(
            SupabaseConfiguration.storageURL?
            .appendingPathComponent("object")
            .appendingPathComponent("sign")
            .appendingPathComponent("listing-images")
        ) { partialURL, pathPart in
            partialURL?.appendingPathComponent(String(pathPart))
        }
    }

    private func request(url: URL, accessToken: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? SupabaseConfiguration.publishableKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseServiceError.requestFailed(httpResponse.statusCode)
        }
    }

    private func validatePhotoUploadResponse(_ response: URLResponse, data: Data, step: String, storagePath: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            debugPhotoUpload(step: step, message: "invalid response, path=\(storagePath)")
            throw SupabaseServiceError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return
        }

        let body = String(data: data, encoding: .utf8) ?? "<unreadable response body>"
        debugPhotoUpload(step: step, message: "failed status=\(httpResponse.statusCode), path=\(storagePath), body=\(body)")
        throw SupabaseServiceError.requestFailed(httpResponse.statusCode)
    }

    private func debugPhotoUpload(step: String, message: String) {
        #if DEBUG
        print("[PhotoUpload] \(step): \(message)")
        #endif
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISODateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct SupabaseEventRecord: Decodable {
    let id: UUID
    let title: String
    let category: String
    let town: String
    let venue: String
    let startAt: Date
    let endAt: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String?
    let contactName: String?
    let contactPhone: String?
    let contactEmail: String?
    let isFeatured: Bool
    let isPaidPush: Bool
    let status: String
    let unverifiedUserListing: Bool?
    let eventImages: [SupabaseEventImageRecord]?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case town
        case venue
        case startAt = "start_at"
        case endAt = "end_at"
        case priceLabel = "price_label"
        case isFree = "is_free"
        case audience
        case shortDescription = "short_description"
        case longDescription = "long_description"
        case contactName = "contact_name"
        case contactPhone = "contact_phone"
        case contactEmail = "contact_email"
        case isFeatured = "is_featured"
        case isPaidPush = "is_paid_push"
        case status
        case unverifiedUserListing = "unverified_user_listing"
        case eventImages = "event_images"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func localEvent(images: [EventImage] = []) -> LocalEvent? {
        guard let category = EventCategory(databaseValue: category),
              let town = CoastTown(databaseValue: town),
              let listingStatus = ListingStatus(rawValue: status) else {
            return nil
        }

        return LocalEvent(
            id: id,
            title: title,
            category: category,
            town: town,
            venue: venue,
            startDate: startAt,
            endDate: endAt,
            priceLabel: priceLabel,
            isFree: isFree,
            audience: audience,
            shortDescription: shortDescription,
            longDescription: longDescription ?? shortDescription,
            contactName: contactName,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            isFeatured: isFeatured,
            isPaidPush: isPaidPush,
            listingStatus: listingStatus,
            unverifiedUserListing: unverifiedUserListing ?? false,
            images: images,
            createdAt: createdAt ?? startAt,
            updatedAt: updatedAt
        )
    }
}

struct SupabaseEventImageRecord: Decodable {
    let id: UUID
    let eventID: UUID
    let storagePath: String
    let position: Int
    let mimeType: String
    let byteSize: Int?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case storagePath = "storage_path"
        case position
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case width
        case height
    }

    func eventImage(signedURL: URL?) -> EventImage {
        EventImage(
            id: id,
            eventID: eventID,
            storagePath: storagePath,
            position: position,
            mimeType: mimeType,
            byteSize: byteSize,
            width: width,
            height: height,
            signedURL: signedURL
        )
    }
}

struct SupabaseEventChangeRequestRecord: Decodable {
    let id: UUID
    let eventID: UUID
    let requestedBy: UUID
    let changeType: EventChangeType
    let status: EventChangeRequestStatus
    let proposedChanges: [String: EventChangeValue]
    let requesterNote: String?
    let reviewReason: EventReviewReason?
    let supportNote: String?
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let appliedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let event: SupabaseEventRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case requestedBy = "requested_by"
        case changeType = "change_type"
        case status
        case proposedChanges = "proposed_changes"
        case requesterNote = "requester_note"
        case reviewReason = "review_reason"
        case supportNote = "support_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case appliedAt = "applied_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case event = "events"
    }

    func changeRequest(event: LocalEvent?) -> EventChangeRequest {
        EventChangeRequest(
            id: id,
            eventID: eventID,
            requestedBy: requestedBy,
            changeType: changeType,
            status: status,
            proposedChanges: proposedChanges,
            requesterNote: requesterNote,
            reviewReason: reviewReason,
            supportNote: supportNote,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt,
            appliedAt: appliedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            event: event
        )
    }
}

struct EventChangeRequestInsert: Encodable {
    let eventID: UUID
    let requestedBy: UUID
    let changeType: EventChangeType
    let status: EventChangeRequestStatus = .pending
    let proposedChanges: [String: EventChangeValue]
    let requesterNote: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case requestedBy = "requested_by"
        case changeType = "change_type"
        case status
        case proposedChanges = "proposed_changes"
        case requesterNote = "requester_note"
    }
}

struct EventChangeRequestUpdate: Encodable {
    let status: EventChangeRequestStatus
    let reviewReason: EventReviewReason
    let supportNote: String?
    let reviewedAt: Date?
    let appliedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case reviewReason = "review_reason"
        case supportNote = "support_note"
        case reviewedAt = "reviewed_at"
        case appliedAt = "applied_at"
    }
}

struct OwnerPasswordLogin: Encodable {
    let email: String
    let password: String
}

struct OwnerRefreshLogin: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct SupabaseAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct SupabaseAuthUser: Decodable, Hashable {
    let id: UUID?
    let email: String?
}

struct OwnerStatusUpdate: Encodable {
    let status: String
}

struct InsertedEventResponse: Decodable {
    let id: UUID
}

struct EventImageInsert: Encodable {
    let eventID: UUID
    let storagePath: String
    let position: Int
    let mimeType: String
    let byteSize: Int
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case storagePath = "storage_path"
        case position
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case width
        case height
    }
}

struct StorageSignRequest: Encodable {
    let expiresIn: Int
}

struct StorageSignedURLResponse: Decodable {
    let signedURL: String?
}

struct PendingEventInsert: Encodable {
    let title: String
    let category: String
    let town: String
    let venue: String
    let startAt: Date
    let endAt: Date
    let priceLabel: String
    let isFree: Bool
    let audience: String
    let shortDescription: String
    let longDescription: String
    let contactName: String?
    let contactEmail: String?
    let isFeatured: Bool
    let isPaidPush: Bool
    let status: String

    init(draft: PendingListingDraft) {
        let start = Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: draft.time),
            minute: Calendar.current.component(.minute, from: draft.time),
            second: 0,
            of: draft.date
        ) ?? draft.date

        self.title = draft.title.trimmed
        self.category = draft.category.rawValue
        self.town = draft.town.rawValue
        self.venue = draft.venue.trimmed
        self.startAt = start
        self.endAt = Calendar.current.date(byAdding: .hour, value: 2, to: start) ?? start
        let price = draft.priceLabel.trimmed
        self.priceLabel = price.isEmpty ? "Free" : price
        self.isFree = price.isEmpty || price.localizedCaseInsensitiveContains("free")
        self.audience = "Everyone"
        self.shortDescription = draft.shortDescription.trimmed
        self.longDescription = draft.shortDescription.trimmed
        self.contactName = draft.contactName.trimmed.nilIfEmpty
        self.contactEmail = draft.contactEmail.trimmed.nilIfEmpty
        self.isFeatured = false
        self.isPaidPush = false
        self.status = ListingStatus.pendingReview.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case title
        case category
        case town
        case venue
        case startAt = "start_at"
        case endAt = "end_at"
        case priceLabel = "price_label"
        case isFree = "is_free"
        case audience
        case shortDescription = "short_description"
        case longDescription = "long_description"
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case isFeatured = "is_featured"
        case isPaidPush = "is_paid_push"
        case status
    }
}

private extension EventCategory {
    init?(databaseValue: String) {
        self.init(rawValue: databaseValue)
    }
}

private extension CoastTown {
    init?(databaseValue: String) {
        self.init(rawValue: databaseValue)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension UUID {
    var redactedForLog: String {
        "\(uuidString.prefix(8))..."
    }
}
