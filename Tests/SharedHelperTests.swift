import Foundation
import Testing
@testable import Campfire

@Suite("Site names")
struct DisplayHostTests {
    @Test("Shows the site's name", arguments: [
        ("https://www.example.com/post", "example.com"),
        ("https://example.com/post", "example.com"),
        ("https://blog.example.com", "blog.example.com"),
        ("https://awww.com/cats", "awww.com"),            // "www." only comes off the front
        ("https://www.www.example.com", "www.example.com"),
    ])
    func displayHost(link: String, host: String) throws {
        #expect(try #require(URL(string: link)).displayHost == host)
    }

    @Test func noSiteNoName() throws {
        #expect(try #require(URL(string: "mailto:sam@example.com")).displayHost == nil)
    }

    @Test func entriesUseIt() {
        let capture = Capture(title: "x", url: URL(string: "https://www.example.com/a"), destination: .notion, status: .sent)
        #expect(capture.host == "example.com")
    }
}

@Suite("Service replies")
struct ServiceReplyTests {
    private func reply(_ status: Int, _ message: String? = nil) -> ServiceResponse {
        ServiceResponse(status: status, message: message)
    }

    @Test func successIsNoError() {
        #expect(NotionClient.error(for: reply(200)) == nil)
        #expect(EmailClient.error(for: reply(201)) == nil)
    }

    @Test func notionErrors() {
        #expect(NotionClient.error(for: reply(401))?.localizedDescription == NotionClient.NotionError.unauthorized.localizedDescription)
        #expect(NotionClient.error(for: reply(404))?.localizedDescription == NotionClient.NotionError.databaseNotShared.localizedDescription)
        #expect(NotionClient.error(for: reply(400, "body failed validation"))?.localizedDescription == "Notion said: body failed validation")
        #expect(NotionClient.error(for: reply(500))?.localizedDescription == "Notion said: error 500")
    }

    @Test func emailErrors() {
        #expect(EmailClient.error(for: reply(401))?.localizedDescription == EmailClient.EmailError.unauthorized.localizedDescription)
        #expect(EmailClient.error(for: reply(403, "You can only send testing emails to your own email address"))?.localizedDescription
                == EmailClient.EmailError.notAccountAddress.localizedDescription)
        #expect(EmailClient.error(for: reply(403, "Forbidden"))?.localizedDescription == EmailClient.EmailError.unauthorized.localizedDescription)
        #expect(EmailClient.error(for: reply(422, "Invalid `to` field"))?.localizedDescription == "Resend said: Invalid `to` field")
        #expect(EmailClient.error(for: reply(500))?.localizedDescription == "Resend said: error 500")
    }

    @Test func offlineIsOneMessage() {
        #expect(ServiceError.offline.localizedDescription == "No internet connection. Try again when you're back online.")
    }

    @Test func readsTheServicesMessage() {
        #expect(ServiceRequest.message(in: Data(#"{"message":"Rate limited"}"#.utf8)) == "Rate limited")
        #expect(ServiceRequest.message(in: Data(#"{"message":""}"#.utf8)) == nil)
        #expect(ServiceRequest.message(in: Data("not json".utf8)) == nil)
    }
}
