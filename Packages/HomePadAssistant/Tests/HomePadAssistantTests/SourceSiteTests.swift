import Foundation
import Testing
@testable import HomePadAssistant

/// Source chips name the site a link comes from.
@Suite struct SourceSiteTests {
    private func site(_ text: String) throws -> String {
        SourceSite.name(of: try #require(URL(string: text)))
    }

    @Test func dropsWwwMobileAndLanguagePrefixes() throws {
        #expect(try site("https://en.wikipedia.org/wiki/French_toast") == "wikipedia.org")
        #expect(try site("https://en.m.wikipedia.org/wiki/French_toast") == "wikipedia.org")
        #expect(try site("https://www.seriouseats.com/french-toast") == "seriouseats.com")
    }

    @Test func keepsCountryDomainsAndRealSubdomains() throws {
        #expect(try site("https://www.bbc.co.uk/food") == "bbc.co.uk")
        #expect(try site("https://ab.co.uk") == "ab.co.uk")
        #expect(try site("https://cooking.nytimes.com/recipes/1") == "cooking.nytimes.com")
    }
}
