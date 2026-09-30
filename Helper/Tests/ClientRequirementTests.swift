import Foundation
import Testing

private let hash = "0123456789abcdef0123456789ABCDEF01234567"
private let good = "identifier \"dev.mooring.app\" and certificate leaf = H\"\(hash)\""

struct ClientRequirementTests {
    @Test func loadsWellFormedRequirement() {
        #expect(ClientRequirement.load(from: ["SMAuthorizedClients": [good]]) == good)
    }

    @Test func placeholderFailsClosed() {
        #expect(ClientRequirement.load(from: ["SMAuthorizedClients": ["MOORING_UNSIGNED"]]) == nil)
    }

    @Test func missingKeyOrInfoFailsClosed() {
        #expect(ClientRequirement.load(from: [:]) == nil)
        #expect(ClientRequirement.load(from: nil) == nil)
        #expect(ClientRequirement.load(from: ["SMAuthorizedClients": [String]()]) == nil)
    }

    @Test func otherIdentifierFailsClosed() {
        let cli = good.replacingOccurrences(of: "dev.mooring.app", with: "dev.mooring.cli")
        #expect(ClientRequirement.load(from: ["SMAuthorizedClients": [cli]]) == nil)
    }

    @Test func malformedHashFailsClosed() {
        let short = good.replacingOccurrences(of: hash, with: String(hash.dropLast()))
        #expect(ClientRequirement.load(from: ["SMAuthorizedClients": [short]]) == nil)
    }
}
