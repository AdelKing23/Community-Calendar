import Foundation

enum CommunityArea {
    static let appBrandName = "Community Calendar"
    static let defaultCountryName = "New Zealand"
    static let defaultRegionName = "Auckland"
    static let defaultCouncilName = "Auckland Council"
    static let defaultAreaName = "Pōhutukawa Coast"
    static let defaultLocalities = CoastTown.allCases.filter { $0 != .all }
}
