import Foundation
import Testing
@testable import Campfire

@Suite("Retry message for kept files")
struct RetryMessageTests {
    private func failedEmail(sentFrom: String?) -> Capture {
        Capture(title: "Report", fileNames: ["report.pdf"], sentFrom: sentFrom, destination: .email, status: .failed)
    }

    @Test func sentFromTheOtherDevice() {
        #expect(failedEmail(sentFrom: "iPad").missingFilesMessage(on: "iPhone")
                == "The files are kept on your iPad. Try again there, or share them again.")
        #expect(failedEmail(sentFrom: "iPhone").missingFilesMessage(on: "iPad")
                == "The files are kept on your iPhone. Try again there, or share them again.")
    }

    @Test func sentFromThisDeviceButTheFilesAreGone() {
        #expect(failedEmail(sentFrom: "iPhone").missingFilesMessage(on: "iPhone")
                == "The files are no longer on this iPhone. Share them again to try.")
    }

    @Test func olderEntriesDontKnowTheirDevice() {
        #expect(failedEmail(sentFrom: nil).missingFilesMessage(on: "iPad")
                == "The files are kept on the device that sent this. Try again there, or share them again.")
    }

    @Test func neverSaysPhone() {
        for sender in [nil, "iPhone", "iPad"] {
            for device in ["iPhone", "iPad"] {
                let message = failedEmail(sentFrom: sender).missingFilesMessage(on: device)
                #expect(!message.replacingOccurrences(of: "iPhone", with: "").localizedCaseInsensitiveContains("phone"))
            }
        }
    }
}
